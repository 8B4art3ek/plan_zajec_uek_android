enum University {
  uek('uek', 'UEK', 'Uniwersytet Ekonomiczny w Krakowie');

  const University(this.id, this.shortName, this.name);
  final String id;
  final String shortName;
  final String name;

  static University? fromStorage(String? value) {
    for (final university in values) {
      if (university.id == value) return university;
    }
    return null;
  }
}
