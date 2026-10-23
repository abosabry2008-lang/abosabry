/// A mandatory single-day filter for list screens. It always has a value and
/// defaults to today; the list is queried for that whole local day.
class DayFilter {
  DayFilter() : day = _startOfToday();

  DateTime day;

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// `from`/`to` query parameters covering [day] in UTC.
  Map<String, dynamic> query() {
    final start = day;
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return <String, dynamic>{
      'from': start.toUtc().toIso8601String(),
      'to': end.toUtc().toIso8601String(),
    };
  }

  /// Returns true when the day actually changed.
  bool select(DateTime value) {
    final next = DateTime(value.year, value.month, value.day);
    if (next == day) return false;
    day = next;
    return true;
  }
}
