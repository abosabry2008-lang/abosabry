import '../models/return_order.dart';
import 'paged_list_controller.dart';

/// Return orders list with type / status filters.
class ReturnsController extends PagedListController<ReturnOrder> {
  ReturnsController(super.api);

  String? _type;
  String? _status;

  String? get type => _type;
  String? get status => _status;

  @override
  String get path => '/returns';

  @override
  bool get requiresSearch => true;

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_type != null && _type!.isNotEmpty) 'type': _type,
        if (_status != null && _status!.isNotEmpty) 'status': _status,
      };

  void filterByType(String? value) {
    if (value == _type) return;
    _type = value;
    markFilterChanged();
    refresh();
  }

  void filterByStatus(String? value) {
    if (value == _status) return;
    _status = value;
    markFilterChanged();
    refresh();
  }

  @override
  ReturnOrder parseItem(Map<String, dynamic> json) =>
      ReturnOrder.fromJson(json);
}
