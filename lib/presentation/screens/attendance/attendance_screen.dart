import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/attendance_loader.dart';
import '../../../data/datasources/attendance_parser.dart';
import '../../../data/datasources/uek_login_script.dart';
import '../../providers/providers.dart';
import '../../widgets/app_scroll_view.dart';
import '../../widgets/failure_view.dart';
import 'attendance_qr_screen.dart';

const _attendanceUrl =
    'https://portal.uek.krakow.pl/dashboard/obecnosci/mojeObecnosci';

const _attendanceSnapshotScript = r'''
(() => {
  const clean = (value) => String(value || '').split('\n')
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean).join('\n');
  const passwordInput = document.querySelector('input[type="password"]');
  const tables = Array.from(document.querySelectorAll('table'))
    .map((table) => {
      const headerCells = Array.from(table.querySelectorAll('thead th'));
      const firstRowHeaders = headerCells.length
        ? headerCells
        : Array.from(table.querySelectorAll('tr:first-child th'));
      const headers = firstRowHeaders.map((cell) => clean(cell.innerText || cell.textContent));
      const rows = Array.from(table.querySelectorAll('tbody tr')).map((row) =>
        Array.from(row.querySelectorAll('td')).map((cell) => clean(cell.innerText || cell.textContent))
      ).filter((row) => row.length === headers.length && row.some(Boolean));
      const isEmpty = Boolean(table.querySelector('.dataTables_empty, .dt-empty')) ||
        Array.from(table.querySelectorAll('tbody td[colspan]')).some((cell) =>
          /brak (danych|obecności|wpisów)|nie znaleziono/i.test(cell.innerText || cell.textContent || '')
        );
      return { headers, rows, isEmpty };
    })
    .filter((table) =>
      table.headers.some((header) => /identyfikator|przedmiot/i.test(header)) &&
      table.headers.some((header) => /status/i.test(header))
    )
    .sort((a, b) => b.rows.length - a.rows.length);
  const attendanceTable = tables[0] || { headers: [], rows: [] };
  const currentPage = Number(new URL(location.href).searchParams.get('page') || 1);
  const nextPages = Array.from(document.querySelectorAll('a[href]'))
    .map((link) => { try { return new URL(link.href, location.href); } catch (_) { return null; } })
    .filter((url) => url && url.protocol === 'https:' &&
      url.hostname === 'portal.uek.krakow.pl' &&
      url.pathname === '/dashboard/obecnosci/mojeObecnosci' &&
      (!url.port || url.port === '443') && !url.username && !url.password &&
      Number(url.searchParams.get('page') || 1) > currentPage)
    .sort((a, b) => Number(a.searchParams.get('page')) - Number(b.searchParams.get('page')));
  return JSON.stringify({
    title: document.title || '',
    url: location.href,
    documentId: String(performance.timeOrigin),
    isReady: document.readyState !== 'loading',
    isLogin: Boolean(passwordInput),
    isEmpty: Boolean(attendanceTable.isEmpty),
    headers: attendanceTable.headers,
    rows: attendanceTable.rows,
    nextPageUrl: nextPages.length ? nextPages[0].href : null,
  });
})()
''';

class AttendanceScreen extends ConsumerStatefulWidget {
  AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late final WebViewController _controller;
  late final AttendanceLoader _loader;
  final _parser = AttendanceParser();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    final ready = _configureWebView();
    _loader = AttendanceLoader(
      firstPage: Uri.parse(_attendanceUrl),
      readCredentials: () => ref.read(authServiceProvider).getCredentials(),
      openPage: (forceReload) async {
        await ready;
        if (forceReload) await _controller.clearCache();
        await _controller.loadRequest(
          Uri.parse(_attendanceUrl),
          headers: forceReload
              ? const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'}
              : const {},
        );
      },
      openNextPage: (url) async {
        await ready;
        await _controller.loadRequest(url);
      },
      readSnapshot: () async => _parser.parseWebViewResult(
        await _controller
            .runJavaScriptReturningResult(_attendanceSnapshotScript),
      ),
      submitLogin: (credentials) async =>
          await _controller.runJavaScriptReturningResult(
            buildUekLoginScript(credentials),
          ) ==
          true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loader.load());
    });
  }

  Future<void> _configureWebView() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(AppColors.background);
  }

  Future<void> _scanAttendance() async {
    final uri = await Navigator.of(context).push<Uri>(
        MaterialPageRoute(builder: (_) => const AttendanceQrScreen()));
    if (uri == null || !mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AttendanceRegistrationScreen(url: uri)));
    if (mounted) unawaited(_loader.load(forceReload: true));
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loader,
      builder: (context, _) {
        final state = _loader.state;
        final snapshot = state.snapshot;
        final semesters = snapshot?.semesters ?? const <AttendanceSemester>[];
        return Scaffold(
          appBar: AppBar(
            title: Text('Moje obecności'),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh_rounded),
                tooltip: 'Odśwież obecności',
                onPressed: state.loading
                    ? null
                    : () => _loader.load(forceReload: true),
              ),
            ],
          ),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: _scanAttendance,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Skanuj obecność')))),
            Expanded(
                child: Stack(
              children: [
                Positioned(
                  key: const ValueKey('attendance-webview'),
                  left: 0,
                  bottom: 0,
                  width: 1,
                  height: 1,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0,
                      child: WebViewWidget(controller: _controller),
                    ),
                  ),
                ),
                if (state.loading)
                  Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          const SizedBox(height: 16),
                          Text(state.status, textAlign: TextAlign.center),
                        ])),
                  )
                else if (state.error != null)
                  _AttendanceError(
                    status: state.status,
                    error: state.error!,
                    onRetry: () => _loader.load(forceReload: true),
                  )
                else if (snapshot != null)
                  RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    onRefresh: () => _loader.load(forceReload: true),
                    child: AppScrollView(
                        child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: semesters.isEmpty ? 1 : semesters.length,
                      separatorBuilder: (_, __) => SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (semesters.isEmpty) {
                          return Text(
                            'Brak obecności.',
                            style: TextStyle(
                              color: AppColors.onSurfaceMuted,
                              fontSize: 13,
                            ),
                          );
                        }
                        final semester = semesters[index];
                        return ExpansionTile(
                          key: ValueKey(semester.code ?? 'unknown-semester'),
                          initiallyExpanded: index == 0,
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(semester.label),
                          subtitle:
                              Text('Przedmioty: ${semester.subjects.length}'),
                          children: [
                            for (final subject in semester.subjects)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _AttendanceSubjectTile(
                                  subject: subject,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AttendanceSubjectScreen(
                                        subject: subject,
                                        semesterLabel: semester.label,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    )),
                  ),
              ],
            )),
          ]),
        );
      },
    );
  }
}

class _AttendanceSubjectTile extends StatelessWidget {
  _AttendanceSubjectTile({required this.subject, required this.onTap});

  final AttendanceSubject subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        title: Text(
          subject.name,
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${subject.records.length} wpisy · ${subject.registeredCount} zarejestrowane',
            style: TextStyle(color: AppColors.onSurfaceMuted),
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class AttendanceSubjectScreen extends StatelessWidget {
  AttendanceSubjectScreen(
      {super.key, required this.subject, this.semesterLabel});

  final AttendanceSubject subject;
  final String? semesterLabel;

  @override
  Widget build(BuildContext context) {
    final recordsByType = <String, List<AttendanceRecord>>{};
    for (final record in subject.records) {
      final type = record.classType.isEmpty ? 'Inne zajęcia' : record.classType;
      recordsByType.putIfAbsent(type, () => []).add(record);
    }
    final showTypeSections = recordsByType.length > 1;

    return Scaffold(
      appBar: AppBar(title: Text(subject.name)),
      body: AppScrollView(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (semesterLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(semesterLabel!,
                  style: TextStyle(color: AppColors.onSurfaceMuted)),
            ),
          ...showTypeSections
              ? [
                  for (final entry in recordsByType.entries) ...[
                    _AttendanceSection(
                      title: entry.key,
                      records: entry.value,
                    ),
                    if (entry.key != recordsByType.keys.last)
                      SizedBox(height: 22),
                  ],
                ]
              : [
                  for (final record in subject.records) ...[
                    _AttendanceRecordCard(record: record),
                    if (record != subject.records.last) SizedBox(height: 10),
                  ],
                ],
        ],
      )),
    );
  }
}

class _AttendanceSection extends StatelessWidget {
  _AttendanceSection({
    required this.title,
    required this.records,
  });

  final String title;
  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10),
        for (final record in records) ...[
          _AttendanceRecordCard(record: record),
          if (record != records.last) SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AttendanceRecordCard extends StatelessWidget {
  _AttendanceRecordCard({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.classDetails.isNotEmpty)
              Text(
                record.classDetails,
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (record.classDetails.isNotEmpty) SizedBox(height: 10),
            _AttendanceValue(
              icon: Icons.event_available_rounded,
              label: 'Data rejestracji',
              value: record.registeredAt,
            ),
            SizedBox(height: 8),
            _AttendanceValue(
              icon: Icons.schedule_rounded,
              label: 'Termin otwarcia',
              value: record.openedAt,
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  record.isRegistered
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: record.isRegistered
                      ? AppColors.success
                      : AppColors.onSurfaceMuted,
                  size: 18,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    record.status.isEmpty ? 'Brak statusu' : record.status,
                    style: TextStyle(
                      color: record.isRegistered
                          ? AppColors.success
                          : AppColors.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceValue extends StatelessWidget {
  _AttendanceValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.onSurfaceMuted),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted,
                  fontSize: 11,
                ),
              ),
              Text(
                value.isEmpty ? 'Brak danych' : value,
                style: TextStyle(color: AppColors.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttendanceError extends StatelessWidget {
  _AttendanceError({
    required this.status,
    required this.error,
    required this.onRetry,
  });

  final String status;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FailureView(error: error, onRetry: onRetry);
  }
}
