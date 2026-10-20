import '../models/expense.dart';
import 'paged_list_controller.dart';

/// Expense list with category and cash-box filters.
class ExpensesController extends PagedListController<Expense> {
  ExpensesController(super.api);

  String? _categoryId;
  String? _cashBoxId;

  String? get categoryId => _categoryId;
  String? get cashBoxId => _cashBoxId;

  @override
  String get path => '/expenses';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_categoryId != null && _categoryId!.isNotEmpty)
          'categoryId': _categoryId,
        if (_cashBoxId != null && _cashBoxId!.isNotEmpty) 'cashBoxId': _cashBoxId,
      };

  void filterByCategory(String? value) {
    if (value == _categoryId) return;
    _categoryId = value;
    markFilterChanged();
    refresh();
  }

  void filterByCashBox(String? value) {
    if (value == _cashBoxId) return;
    _cashBoxId = value;
    markFilterChanged();
    refresh();
  }

  @override
  Expense parseItem(Map<String, dynamic> json) => Expense.fromJson(json);
}
