Uri? parseAttendanceLink(String input) {
  final trimmed = input.trim();
  final value = RegExp(r'^[\d\s]+$').hasMatch(trimmed)
      ? trimmed.replaceAll(RegExp(r'\s+'), '')
      : trimmed;
  final uri = RegExp(r'^\d{6,20}$').hasMatch(value)
      ? Uri.https('portal.uek.krakow.pl', '/obecnosc/$value')
      : Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.host != 'portal.uek.krakow.pl' ||
      !RegExp(r'^/obecnosc/\d{6,20}/?$').hasMatch(uri.path) ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

bool isAttendanceNavigation(Uri uri) {
  if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.host == 'portal.uek.krakow.pl') return true;
  if (uri.host != 'logowanie.uek.krakow.pl' || uri.path != '/cas/login') {
    return false;
  }
  String? service;
  try {
    service = uri.queryParameters['service'];
  } on FormatException {
    return false;
  } on ArgumentError {
    return false;
  }
  if (service == null) return true;
  final target = Uri.tryParse(service);
  return target != null &&
      target.scheme == 'https' &&
      target.port == 443 &&
      target.userInfo.isEmpty &&
      target.host == 'portal.uek.krakow.pl';
}
