import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/paginated.dart';

/// Shared paging logic for every list-oriented feature controller.
///
/// Subclasses only declare the endpoint [path], any extra [queryParameters]
/// and how to [parseItem] a single record.
abstract class PagedListController<T> extends ChangeNotifier {
  PagedListController(this.api);

  final ApiClient api;

  final List<T> items = <T>[];

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _totalPages = 0;
  int _pageSize = 20;
  String _search = '';
  bool _initialised = false;
  bool _hasLoadedOnce = false;
  bool _activated = false;

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  int get page => _page;
  int get total => _total;
  int get totalPages => _totalPages;
  int get pageSize => _pageSize;
  String get search => _search;
  bool get hasMore => _totalPages > 0 && _page < _totalPages;
  bool get isEmpty => !_loading && items.isEmpty;
  bool get isInitialised => _initialised;
  /// True once a fetch has completed at least once (so empty means "no matches",
  /// not "not loaded yet").
  bool get hasLoadedOnce => _hasLoadedOnce;

  /// Endpoint path, e.g. `/products`.
  String get path;

  /// Extra filters appended to every request.
  Map<String, dynamic> queryParameters() => const <String, dynamic>{};

  /// When true the list stays empty until the user searches or applies a filter.
  /// This keeps big lists (invoices, orders, movements…) from loading everything
  /// at once and keeps the app snappy.
  bool get requiresSearch => false;

  /// Whether the controller is allowed to fetch right now. Once a search term or
  /// a filter is set the list becomes active; lists that don't [requiresSearch]
  /// are always active.
  bool get isActivated => _activated || !requiresSearch;

  /// Call from a subclass whenever a filter changes so a filtered list loads.
  @protected
  void markFilterChanged() {
    if (requiresSearch) _activated = true;
  }

  /// Parses a single record.
  T parseItem(Map<String, dynamic> json);

  /// Loads the first page the first time the controller is used.
  Future<void> ensureLoaded() async {
    if (_initialised) return;
    _initialised = true;
    if (!isActivated) {
      notifyListeners();
      return;
    }
    await refresh();
  }

  /// Reloads from page 1.
  Future<void> refresh() async {
    if (_loading) return;
    if (!isActivated) {
      _hasLoadedOnce = true;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _fetch(1);
      items
        ..clear()
        ..addAll(result.items);
      _page = result.page < 1 ? 1 : result.page;
      _total = result.total;
      _totalPages = result.totalPages;
      _initialised = true;
      _hasLoadedOnce = true;
    } on ApiException catch (error) {
      _error = error.message;
      _hasLoadedOnce = true;
    } catch (error) {
      debugPrint('$runtimeType.refresh failed: $error');
      _error = 'Something went wrong while loading data.';
      _hasLoadedOnce = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Appends the next page.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final result = await _fetch(_page + 1);
      items.addAll(result.items);
      _page = result.page < 1 ? _page + 1 : result.page;
      _total = result.total;
      _totalPages = result.totalPages;
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      debugPrint('$runtimeType.loadMore failed: $error');
      _error = 'Something went wrong while loading more data.';
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Sets the free-text search term and reloads.
  void searchWith(String value) {
    final term = value.trim();
    if (term == _search) return;
    _search = term;
    if (term.isNotEmpty) _activated = true;
    refresh();
  }

  /// Changes the page size and reloads.
  void setPageSize(int value) {
    if (value == _pageSize) return;
    _pageSize = value;
    refresh();
  }

  /// Applies a new set of filters and reloads from page 1.
  ///
  /// Subclasses call this from their filter setters so a filtered list
  /// activates (even when it [requiresSearch]).
  @protected
  void applyFilters(VoidCallback mutate) {
    mutate();
    markFilterChanged();
    refresh();
  }

  /// Clears the current error (used after the user dismisses it).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Replaces a single item in the loaded list after a local mutation.
  void replaceWhere(bool Function(T item) test, T Function(T item) update) {
    for (var index = 0; index < items.length; index++) {
      if (test(items[index])) {
        items[index] = update(items[index]);
        notifyListeners();
        return;
      }
    }
  }

  /// Removes an item from the loaded list after a local mutation.
  void removeWhere(bool Function(T item) test) {
    final removed = items.length;
    items.removeWhere(test);
    if (items.length != removed) notifyListeners();
  }

  Future<Paginated<T>> _fetch(int pageNumber) {
    final query = <String, dynamic>{
      ...queryParameters(),
      'page': pageNumber,
      'pageSize': _pageSize,
    };
    if (_search.isNotEmpty) query['search'] = _search;
    return api.getPage<T>(path, query: query, parse: parseItem);
  }
}
