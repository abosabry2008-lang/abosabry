/// A mandatory single-day filter for list screens. It always has a value and
/// defaults to today; the list is queried for that whole local day.
class DayFilter {
  DayFilter() : day = _startOfToday();

  DateTime day;

  /// True while the filter follows the calendar day. Picking a past day pins
  /// it; picking today switches auto-follow back on so the list rolls over at
  /// midnight instead of silently showing yesterday's documents.
  bool _followsToday = true;

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Moves the filter to today when it is still following the calendar.
  /// Returns true when the day actually changed.
  bool rollToToday() {
    if (!_followsToday) return false;
    final today = _startOfToday();
    if (today == day) return false;
    day = today;
    return true;
  }

  /// `from`/`to` query parameters covering [day] in UTC.
  Map<String, dynamic> query() {
    rollToToday();
    final start = day;
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return <String, dynamic>{
      'from': start.toUtc().toIso8601String(),
      'to': end.toUtc().toIso8601String(),
    };
  }

  /// Returns true when the day actually changed.
  bool select(DateTime value) {
    final next = DateTime(value.year, value.month, value.day);
    _followsToday = next == _startOfToday();
    if (next == day) return false;
    day = next;
    return true;
  }
}
