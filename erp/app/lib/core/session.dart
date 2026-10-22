import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'config.dart';
import 'json_utils.dart';

/// Lifecycle of the authenticated session.
enum SessionStatus { unknown, unauthenticated, authenticated }

/// Role → permission keys. `ADMIN` is a wildcard.
const Map<String, Set<String>> rolePermissions = <String, Set<String>>{
  'ADMIN': <String>{'*'},
  'MANAGER': <String>{
    'dashboard',
    'pos',
    'products',
    'categories',
    'inventory',
    'warehouses',
    'suppliers',
    'purchases',
    'customers',
    'sales',
    'invoices',
    'payments',
    'treasury',
    'reports',
    'accounting',
    'openingBalances',
    'currencies',
    'settings',
    'roles.manage',
  },
  'SALES': <String>{
    'dashboard',
    'pos',
    'products',
    'categories',
    'inventory',
    'customers',
    'sales',
    'invoices',
    'payments',
    'treasury',
    'reports',
    'settings',
    'currencies',
  },
  'CASHIER': <String>{
    'dashboard',
    'pos',
    'products',
    'categories',
    'customers',
    'sales',
    'invoices',
    'payments',
    'treasury',
    'expenses',
    'reports',
    'settings',
    'currencies',
  },
  'WAREHOUSE': <String>{
    'dashboard',
    'products',
    'categories',
    'inventory',
    'warehouses',
    'suppliers',
    'purchases',
    'reports',
    'settings',
  },
  'ACCOUNTANT': <String>{
    'dashboard',
    'products',
    'suppliers',
    'purchases',
    'customers',
    'sales',
    'invoices',
    'payments',
    'treasury',
    'expenses',
    'reports',
    'accounting',
    'settings',
    'currencies',
  },
};

/// Holds tokens, the signed-in user and the permission helpers.
class Session extends ChangeNotifier {
  Session({ApiClient? client}) : api = client ?? ApiClient() {
    api.onRefresh = _refresh;
    api.onSessionExpired = _handleExpired;
  }

  final ApiClient api;

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _userKey = 'current_user';

  SessionStatus _status = SessionStatus.unknown;
  AppUser? _user;
  String? _accessToken;
  String? _refreshToken;
  bool _busy = false;
  String? _error;

  SessionStatus get status => _status;
  AppUser? get user => _user;
  String? get role => _user?.role;
  bool get isAdmin => (role ?? '').toUpperCase() == 'ADMIN';
  bool get busy => _busy;
  String? get error => _error;
  bool get isAuthenticated =>
      _status == SessionStatus.authenticated && _user != null;

  /// True when the current role has [permission].
  bool can(String permission) {
    final current = role;
    if (current == null) return false;
    if (current == 'ADMIN') return true;
    final userPerms = _user?.permissions;
    if (userPerms != null && userPerms.isNotEmpty) {
      return userPerms.contains('*') || userPerms.contains(permission);
    }
    final permissions = rolePermissions[current];
    if (permissions == null) return false;
    return permissions.contains('*') || permissions.contains(permission);
  }

  /// True when the current role has at least one of [permissions].
  bool canAny(Iterable<String> permissions) =>
      permissions.any((permission) => can(permission));

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Restores a persisted session (if any) and validates it via `/auth/me`.
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessKey);
    _refreshToken = prefs.getString(_refreshKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        _user = AppUser.fromJson(asMap(jsonDecode(userJson)));
      } catch (error) {
        debugPrint('Could not restore cached user: $error');
        _user = null;
      }
    }

    api.accessToken = _accessToken;
    api.refreshToken = _refreshToken;

    if (_accessToken == null || _accessToken!.isEmpty) {
      _status = SessionStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final data = await api.getObject('/auth/me');
      _user = AppUser.fromJson(data);
      await _persistUser(_user!);
      _status = SessionStatus.authenticated;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clear();
      } else if (_user != null) {
        // Offline / server unreachable but we have a cached user.
        _status = SessionStatus.authenticated;
      } else {
        _status = SessionStatus.unauthenticated;
      }
    }

    notifyListeners();
  }

  /// Signs in. Optionally overrides and persists the API base URL.
  Future<bool> login({
    required String email,
    required String password,
    String? baseUrl,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        await AppConfig.setBaseUrl(baseUrl);
      }
      final data = await api.postObject(
        '/auth/login',
        body: <String, dynamic>{
          'email': email.trim(),
          'password': password,
        },
      );
      _accessToken = asStringOrNull(data['accessToken']);
      _refreshToken = asStringOrNull(data['refreshToken']);
      _user = AppUser.fromJson(asMap(data['user']));
      api.accessToken = _accessToken;
      api.refreshToken = _refreshToken;
      await _persistSession();
      _status = SessionStatus.authenticated;
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      _status = SessionStatus.unauthenticated;
      return false;
    } catch (error) {
      debugPrint('Login failed: $error');
      _error = 'Unable to sign in. Please try again.';
      _status = SessionStatus.unauthenticated;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Revokes the refresh token server side and clears local state.
  Future<void> logout() async {
    final token = _refreshToken;
    if (token != null && token.isNotEmpty) {
      try {
        await api.post(
          '/auth/logout',
          body: <String, dynamic>{'refreshToken': token},
          retry: false,
        );
      } catch (error) {
        debugPrint('Logout request failed: $error');
      }
    }
    await _clear();
    notifyListeners();
  }

  /// Reloads the current user from `/auth/me`.
  Future<void> refreshUser() async {
    if (_accessToken == null) return;
    try {
      final data = await api.getObject('/auth/me');
      _user = AppUser.fromJson(data);
      await _persistUser(_user!);
      notifyListeners();
    } catch (error) {
      debugPrint('Could not refresh user: $error');
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) await prefs.setString(_accessKey, _accessToken!);
    if (_refreshToken != null) {
      await prefs.setString(_refreshKey, _refreshToken!);
    }
    if (_user != null) await _persistUser(_user!);
  }

  Future<void> _persistUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> _clear() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _error = null;
    api.accessToken = null;
    api.refreshToken = null;
    _status = SessionStatus.unauthenticated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }

  Future<bool> _refresh() async {
    final token = _refreshToken;
    if (token == null || token.isEmpty) return false;
    try {
      final data = await api.postObject(
        '/auth/refresh',
        body: <String, dynamic>{'refreshToken': token},
        retry: false,
      );
      final newAccess = asStringOrNull(data['accessToken']);
      if (newAccess == null) return false;
      final newRefresh = asStringOrNull(data['refreshToken']) ?? token;
      _accessToken = newAccess;
      _refreshToken = newRefresh;
      api.accessToken = newAccess;
      api.refreshToken = newRefresh;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessKey, newAccess);
      await prefs.setString(_refreshKey, newRefresh);
      return true;
    } catch (error) {
      debugPrint('Token refresh failed: $error');
      return false;
    }
  }

  void _handleExpired() {
    if (_status == SessionStatus.unauthenticated) return;
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    api.accessToken = null;
    api.refreshToken = null;
    _status = SessionStatus.unauthenticated;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_accessKey);
      prefs.remove(_refreshKey);
      prefs.remove(_userKey);
    });
  }
}
