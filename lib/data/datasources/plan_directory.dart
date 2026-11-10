import 'package:html/parser.dart' as html;

import '../../domain/entities/schedule_entry.dart';
import 'auth_service.dart';
import 'schedule_parser.dart';
import 'schedule_remote_datasource.dart';

String foldSearch(String value) {
  const polish = 'ąćęłńóśźż';
  const ascii = 'acelnoszz';
  var result = value.toLowerCase();
  for (var i = 0; i < polish.length; i++) {
    result = result.replaceAll(polish[i], ascii[i]);
  }
  return result.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool matchesSearch(String value, String query) {
  final folded = foldSearch(value);
  return foldSearch(query).split(' ').every(folded.contains);
}

enum PlanKind { lecturer, room }

class PlanTarget {
  const PlanTarget({required this.name, required this.uri, required this.kind});
  final String name;
  final Uri uri;
  final PlanKind kind;
  String get key =>
      '${uri.queryParameters['typ']}:${uri.queryParameters['id']}';
}

class PlanDirectoryPage {
  const PlanDirectoryPage(this.targets, this.categories);
  final List<PlanTarget> targets;
  final Map<Uri, String> categories;
}

class PlanDirectory {
  const PlanDirectory(this.remote, this.auth);
  final ScheduleRemoteDatasource remote;
  final AuthService auth;
  static final base = Uri.https('planzajec.uek.krakow.pl', '/index.php');

  Future<PlanDirectoryPage> catalogue(PlanKind kind,
      {Uri? page, bool Function()? cancelled}) async {
    final first = await load(kind, page: page);
    final targets = {for (final target in first.targets) target.key: target};
    final pending = Map<Uri, String>.of(first.categories);
    final unavailable = <Uri, String>{};
    final visited = <Uri>{page ?? base};
    while (pending.isNotEmpty &&
        visited.length < 40 &&
        cancelled?.call() != true) {
      final uri = pending.keys.first;
      if (!visited.add(uri)) {
        pending.remove(uri);
        continue;
      }
      // Keep unavailable categories visible so partial results are not lost.
      PlanDirectoryPage next;
      try {
        next = await load(kind, page: uri);
      } catch (_) {
        unavailable[uri] = pending.remove(uri)!;
        break;
      }
      pending.remove(uri);
      for (final target in next.targets) {
        targets.putIfAbsent(target.key, () => target);
      }
      for (final entry in next.categories.entries) {
        if (!visited.contains(entry.key)) pending[entry.key] = entry.value;
      }
    }
    final sorted = targets.values.toList()
      ..sort((a, b) => foldSearch(a.name).compareTo(foldSearch(b.name)));
    return PlanDirectoryPage(sorted, {...unavailable, ...pending});
  }

  static PlanDirectoryPage parse(String source, Uri page, PlanKind kind) {
    final document = html.parse(source);
    final targets = <String, PlanTarget>{};
    final categories = <Uri, String>{};
    final type = kind == PlanKind.lecturer ? 'N' : 'S';
    for (final anchor in document.querySelectorAll('a[href]')) {
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      try {
        final uri = page.resolve(anchor.attributes['href']!);
        if (uri.scheme != 'https' ||
            uri.host != base.host ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            uri.path != base.path ||
            uri.queryParameters['typ'] != type) {
          continue;
        }
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) {
          final target = PlanTarget(
              name: label, uri: uri.replace(fragment: ''), kind: kind);
          targets.putIfAbsent(target.key, () => target);
        } else {
          categories[uri.replace(fragment: '')] = label;
        }
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    return PlanDirectoryPage(targets.values.toList(), categories);
  }

  Future<PlanDirectoryPage> load(PlanKind kind, {Uri? page}) async {
    final credentials = await auth.getCredentials();
    if (credentials == null) throw StateError('Zaloguj się ponownie.');
    final uri = page ?? base;
    final source = await remote.fetchAuthenticatedPlanHtml(
      uri: uri,
      username: credentials.username,
      password: credentials.password,
    );
    final parsed = parse(source, uri, kind);
    // Follow the catalogue landing page, not every lecturer/room schedule.
    if (page == null &&
        parsed.targets.isEmpty &&
        parsed.categories.length == 1) {
      return load(kind, page: parsed.categories.keys.single);
    }
    return parsed;
  }

  Future<List<ScheduleEntry>> schedule(PlanTarget target, int period) async {
    final credentials = await auth.getCredentials();
    if (credentials == null) throw StateError('Zaloguj się ponownie.');
    final uri = target.uri.replace(queryParameters: {
      ...target.uri.queryParameters,
      'okres': '$period',
    });
    final source = await remote.fetchAuthenticatedPlanHtml(
      uri: uri,
      username: credentials.username,
      password: credentials.password,
    );
    return ScheduleParser().parse(
      source,
      target.key,
      GroupType.dean,
      lecturerOverride: target.kind == PlanKind.lecturer ? target.name : null,
      roomOverride: target.kind == PlanKind.room ? target.name : null,
    );
  }
}
