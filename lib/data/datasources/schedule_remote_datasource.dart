// lib/data/datasources/schedule_remote_datasource.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ScheduleRemoteDatasource {
  Future<void> verifyCredentials({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('https://planzajec.uek.krakow.pl/index.php');
    await _getAuthenticatedHtml(uri, username, password);
  }

  /// Fetches raw HTML for the given group.
  /// Value used by the UEK plan website to select the currently valid period.
  Future<String> fetchScheduleHtml({
    required String groupId,
    required String username,
    required String password,
    int okres = 3,
  }) async {
    final uri = Uri.parse(
      'https://planzajec.uek.krakow.pl/index.php?typ=G&id=$groupId&okres=$okres',
    );

    return _getAuthenticatedHtml(uri, username, password);
  }

  Future<String> fetchPlanIndexHtml({
    required String username,
    required String password,
  }) {
    return fetchAuthenticatedPlanHtml(
      uri: Uri.parse('https://planzajec.uek.krakow.pl/index.php'),
      username: username,
      password: password,
    );
  }

  Future<String> fetchAuthenticatedPlanHtml({
    required Uri uri,
    required String username,
    required String password,
  }) {
    return _getAuthenticatedHtml(uri, username, password);
  }

  Future<String> _getAuthenticatedHtml(
    Uri uri,
    String username,
    String password,
  ) async {
    final basicAuth = base64Encode(utf8.encode('$username:$password'));

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'pl,en;q=0.9',
      },
    );

    if (response.statusCode == 401) {
      throw Exception('Nieprawidłowe dane logowania (401).');
    }
    if (response.statusCode != 200) {
      throw Exception('Błąd HTTP ${response.statusCode}.');
    }

    return _decodeResponseBody(response);
  }

  /// Decodes response bytes with proper ISO-8859-2 / UTF-8 detection.
  String _decodeResponseBody(http.Response response) {
    final bytes = response.bodyBytes;

    final contentType = response.headers['content-type'] ?? '';
    final charsetMatch = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
        .firstMatch(contentType);
    final charset = charsetMatch?.group(1)?.toLowerCase().trim();

    if (charset == 'utf-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }

    // UEK uses ISO-8859-2 by default — decode and check meta charset
    final decoded = _decodeLatin2(bytes);

    final metaCharset = RegExp(
      r'''charset\s*=\s*["']?(utf-8|iso-8859-2)''',
      caseSensitive: false,
    ).firstMatch(decoded)?.group(1)?.toLowerCase();

    if (metaCharset == 'utf-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }

    return decoded;
  }

  /// Decodes bytes using ISO-8859-2 (Latin-2) encoding.
  String _decodeLatin2(Uint8List bytes) {
    const latin2Map = <int, int>{
      0xA0: 0x00A0,
      0xA1: 0x0104,
      0xA2: 0x02D8,
      0xA3: 0x0141,
      0xA4: 0x00A4,
      0xA5: 0x013D,
      0xA6: 0x015A,
      0xA7: 0x00A7,
      0xA8: 0x00A8,
      0xA9: 0x0160,
      0xAA: 0x015E,
      0xAB: 0x0164,
      0xAC: 0x0179,
      0xAD: 0x00AD,
      0xAE: 0x017D,
      0xAF: 0x017B,
      0xB0: 0x00B0,
      0xB1: 0x0105,
      0xB2: 0x02DB,
      0xB3: 0x0142,
      0xB4: 0x00B4,
      0xB5: 0x013E,
      0xB6: 0x015B,
      0xB7: 0x02C7,
      0xB8: 0x00B8,
      0xB9: 0x0161,
      0xBA: 0x015F,
      0xBB: 0x0165,
      0xBC: 0x017A,
      0xBD: 0x02DD,
      0xBE: 0x017E,
      0xBF: 0x017C,
      0xC0: 0x0154,
      0xC1: 0x00C1,
      0xC2: 0x00C2,
      0xC3: 0x0102,
      0xC4: 0x00C4,
      0xC5: 0x0139,
      0xC6: 0x0106,
      0xC7: 0x00C7,
      0xC8: 0x010C,
      0xC9: 0x00C9,
      0xCA: 0x0118,
      0xCB: 0x00CB,
      0xCC: 0x011A,
      0xCD: 0x00CD,
      0xCE: 0x00CE,
      0xCF: 0x010E,
      0xD0: 0x0110,
      0xD1: 0x0143,
      0xD2: 0x0147,
      0xD3: 0x00D3,
      0xD4: 0x00D4,
      0xD5: 0x0150,
      0xD6: 0x00D6,
      0xD7: 0x00D7,
      0xD8: 0x0158,
      0xD9: 0x016E,
      0xDA: 0x00DA,
      0xDB: 0x0170,
      0xDC: 0x00DC,
      0xDD: 0x00DD,
      0xDE: 0x0162,
      0xDF: 0x00DF,
      0xE0: 0x0155,
      0xE1: 0x00E1,
      0xE2: 0x00E2,
      0xE3: 0x0103,
      0xE4: 0x00E4,
      0xE5: 0x013A,
      0xE6: 0x0107,
      0xE7: 0x00E7,
      0xE8: 0x010D,
      0xE9: 0x00E9,
      0xEA: 0x0119,
      0xEB: 0x00EB,
      0xEC: 0x011B,
      0xED: 0x00ED,
      0xEE: 0x00EE,
      0xEF: 0x010F,
      0xF0: 0x0111,
      0xF1: 0x0144,
      0xF2: 0x0148,
      0xF3: 0x00F3,
      0xF4: 0x00F4,
      0xF5: 0x0151,
      0xF6: 0x00F6,
      0xF7: 0x00F7,
      0xF8: 0x0159,
      0xF9: 0x016F,
      0xFA: 0x00FA,
      0xFB: 0x0171,
      0xFC: 0x00FC,
      0xFD: 0x00FD,
      0xFE: 0x0163,
      0xFF: 0x02D9,
    };

    final codeUnits = <int>[];
    for (final byte in bytes) {
      if (byte < 0xA0) {
        codeUnits.add(byte);
      } else {
        codeUnits.add(latin2Map[byte] ?? 0xFFFD);
      }
    }
    return String.fromCharCodes(codeUnits);
  }
}
