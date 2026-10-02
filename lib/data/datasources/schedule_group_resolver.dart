import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/usos_import.dart';
import 'schedule_remote_datasource.dart';

class ScheduleGroupResolver {
  static final Uri _baseUri =
      Uri.parse('https://planzajec.uek.krakow.pl/index.php');

  final ScheduleRemoteDatasource remote;

  const ScheduleGroupResolver({required this.remote});

  Future<UsosImportResult> resolve({
    required UsosImportData data,
    required String username,
    required String password,
  }) async {
    final targets = data.toTargets();
    if (targets.isEmpty) {
      return const UsosImportResult(imported: [], unresolved: []);
    }

    final planLinks = await _collectPlanLinks(
      targets: targets,
      username: username,
      password: password,
    );

    final resolved = <ResolvedUsosGroup>[];
    final unresolved = <UnresolvedUsosGroup>[];

    for (final target in targets) {
      final matches = _findMatches(target, planLinks);
      if (matches.isEmpty) {
        unresolved.add(
          UnresolvedUsosGroup(
            groupType: target.groupType,
            sourceLabel: target.sourceLabel,
            scheduleCodeCandidates: target.scheduleCodeCandidates,
          ),
        );
        continue;
      }

      for (final match in matches) {
        resolved.add(ResolvedUsosGroup(
          groupType: target.groupType,
          sourceLabel: target.sourceLabel,
          scheduleCode: match.matchedCode,
          scheduleId: match.link.scheduleId!,
          scheduleLabel: match.link.label,
        ));
      }
    }

    return UsosImportResult(
      imported: _uniqueResolvedGroups(resolved),
      unresolved: unresolved,
    );
  }

  Future<List<_PlanLink>> _collectPlanLinks({
    required List<UsosImportTarget> targets,
    required String username,
    required String password,
  }) async {
    final indexHtml = await remote.fetchPlanIndexHtml(
      username: username,
      password: password,
    );
    final indexLinks = _extractPlanLinks(indexHtml, _baseUri);
    final result = <_PlanLink>[
      ...indexLinks.where((link) => link.scheduleId != null),
    ];

    final queue = Queue<_QueuedPage>();
    final pagesToVisit = _selectInitialPages(indexLinks, targets);
    for (final link in pagesToVisit) {
      queue.add(_QueuedPage(link: link, depth: 0));
    }

    final visited = <String>{_normalizeUri(_baseUri).toString()};
    const maxPages = 80;

    while (queue.isNotEmpty && visited.length < maxPages) {
      final page = queue.removeFirst();
      final uri = _normalizeUri(page.link.uri);
      if (!_isPlanPage(uri) || !visited.add(uri.toString())) continue;

      final html = await remote.fetchAuthenticatedPlanHtml(
        uri: uri,
        username: username,
        password: password,
      );
      final links = _extractPlanLinks(html, uri);
      result.addAll(links.where((link) => link.scheduleId != null));

      if (page.depth >= 2) continue;
      for (final link in links.where((link) => link.isGroupPage)) {
        final childUri = _normalizeUri(link.uri);
        if (!_isPlanPage(childUri) || visited.contains(childUri.toString())) {
          continue;
        }
        if (_isUsefulPage(link, targets) || page.depth == 0) {
          queue.add(_QueuedPage(link: link, depth: page.depth + 1));
        }
      }
    }

    return _uniquePlanLinks(result);
  }

  List<_PlanLink> _selectInitialPages(
    List<_PlanLink> indexLinks,
    List<UsosImportTarget> targets,
  ) {
    final selected = <_PlanLink>[];
    final categoryLinks =
        indexLinks.where((link) => link.isGroupPage).toList(growable: false);

    for (final target in targets) {
      final matches = categoryLinks
          .where((link) => _isUsefulPage(link, [target]))
          .toList(growable: false);
      selected.addAll(matches.isEmpty ? categoryLinks : matches);
    }

    return _uniquePlanLinks(selected);
  }

  bool _isUsefulPage(_PlanLink link, List<UsosImportTarget> targets) {
    final foldedLabel = _fold('${link.label} ${link.uri}');

    for (final target in targets) {
      if (target.groupType == GroupType.language) {
        if (foldedLabel.contains('centrum jezykowe') ||
            foldedLabel.contains('cj')) {
          return true;
        }
        continue;
      }

      final majorCode = _majorCodeFromDeanCandidates(
        target.scheduleCodeCandidates,
      );
      if (majorCode == null) continue;
      if (foldedLabel.contains('($majorCode)') ||
          foldedLabel.contains('=$majorCode') ||
          foldedLabel.contains('%28$majorCode%29')) {
        return true;
      }
    }

    return false;
  }

  List<_PlanMatch> _findMatches(
    UsosImportTarget target,
    List<_PlanLink> links,
  ) {
    for (final candidate in target.scheduleCodeCandidates) {
      final normalizedCandidate = _normalizeCode(candidate);
      final matches = links.where((link) {
        final haystack = _normalizeCode('${link.label} ${link.uri}');
        return haystack.contains(normalizedCandidate);
      }).toList();

      if (matches.isEmpty) continue;
      matches.sort((a, b) => a.label.length.compareTo(b.label.length));
      if (!target.includeAllMatches) {
        return [_PlanMatch(link: matches.first, matchedCode: candidate)];
      }
      return matches
          .map(
            (link) => _PlanMatch(
              link: link,
              matchedCode: _codeFromLink(link) ?? candidate,
            ),
          )
          .toList(growable: false);
    }

    return const [];
  }

  String? _codeFromLink(_PlanLink link) {
    return RegExp(r'CJ-[A-Z0-9-]+-[0-9]+/[0-9]+-[A-Z]+\.[ABC][12]-[0-9]+')
        .firstMatch('${link.label} ${link.uri}')
        ?.group(0)
        ?.toUpperCase();
  }

  List<ResolvedUsosGroup> _uniqueResolvedGroups(
    Iterable<ResolvedUsosGroup> groups,
  ) {
    final seen = <String>{};
    return groups
        .where((group) => seen.add('${group.groupType}:${group.scheduleId}'))
        .toList(growable: false);
  }

  List<_PlanLink> _extractPlanLinks(String html, Uri pageUri) {
    final document = html_parser.parse(html);
    return document
        .querySelectorAll('a[href]')
        .map((anchor) => _linkFromAnchor(anchor, pageUri))
        .whereType<_PlanLink>()
        .toList();
  }

  _PlanLink? _linkFromAnchor(dom.Element anchor, Uri pageUri) {
    final href = anchor.attributes['href'];
    if (href == null || href.trim().isEmpty) return null;

    Uri uri;
    try {
      uri = _normalizeUri(pageUri.resolve(href));
    } on FormatException {
      return null;
    }
    if (!_isPlanPage(uri)) return null;

    final label = _cleanup(anchor.text);
    return _PlanLink(
      label: label.isEmpty ? _decodeUriSafely(uri.toString()) : label,
      uri: uri,
      scheduleId: uri.queryParameters['id'],
      isGroupPage: uri.queryParameters['typ'] == 'G',
    );
  }

  String? _majorCodeFromDeanCandidates(List<String> candidates) {
    for (final candidate in candidates) {
      final match = RegExp(r'^[A-Z0-9]*?([A-Z]{2})S[12]')
          .firstMatch(candidate.toUpperCase());
      if (match != null) return match.group(1)!.toLowerCase();
    }
    return null;
  }

  bool _isPlanPage(Uri uri) =>
      uri.host == _baseUri.host && uri.path.endsWith('/index.php');

  Uri _normalizeUri(Uri uri) {
    return uri.replace(fragment: '');
  }

  List<_PlanLink> _uniquePlanLinks(Iterable<_PlanLink> links) {
    final seen = <String>{};
    final result = <_PlanLink>[];
    for (final link in links) {
      final key = '${link.uri}|${link.label}';
      if (seen.add(key)) result.add(link);
    }
    return result;
  }

  String _normalizeCode(String value) {
    return _fold(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .replaceAll(' ', '');
  }

  String _cleanup(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _fold(String value) {
    return _decodeUriSafely(value)
        .toLowerCase()
        .replaceAll('ą', 'a')
        .replaceAll('ć', 'c')
        .replaceAll('ę', 'e')
        .replaceAll('ł', 'l')
        .replaceAll('ń', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ś', 's')
        .replaceAll('ź', 'z')
        .replaceAll('ż', 'z');
  }

  String _decodeUriSafely(String value) {
    try {
      return Uri.decodeFull(value);
    } on FormatException {
      return value;
    }
  }
}

class _PlanLink {
  final String label;
  final Uri uri;
  final String? scheduleId;
  final bool isGroupPage;

  const _PlanLink({
    required this.label,
    required this.uri,
    required this.scheduleId,
    required this.isGroupPage,
  });
}

class _PlanMatch {
  final _PlanLink link;
  final String matchedCode;

  const _PlanMatch({required this.link, required this.matchedCode});
}

class _QueuedPage {
  final _PlanLink link;
  final int depth;

  const _QueuedPage({required this.link, required this.depth});
}
