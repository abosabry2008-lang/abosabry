import '../models/account.dart';
import '../models/journal_entry.dart';
import 'paged_list_controller.dart';

/// Chart of accounts (`GET /accounting/accounts`).
class AccountsController extends PagedListController<Account> {
  AccountsController(super.api);

  String? _type;

  String? get type => _type;

  @override
  String get path => '/accounting/accounts';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_type != null && _type!.isNotEmpty) 'type': _type,
      };

  void filterByType(String? value) {
    if (value == _type) return;
    _type = value;
    refresh();
  }

  @override
  Account parseItem(Map<String, dynamic> json) => Account.fromJson(json);
}

/// Journal entries (`GET /accounting/journal`).
class JournalController extends PagedListController<JournalEntry> {
  JournalController(super.api);

  String? _reference;

  @override
  String get path => '/accounting/journal';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_reference != null && _reference!.isNotEmpty)
          'reference': _reference,
      };

  void filterByReference(String? value) {
    if (value == _reference) return;
    _reference = value;
    refresh();
  }

  @override
  JournalEntry parseItem(Map<String, dynamic> json) =>
      JournalEntry.fromJson(json);
}
