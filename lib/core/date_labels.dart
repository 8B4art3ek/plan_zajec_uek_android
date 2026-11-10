String polishWeekday(DateTime date) => const [
      'poniedziałek',
      'wtorek',
      'środa',
      'czwartek',
      'piątek',
      'sobota',
      'niedziela',
    ][date.weekday - 1];
