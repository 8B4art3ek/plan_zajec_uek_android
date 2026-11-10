import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/auth_service.dart';
import '../../../data/datasources/uek_login_script.dart';
import '../../../data/datasources/usos_import_parser.dart';
import '../../../data/datasources/plan_cas_session.dart';
import '../../../data/datasources/schedule_group_resolver.dart';
import '../../../data/repositories/schedule_repository_impl.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../../domain/entities/usos_import.dart';
import '../../providers/providers.dart';
import 'navigation_log.dart';
import '../../widgets/app_scroll_view.dart';

const _usosStartUrl = 'https://usosweb.uek.krakow.pl/';
const _deanGroupsUrl =
    'https://usosweb.uek.krakow.pl/kontroler.php?_action=dla_stud/studia/grupyDziekanskie';
const _classGroupsUrl =
    'https://usosweb.uek.krakow.pl/kontroler.php?_action=home/grupy';

const _pageSnapshotScript = r'''
(() => {
  const text = document.body ? document.body.innerText : '';
  const foldedText = text.toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const loginLink = Array.from(document.querySelectorAll('a[href]')).find((link) =>
    String(link.innerText || link.textContent || '').toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .includes('zaloguj sie')
  );
  return JSON.stringify({
    isLogin: Boolean(document.querySelector('input[type="password"]')),
    hasDeanGroupsHeading: foldedText.includes('grupy dziekanskie'),
    hasLoginLink: Boolean(loginLink),
    url: location.href,
    title: document.title
  });
})()
''';

const _clickLoginLinkScript = r'''
(() => {
  const fold = (value) => String(value || '').toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const loginLink = Array.from(document.querySelectorAll('a[href]')).find((link) =>
    fold(link.innerText || link.textContent).includes('zaloguj sie')
  );
  if (!loginLink) return false;
  window.location.assign(loginLink.href);
  return true;
})()
''';

const _scanUsosGroupsScript = r'''
(() => {
  function clean(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  const rawText = document.body ? document.body.innerText : '';
  const foldedText = rawText.toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const deanCodes = Array.from(
    foldedText.matchAll(
      /grupa\s+dziekanska\s*:\s*(?:[a-z0-9-]+\s*)?\[([a-z0-9-]+)\]/gi
    )
  ).map((match) => match[1].toUpperCase());
  const rows = Array.from(
    document.querySelectorAll('tr, li, section, article, div, p, td, th, dt, dd')
  )
    .map((node) => clean(node.innerText || node.textContent))
    .filter((value) => value.length >= 4 && value.length <= 600);

  return JSON.stringify({
    url: location.href,
    title: document.title,
    text: rawText.slice(0, 200000),
    rows: Array.from(new Set(rows)).slice(0, 1200),
    deanCodes: Array.from(new Set(deanCodes))
  });
})()
''';

class UsosImportScreen extends ConsumerStatefulWidget {
  UsosImportScreen({super.key});

  @override
  ConsumerState<UsosImportScreen> createState() => _UsosImportScreenState();
}

enum _ImportStep {
  deanNavigation,
  languageNavigation,
  languageResults,
}

class _UsosImportScreenState extends ConsumerState<UsosImportScreen> {
  late final WebViewController _controller;
  final _parser = UsosImportParser();
  final Set<String> _selectedGroupKeys = {};

  Credentials? _credentials;
  UsosImportData? _scan;
  UsosImportData? _deanScan;
  UsosImportResult? _resolution;
  String? _error;
  String _status = 'Przygotowuje import z USOS.';
  bool _isHandlingPage = false;
  bool _isImporting = false;
  bool _isResolving = false;
  bool _completedScan = false;
  int _loginAttempts = 0;
  bool _openedLoginPage = false;
  final List<String> _navigationLog = [];
  _ImportStep _step = _ImportStep.deanNavigation;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _recordNavigation('Otwieram: $url'),
          onPageFinished: _handlePageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted && !_completedScan) {
              setState(() => _error = error.description);
            }
          },
        ),
      );
    _startImport();
  }

  Future<void> _startImport() async {
    final credentials = await ref.read(authServiceProvider).getCredentials();
    if (!mounted) return;
    if (credentials == null) {
      setState(() {
        _error = 'Brak zapisanych danych logowania do USOS.';
        _status = 'Zaloguj sie ponownie w aplikacji i sprobuj jeszcze raz.';
      });
      return;
    }

    setState(() {
      _credentials = credentials;
      _error = null;
      _scan = null;
      _deanScan = null;
      _resolution = null;
      _completedScan = false;
      _loginAttempts = 0;
      _openedLoginPage = false;
      _navigationLog.clear();
      _step = _ImportStep.deanNavigation;
      _status = 'Loguje do USOS tymi samymi danymi co aplikacja.';
    });
    await _loadUsosPage(_usosStartUrl);
  }

  Future<void> _handlePageFinished(String _) async {
    if (!mounted || _isHandlingPage || _completedScan || _credentials == null) {
      return;
    }
    _recordNavigation('Zaladowano: $_');
    _isHandlingPage = true;

    try {
      final snapshot = _decodeMap(
        await _controller.runJavaScriptReturningResult(_pageSnapshotScript),
      );
      if (snapshot['hasLoginLink'] == true && !_openedLoginPage) {
        _openedLoginPage = true;
        _recordNavigation('Klikam: Zaloguj sie');
        if (mounted) setState(() => _status = 'Otwieram logowanie do USOS.');
        await _controller.runJavaScript(_clickLoginLinkScript);
        return;
      }
      if (snapshot['isLogin'] == true) {
        if (_loginAttempts >= 2) {
          throw Exception('USOS nie przyjal danych logowania.');
        }
        _loginAttempts++;
        _recordNavigation('Wysylam zapisane dane logowania');
        if (mounted) setState(() => _status = 'Loguje do USOS.');
        final submitted = await _controller.runJavaScriptReturningResult(
          buildUekLoginScript(_credentials!),
        );
        if (submitted != true) {
          throw Exception(
              'Nie znaleziono bezpiecznego formularza logowania UEK.');
        }
        return;
      }

      await _continueImport();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Nie udalo sie pobrac grup z USOS.';
        });
      }
    } finally {
      _isHandlingPage = false;
    }
  }

  Future<void> _continueImport() async {
    switch (_step) {
      case _ImportStep.deanNavigation:
        _step = _ImportStep.languageNavigation;
        if (mounted) {
          setState(() => _status = 'Pobieram grupy dziekanskie.');
        }
        await _loadUsosPage(_deanGroupsUrl);
        return;
      case _ImportStep.languageNavigation:
        await _verifyDeanGroupsPage();
        _deanScan = await _scanCurrentPage();
        if (_deanScan!.deanCodes.isEmpty) {
          throw Exception(
            'Strona Grup dziekanskich zostala otwarta, ale nie znaleziono na niej wpisu "Grupa dziekanska: ... [...]".',
          );
        }
        _step = _ImportStep.languageResults;
        if (mounted) setState(() => _status = 'Otwieram grupy zajeciowe.');
        await _loadUsosPage(_classGroupsUrl);
        return;
      case _ImportStep.languageResults:
        await _finishImport();
        return;
    }
  }

  Future<UsosImportData> _scanCurrentPage() async {
    return _parser.parseWebViewResult(
      await _controller.runJavaScriptReturningResult(_scanUsosGroupsScript),
    );
  }

  void _recordNavigation(String message) {
    if (!mounted) return;
    final safeMessage = message.replaceFirst(RegExp(r'\?.*$'), '');
    setState(() {
      _navigationLog.add(safeMessage);
      if (_navigationLog.length > 12) _navigationLog.removeAt(0);
    });
  }

  Future<void> _loadUsosPage(String url) {
    return _controller.loadRequest(_parseUsosUri(url));
  }

  Uri _parseUsosUri(String url) {
    try {
      return Uri.parse(url);
    } on ArgumentError {
      final sanitized = url.replaceAllMapped(
        RegExp(r'%(?![0-9a-fA-F]{2})'),
        (_) => '%25',
      );
      return Uri.parse(sanitized);
    }
  }

  Future<void> _verifyDeanGroupsPage() async {
    var snapshot = await _readPageSnapshot();
    if (snapshot['hasDeanGroupsHeading'] == true) return;

    await Future<void>.delayed(Duration(milliseconds: 700));
    snapshot = await _readPageSnapshot();
    if (snapshot['hasDeanGroupsHeading'] == true) return;

    if (snapshot['isLogin'] == true) {
      throw Exception('Logowanie do USOS nie powiodlo sie.');
    }
    final title = (snapshot['title'] as String? ?? '').trim();
    throw Exception(
      title.isEmpty
          ? 'USOS nie otworzyl strony Grup dziekanskich.'
          : 'USOS nie otworzyl strony Grup dziekanskich (aktualna strona: $title).',
    );
  }

  Future<Map<String, dynamic>> _readPageSnapshot() async {
    return _decodeMap(
      await _controller.runJavaScriptReturningResult(_pageSnapshotScript),
    );
  }

  Future<void> _finishImport() async {
    if (mounted) setState(() => _status = 'Dopasowuje grupy do planu UEK.');
    _recordNavigation('Skanuje grupy jezykowe');
    final languageScan = await _scanCurrentPage();
    final deanScan = _deanScan;
    if (deanScan == null || deanScan.deanCodes.isEmpty) {
      throw Exception('USOS nie zwrocil grup dziekanskich.');
    }
    final scan = UsosImportData(
      deanCodes: deanScan.deanCodes,
      languageGroups: languageScan.languageGroups,
      pageUrl: languageScan.pageUrl,
      pageTitle: languageScan.pageTitle,
    );
    _recordNavigation(
      'Znaleziono: ${scan.deanCodes.length} dziekanskie, ${scan.languageGroups.length} jezykowe',
    );
    _recordNavigation('Szukam tych grup na planie UEK');
    if (!mounted) return;
    setState(() => _scan = scan);
    await _resolveScannedGroups();
  }

  Future<void> _resolveScannedGroups() async {
    final scan = _scan;
    if (scan == null || _isResolving) return;
    setState(() {
      _isResolving = true;
      _error = null;
      _status = 'Grupy pobrano z USOS. Dopasowuję je do planu UEK.';
    });
    try {
      final resolution =
          await ref.read(scheduleRepositoryProvider).resolveUsosGroups(scan);
      if (!mounted) return;
      setState(() {
        _resolution = resolution;
        _selectedGroupKeys
          ..clear()
          ..addAll(resolution.imported.map(_groupKey));
        _completedScan = true;
        _error = null;
        _status = resolution.imported.isEmpty
            ? 'Grupy pobrano z USOS, ale nie znaleziono ich w katalogu planu UEK.'
            : 'Wybierz grupy, które chcesz dodać do planu.';
      });
    } catch (error) {
      if (!mounted) return;
      if (error is PlanLoginException) {
        for (final step in error.steps) {
          _recordNavigation(step);
        }
      }
      setState(() {
        _completedScan = true;
        _status = 'Grupy zostały poprawnie pobrane z USOS.';
        _error = switch (error) {
          PlanLoginException() => error.message,
          PlanCatalogException() =>
            'Połączono ze stroną planu UEK, ale nie udało się odczytać katalogu grup. '
                'Możliwa jest zmiana układu strony.',
          TimeoutException() =>
            'Przekroczono czas oczekiwania na plan UEK lub logowanie CAS. Ponów dopasowanie.',
          _ => 'Nie udało się pobrać katalogu planu UEK. Ponów dopasowanie.',
        };
      });
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _importSelected() async {
    final resolution = _resolution;
    if (resolution == null || _isImporting) return;
    final selected = resolution.imported
        .where((group) => _selectedGroupKeys.contains(_groupKey(group)))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final repository = ref.read(scheduleRepositoryProvider);
    final planPeriod = await _choosePlanPeriod(repository);
    if (planPeriod == null || !mounted) return;

    setState(() => _isImporting = true);
    try {
      await repository.setPlanPeriod(planPeriod);
      final result = await repository.importResolvedUsosGroups(selected);
      ref.invalidate(groupsProvider);
      ref.invalidate(todayScheduleProvider);
      ref.invalidate(refreshInfoProvider);
      if (!mounted) return;

      final failures = result.refreshFailures.length;
      final message = failures == 0
          ? 'Dodano ${result.importedCount} grup.'
          : 'Dodano ${result.importedCount} grup, bledy pobierania: $failures.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nie udalo sie dodac grup: $error'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<int?> _choosePlanPeriod(ScheduleRepository repository) async {
    final currentPeriod = await repository.getPlanPeriod();
    if (!mounted) return null;

    return showDialog<int>(
      context: context,
      builder: (context) => _PlanPeriodDialog(initialPeriod: currentPeriod),
    );
  }

  Map<String, dynamic> _decodeMap(Object value) {
    Object decoded = value;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw FormatException('Nieprawidlowy wynik z USOS.');
  }

  String _groupKey(ResolvedUsosGroup group) =>
      '${group.groupType.index}:${group.scheduleId}';

  @override
  Widget build(BuildContext context) {
    final resolution = _resolution;
    final candidates = resolution?.imported ?? const <ResolvedUsosGroup>[];
    final selectedCount = candidates
        .where((group) => _selectedGroupKeys.contains(_groupKey(group)))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Import z USOS'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded),
            tooltip: 'Sprobuj ponownie',
            onPressed: _isImporting || _isResolving ? null : _startImport,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppScrollView(
                  child: ListView(
                children: [
                  _ImportStatus(status: _status, error: _error),
                  if (_navigationLog.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Text(
                      'Przebieg importu',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    NavigationLog(entries: _navigationLog),
                  ],
                  if (_scan != null) ...[
                    SizedBox(height: 16),
                    Text(
                      'Znalezione w USOS: ${_scan!.deanCodes.length} dziekańskie, ${_scan!.languageGroups.length} językowe',
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (resolution != null && candidates.isEmpty) ...[
                    SizedBox(height: 20),
                    Text(
                      'Nie znaleziono dopasowań w odczytanym katalogu. Nie oznacza to, że nie należysz do tych grup w USOS.',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ],
                  if (_scan != null &&
                      (_resolution == null || candidates.isEmpty)) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isResolving ? null : _resolveScannedGroups,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_isResolving
                          ? 'Dopasowywanie…'
                          : 'Ponów dopasowanie do planu UEK'),
                    ),
                  ],
                  if (candidates.isNotEmpty) ...[
                    SizedBox(height: 20),
                    Text(
                      'Wybierz grupy do dodania',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    for (final group in candidates) ...[
                      _SelectableGroupTile(
                        group: group,
                        selected: _selectedGroupKeys.contains(_groupKey(group)),
                        onChanged: (selected) => setState(() {
                          if (selected) {
                            _selectedGroupKeys.add(_groupKey(group));
                          } else {
                            _selectedGroupKeys.remove(_groupKey(group));
                          }
                        }),
                      ),
                      SizedBox(height: 8),
                    ],
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: selectedCount == 0 || _isImporting
                            ? null
                            : _importSelected,
                        icon: _isImporting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : Icon(Icons.add_circle_outline_rounded),
                        label: Text('Dodaj wybrane ($selectedCount)'),
                      ),
                    ),
                  ],
                ],
              )),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0,
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanPeriodDialog extends StatefulWidget {
  _PlanPeriodDialog({required this.initialPeriod});

  final int initialPeriod;

  @override
  State<_PlanPeriodDialog> createState() => _PlanPeriodDialogState();
}

class _PlanPeriodDialogState extends State<_PlanPeriodDialog> {
  late int _period = widget.initialPeriod;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text('Okres planu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Wybierz okres, z którego pobrać zajęcia.'),
          ),
          SizedBox(height: 8),
          for (final period in ScheduleRepository.planPeriods)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Okres $period'),
              trailing: Icon(
                _period == period
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: _period == period
                    ? AppColors.primary
                    : AppColors.onSurfaceMuted,
              ),
              onTap: () => setState(() => _period = period),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Anuluj'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_period),
          child: Text('Dodaj grupy'),
        ),
      ],
    );
  }
}

class _ImportStatus extends StatelessWidget {
  final String status;
  final String? error;

  _ImportStatus({required this.status, required this.error});

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.error.withValues(alpha: 0.14)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? AppColors.error.withValues(alpha: 0.45)
              : AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasError ? Icons.error_outline_rounded : Icons.sync_rounded,
            color: hasError ? AppColors.error : AppColors.primary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              error == null ? status : '$status\n$error',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableGroupTile extends StatelessWidget {
  final ResolvedUsosGroup group;
  final bool selected;
  final ValueChanged<bool> onChanged;

  _SelectableGroupTile({
    required this.group,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        activeColor: AppColors.primary,
        controlAffinity: ListTileControlAffinity.trailing,
        title: Text(
          group.scheduleCode,
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${group.groupType.label} - ${group.sourceLabel}',
          style: TextStyle(
            color: AppColors.onSurfaceMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
