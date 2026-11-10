class RefreshSettings {
  static const key = 'automatic_refresh_minutes';
  static const options = [0, 15, 30, 60, 120, 360, 720, 1440];

  static int parse(String? value) {
    final minutes = int.tryParse(value ?? '');
    return options.contains(minutes) ? minutes! : 60;
  }

  static String label(int minutes) => switch (minutes) {
        0 => 'Tylko ręcznie',
        1440 => 'Co 24 godziny',
        _ when minutes >= 60 => 'Co ${minutes ~/ 60} godz.',
        _ => 'Co $minutes min',
      };

  static DateTime? dueAt(int minutes, DateTime? last, DateTime? retry) {
    if (minutes == 0) return null;
    final regular = last?.add(Duration(minutes: minutes));
    if (retry == null) return regular;
    return regular != null && regular.isAfter(retry) ? regular : retry;
  }
}
