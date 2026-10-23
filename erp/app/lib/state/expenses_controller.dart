import '../models/expense.dart';
import 'paged_list_controller.dart';

/// Expense list filtered by a mandatory day (defaults to today), category and
/// cash box. "All categories" / "All boxes" simply leave that filter unset.
class ExpensesController extends PagedListController<Expense> {
  ExpensesController(super.api);

  String? _categoryId;
  String? _cashBoxId;
  DateTime _date = _today();

  String? get categoryId => _categoryId;
  String? get cashBoxId => _cashBoxId;
  DateTime get date => _date;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  String get path => '/expenses';

  @override
  Map<String, dynamic> queryParameters() {
    final start = _date;
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return <String, dynamic>{
      'from': start.toUtc().toIso8601String(),
      'to': end.toUtc().toIso8601String(),
      if (_categoryId != null && _categoryId!.isNotEmpty)
        'categoryId': _categoryId,
      if (_cashBoxId != null && _cashBoxId!.isNotEmpty) 'cashBoxId': _cashBoxId,
    };
  }

  void filterByDate(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    if (day == _date) return;
    _date = day;
    refresh();
  }

  void filterByCategory(String? value) {
    if (value == _categoryId) return;
    _categoryId = value;
    refresh();
  }

  void filterByCashBox(String? value) {
    if (value == _cashBoxId) return;
    _cashBoxId = value;
    refresh();
  }

  @override
  Expense parseItem(Map<String, dynamic> json) => Expense.fromJson(json);
}
