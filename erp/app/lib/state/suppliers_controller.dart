import '../models/supplier.dart';
import 'paged_list_controller.dart';

/// Supplier list.
class SuppliersController extends PagedListController<Supplier> {
  SuppliersController(super.api);

  @override
  String get path => '/suppliers';

  @override
  Supplier parseItem(Map<String, dynamic> json) => Supplier.fromJson(json);
}
