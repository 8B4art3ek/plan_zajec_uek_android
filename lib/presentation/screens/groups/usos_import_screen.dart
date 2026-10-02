import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/auth_service.dart';
import '../../../data/datasources/usos_import_parser.dart';
import '../../../domain/entities/schedule_entry.dart';
import '../../../domain/entities/usos_import.dart';
import '../../providers/providers.dart';

const _usosStartUrl = 'https://usosweb.uek.krakow.pl/';
const _deanGroupsUrl =
    'https://usosweb.uek.krakow.pl/kontroler.php?_action=dla_stud/studia/grupyDziekanskie';

const _pageSnapshotScript = r'''
(() => {
  return JSON.stringify({
    isLogin: Boolean(document.querySelector('input[type="password"]'))
  });
})()
''';

const _scanUsosGroupsScript = r'''
(() => {
  function clean(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  const text = clean(document.body ? document.body.innerText : '');
  const rows = Array.from(document.querySelectorAll('tr, li, section, article, div'))
    .map((node) => clean(node.innerText || node.textContent))
    .filter((value) => value.length >= 4 && value.length <= 600);

  return JSON.stringify({
    url: location.href,
    title: document.title,
    text: text.slice(0, 200000),
    rows: Array.from(new Set(rows)).slice(0, 1200)
  });
})()
''';

class UsosImportScreen extends ConsumerStatefulWidget {
  const UsosImportScreen({super.key});

  @override
  ConsumerState<UsosImportScreen> createState() => _UsosImportScreenState();
}

enum _ImportStep {
  deanNavigation,
  languageNavigation,
  languageGroups,
  languageYear,
  languageScan,
  languageResults,
}

class _UsosImportScreenState extends ConsumerState<UsosImportScreen> {
  late final WebViewController _controller;
  final _parser = const UsosImportParser();
  final Set<String> _selectedGroupKeys = {};

  Credentials? _credentials;
  UsosImportData? _scan;
  UsosImportData? _deanScan;
  UsosImportResult? _resolution;
  String? _error;
  String _status = 'Przygotowuje import z USOS.';
  bool _isHandlingPage = false;
  bool _isImporting = false;
  bool _completedScan = false;
  int _loginAttempts = 0;
  _ImportStep _step = _ImportStep.deanNavigation;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _handlePageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
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
      _step = _ImportStep.deanNavigation;
      _status = 'Loguje do USOS tymi samymi danymi co aplikacja.';
    });
    await _controller.loadRequest(Uri.parse(_usosStartUrl));
  }

  Future<void> _handlePageFinished(String _) async {
    if (!mounted || _isHandlingPage || _completedScan || _credentials == null) {
      return;
    }
    _isHandlingPage = true;

    try {
      final snapshot = _decodeMap(
        await _controller.runJavaScriptReturningResult(_pageSnapshotScript),
      );
      if (snapshot['isLogin'] == true) {
        if (_loginAttempts >= 2) {
          throw Exception('USOS nie przyjal danych logowania.');
        }
        _loginAttempts++;
        if (mounted) setState(() => _status = 'Loguje do USOS.');
        await _controller.runJavaScript(_loginScript(_credentials!));
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
        await _controller.loadRequest(Uri.parse(_deanGroupsUrl));
        return;
      case _ImportStep.languageNavigation:
        _deanScan = await _scanCurrentPage();
        _step = _ImportStep.languageGroups;
        if (mounted) setState(() => _status = 'Otwieram Moj USOSweb.');
        await _controller.loadRequest(Uri.parse(_usosStartUrl));
        return;
      case _ImportStep.languageGroups:
        await _followLink(
          const ['moj usosweb'],
          nextStep: _ImportStep.languageYear,
          status: 'Otwieram Moj USOSweb.',
        );
        return;
      case _ImportStep.languageYear:
        await _followLink(
          const ['grupy zajeciowe'],
          nextStep: _ImportStep.languageScan,
          status: 'Otwieram Grupy zajeciowe.',
        );
        return;
      case _ImportStep.languageScan:
        await _chooseAcademicYear();
        return;
      case _ImportStep.languageResults:
        await _finishImport();
        return;
    }
  }

  Future<void> _followLink(
    List<String> terms, {
    required _ImportStep nextStep,
    required String status,
  }) async {
    final raw = await _controller.runJavaScriptReturningResult(
      _findLinkScript(terms),
    );
    final link = _decodeMap(raw)['url'] as String?;
    if (link == null || link.isEmpty) {
      throw Exception('Nie znalazlem pozycji "${terms.join(' ')}" w USOS.');
    }
    _step = nextStep;
    if (mounted) setState(() => _status = status);
    await _controller.loadRequest(Uri.parse(link));
  }

  Future<void> _chooseAcademicYear() async {
    final year = _academicYearLabel();
    final raw = await _controller.runJavaScriptReturningResult(
      _chooseAcademicYearScript(year),
    );
    final result = _decodeMap(raw);
    final link = result['url'] as String?;
    final submitted = result['submitted'] == true;
    if (link == null && !submitted) {
      throw Exception('Nie znalazlem roku akademickiego $year w USOS.');
    }
    _step = _ImportStep.languageResults;
    if (mounted) {
      setState(() => _status = 'Pobieram grupy jezykowe z roku $year.');
    }
    if (link != null) {
      await _controller.loadRequest(Uri.parse(link));
      return;
    }
    // The select form has submitted itself and will trigger onPageFinished.
  }

  Future<UsosImportData> _scanCurrentPage() async {
    return _parser.parseWebViewResult(
      await _controller.runJavaScriptReturningResult(_scanUsosGroupsScript),
    );
  }

  String _findLinkScript(List<String> terms) {
    final encodedTerms = jsonEncode(terms);
    return '''
(() => {
  const terms = $encodedTerms;
  const fold = (value) => String(value || '').toLowerCase()
    .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
  const link = Array.from(document.querySelectorAll('a[href]')).find((item) => {
    const text = fold(item.innerText || item.textContent);
    return terms.every((term) => text.includes(term));
  });
  return JSON.stringify({
    url: link ? new URL(link.getAttribute('href'), location.href).href : null
  });
})()
''';
  }

  String _chooseAcademicYearScript(String year) {
    final encodedYear = jsonEncode(year);
    return '''
(() => {
  const year = $encodedYear;
  const fold = (value) => String(value || '').toLowerCase()
    .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
  const link = Array.from(document.querySelectorAll('a[href]')).find((item) =>
    fold(item.innerText || item.textContent).includes(fold(year))
  );
  if (link) {
    return JSON.stringify({
      url: new URL(link.getAttribute('href'), location.href).href,
      submitted: false
    });
  }
  const select = Array.from(document.querySelectorAll('select')).find((item) =>
    Array.from(item.options).some((option) => fold(option.text).includes(fold(year)))
  );
  if (!select) return JSON.stringify({ url: null, submitted: false });
  const option = Array.from(select.options).find((item) =>
    fold(item.text).includes(fold(year))
  );
  select.value = option.value;
  select.dispatchEvent(new Event('change', { bubbles: true }));
  if (select.form) {
    if (typeof select.form.requestSubmit === 'function') select.form.requestSubmit();
    else select.form.submit();
    return JSON.stringify({ url: null, submitted: true });
  }
  return JSON.stringify({ url: null, submitted: false });
})()
''';
  }

  String _academicYearLabel() {
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    return '$startYear/${startYear + 1}';
  }

  Future<void> _finishImport() async {
    if (mounted) setState(() => _status = 'Dopasowuje grupy do planu UEK.');
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
    final resolution =
        await ref.read(scheduleRepositoryProvider).resolveUsosGroups(scan);
    if (!mounted) return;
    setState(() {
      _scan = scan;
      _resolution = resolution;
      _selectedGroupKeys
        ..clear()
        ..addAll(resolution.imported.map(_groupKey));
      _completedScan = true;
      _status = 'Wybierz grupy, ktore chcesz dodac do planu.';
    });
  }

  Future<void> _importSelected() async {
    final resolution = _resolution;
    if (resolution == null || _isImporting) return;
    final selected = resolution.imported
        .where((group) => _selectedGroupKeys.contains(_groupKey(group)))
        .toList(growable: false);
    if (selected.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final result = await ref
          .read(scheduleRepositoryProvider)
          .importResolvedUsosGroups(selected);
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

  String _loginScript(Credentials credentials) {
    final username = jsonEncode(credentials.username);
    final password = jsonEncode(credentials.password);
    return '''
(() => {
  const username = $username;
  const password = $password;
  const passwordInput = document.querySelector('input[type="password"]');
  if (!passwordInput) return false;
  const inputs = Array.from(document.querySelectorAll('input')).filter((input) =>
    input.type !== 'hidden' && input.type !== 'password' &&
    input.type !== 'submit' && input.type !== 'button'
  );
  const usernameInput = inputs.find((input) =>
    /login|user|uid|username|identyfikator/i.test(input.name || input.id || '')
  ) || inputs[0];
  if (!usernameInput) return false;
  for (const [input, value] of [[usernameInput, username], [passwordInput, password]]) {
    input.focus();
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  const form = passwordInput.form;
  if (!form) return false;
  if (typeof form.requestSubmit === 'function') form.requestSubmit();
  else form.submit();
  return true;
})()
''';
  }

  Map<String, dynamic> _decodeMap(Object value) {
    Object decoded = value;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Nieprawidlowy wynik z USOS.');
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
        title: const Text('Import z USOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Sprobuj ponownie',
            onPressed: _isImporting ? null : _startImport,
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImportStatus(status: _status, error: _error),
                if (_scan != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Znalezione w USOS: ${_scan!.deanCodes.length} dziekanskie, ${_scan!.languageGroups.length} jezykowe',
                    style: const TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (resolution != null && candidates.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Nie udalo sie dopasowac zadnej grupy do planu UEK.',
                    style: TextStyle(color: AppColors.warning),
                  ),
                ],
                if (candidates.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Wybierz grupy do dodania',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: candidates.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final group = candidates[index];
                        final key = _groupKey(group);
                        return _SelectableGroupTile(
                          group: group,
                          selected: _selectedGroupKeys.contains(key),
                          onChanged: (selected) => setState(() {
                            if (selected) {
                              _selectedGroupKeys.add(key);
                            } else {
                              _selectedGroupKeys.remove(key);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: selectedCount == 0 || _isImporting
                          ? null
                          : _importSelected,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline_rounded),
                      label: Text('Dodaj wybrane ($selectedCount)'),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
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
    );
  }
}

class _ImportStatus extends StatelessWidget {
  final String status;
  final String? error;

  const _ImportStatus({required this.status, required this.error});

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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error == null ? status : '$status\n$error',
              style: const TextStyle(
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

  const _SelectableGroupTile({
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
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${group.groupType.label} - ${group.sourceLabel}',
          style: const TextStyle(
            color: AppColors.onSurfaceMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
