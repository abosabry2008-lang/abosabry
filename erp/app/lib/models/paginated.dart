import '../core/json_utils.dart';

/// A page of results from a `{ "data": [...], "meta": {...} }` envelope.
class Paginated<T> {
  const Paginated({
    required this.items,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.totalPages = 0,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  /// True when another page can be fetched.
  bool get hasMore => totalPages > 0 && page < totalPages;

  bool get isEmpty => items.isEmpty;

  factory Paginated.fromJson(
    dynamic json,
    T Function(Map<String, dynamic> json) parse,
  ) {
    final root = asMap(json);
    final data = root['data'];
    final items = <T>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) items.add(parse(asMap(item)));
      }
    } else if (data is Map) {
      items.add(parse(asMap(data)));
    }
    final meta = asMap(root['meta']);
    return Paginated<T>(
      items: items,
      page: asInt(meta['page'], fallback: 1),
      pageSize: asInt(meta['pageSize'], fallback: items.length),
      total: asInt(meta['total'], fallback: items.length),
      totalPages: asInt(meta['totalPages']),
    );
  }

  static Paginated<T> empty<T>() => Paginated<T>(items: const <Never>[]);
}
