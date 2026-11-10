import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'plan_directory.dart';

class LecturerCard {
  const LecturerCard(this.name, this.uri);
  final String name;
  final Uri uri;
}

class LecturerContact {
  const LecturerContact({required this.emails});
  final List<String> emails;
}

String lecturerSearchName(String name) => name
    .replaceAll(RegExp(r'[.,]'), ' ')
    .split(RegExp(r'\s+'))
    .where((word) => !const {
          'prof',
          'dr',
          'hab',
          'mgr',
          'inż',
          'inz',
          'uek',
          'lic',
          ''
        }.contains(word.toLowerCase()))
    .join(' ');

class LecturerDirectory {
  LecturerDirectory({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const host = 'e-uczelnia.uek.krakow.pl';
  void close() => _client.close();

  static Uri searchUri(String name) => Uri.https(host, '/course/search.php', {
        'search': lecturerSearchName(name),
        'perpage': 'all',
        'lang': 'pl',
      });

  Future<String> _get(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.host != host ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw ArgumentError('Niedozwolony adres e-wizytówki.');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(
          'Nie udało się pobrać e-wizytówki (${response.statusCode}).');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<LecturerCard>> search(String name) async =>
      parseSearch(await _get(searchUri(name)), name);

  static List<LecturerCard> parseSearch(String source, String name) {
    final document = html.parse(source);
    final found = <String, LecturerCard>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final requested = foldSearch(lecturerSearchName(name)).split(' ');
      final words = foldSearch(lecturerSearchName(label)).split(' ');
      if (!foldSearch(label).contains('wizytowka') ||
          requested.any((word) => word.isEmpty || !words.contains(word))) {
        continue;
      }
      final canonical = _cardUri(anchor.attributes['href']!);
      if (canonical == null) continue;
      found[canonical.toString()] = LecturerCard(label, canonical);
    }
    return found.values.toList();
  }

  static Uri? _cardUri(String href) {
    try {
      final uri = Uri.https(host, '/').resolve(href);
      if (uri.scheme != 'https' ||
          uri.host != host ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          uri.path != '/course/view.php' ||
          !RegExp(r'^\d+$').hasMatch(uri.queryParameters['id'] ?? '')) {
        return null;
      }
      return Uri.https(host, '/course/view.php',
          {'id': uri.queryParameters['id']!, 'lang': 'pl'});
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<LecturerContact> contact(LecturerCard card) async =>
      parseContact(await _get(card.uri));

  static LecturerContact parseContact(String source) {
    final document = html.parse(source);
    final content = document.querySelector('.course-content') ??
        document.querySelector('#region-main');
    if (content == null) return const LecturerContact(emails: []);
    final emails = <String>{};
    final pattern = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}');
    for (final match in pattern.allMatches(content.text)) {
      emails.add(match.group(0)!);
    }
    for (final anchor in content.querySelectorAll('a[href]')) {
      final uri = Uri.tryParse(anchor.attributes['href']!);
      if (uri == null) continue;
      if (uri.scheme == 'mailto') {
        final email = uri.path;
        if (pattern.stringMatch(email) == email) emails.add(email);
      }
    }
    return LecturerContact(emails: emails.toList());
  }
}
