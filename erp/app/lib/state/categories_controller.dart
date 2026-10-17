import '../models/category.dart';
import 'paged_list_controller.dart';

/// Category list.
class CategoriesController extends PagedListController<Category> {
  CategoriesController(super.api);

  @override
  String get path => '/categories';

  @override
  Category parseItem(Map<String, dynamic> json) => Category.fromJson(json);
}
