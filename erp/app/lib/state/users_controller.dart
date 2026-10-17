import '../models/user.dart';
import 'paged_list_controller.dart';

/// User list with an optional role filter.
class UsersController extends PagedListController<AppUser> {
  UsersController(super.api);

  String? _role;

  String? get role => _role;

  @override
  String get path => '/users';

  @override
  Map<String, dynamic> queryParameters() => <String, dynamic>{
        if (_role != null && _role!.isNotEmpty) 'role': _role,
      };

  void filterByRole(String? value) {
    if (value == _role) return;
    _role = value;
    refresh();
  }

  @override
  AppUser parseItem(Map<String, dynamic> json) => AppUser.fromJson(json);
}
