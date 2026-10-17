import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/paginated.dart';
import 'api_exception.dart';
import 'config.dart';
import 'json_utils.dart';

/// Thin wrapper around `package:http` that understands the ERP API envelope.
///
/// * Attaches `Authorization: Bearer <token>` to every request.
/// * On HTTP 401 it attempts a single token refresh (deduplicated) and retries
///   the original request once.
/// * Decodes `{ "data": ... }` / `{ "data": [...], "meta": {...} }` envelopes and
///   turns `{ "error": { "message": ... } }` responses into [ApiException]s.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 30);

  /// Access token attached to outgoing requests.
  String? accessToken;

  /// Refresh token, kept in sync by [Session].
  String? refreshToken;

  /// Invoked when a 401 is received; must return `true` when new tokens were
  /// obtained successfully.
  Future<bool> Function()? onRefresh;

  /// Invoked when the session cannot be recovered and the user must sign in.
  void Function()? onSessionExpired;

  Future<bool>? _pendingRefresh;

  /// Base URL currently in use.
  String get baseUrl => AppConfig.baseUrl;

  // ---------------------------------------------------------------------------
  // Verbs
  // ---------------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      send('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) =>
      send('POST', path, body: body, query: query, retry: retry);

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) =>
      send('PATCH', path, body: body, query: query, retry: retry);

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) =>
      send('PUT', path, body: body, query: query, retry: retry);

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) =>
      send('DELETE', path, body: body, query: query, retry: retry);

  // ---------------------------------------------------------------------------
  // Typed helpers
  // ---------------------------------------------------------------------------

  /// Performs a request and returns the `data` object.
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, dynamic>? query,
  }) async =>
      _extractData(await get(path, query: query));

  Future<Map<String, dynamic>> postObject(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) async =>
      _extractData(await post(path, body: body, query: query, retry: retry));

  Future<Map<String, dynamic>> patchObject(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retry = true,
  }) async =>
      _extractData(await patch(path, body: body, query: query, retry: retry));

  /// Performs a request whose `data` is a plain list (no pagination meta).
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async =>
      _extractList(await get(path, query: query));

  /// Performs a request whose `data` is a paginated list.
  Future<Paginated<T>> getPage<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic> json) parse,
  }) async =>
      Paginated.fromJson(await get(path, query: query), parse);

  /// Convenience for endpoints that return a single object wrapped in `data`.
  Future<Map<String, dynamic>> getObjectById(String path, String id) =>
      getObject('$path/$id');

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Sends a request and returns the decoded JSON body (or `null`).
  Future<dynamic> send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool retry = true,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null && accessToken!.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(
        'The request timed out. Check your connection and try again.',
        isNetworkError: true,
      );
    } catch (error) {
      throw ApiException(
        'Cannot reach the server at ${AppConfig.baseUrl}.',
        isNetworkError: true,
        details: error,
      );
    }

    if (response.statusCode == 401 && retry) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return send(method, path, query: query, body: body, retry: false);
      }
      onSessionExpired?.call();
      throw ApiException(
        'Your session has expired. Please sign in again.',
        statusCode: 401,
        code: 'UNAUTHORIZED',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response.body);
    }

    throw _buildError(response);
  }

  Future<bool> _refreshOnce() {
    final pending = _pendingRefresh;
    if (pending != null) return pending;
    final callback = onRefresh;
    if (callback == null) return Future<bool>.value(false);
    final future = callback();
    _pendingRefresh = future;
    return future.whenComplete(() {
      _pendingRefresh = null;
    });
  }

  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${AppConfig.baseUrl}$normalized');
    final params = <String, String>{};
    uri.queryParameters.forEach((key, value) => params[key] = value);
    query?.forEach((key, value) {
      if (value == null) return;
      final text = value.toString();
      if (text.isEmpty) return;
      params[key] = text;
    });
    if (params.isEmpty) return uri;
    return uri.replace(queryParameters: params);
  }

  dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> _extractData(dynamic json) {
    final root = asMap(json);
    if (root.containsKey('data')) return asMap(root['data']);
    return root;
  }

  List<Map<String, dynamic>> _extractList(dynamic json) {
    final data = asMap(json)['data'];
    if (data is List) return asMapList(data);
    if (json is List) return asMapList(json);
    return <Map<String, dynamic>>[];
  }

  ApiException _buildError(http.Response response) {
    final decoded = _decode(response.body);
    final error = asMap(asMap(decoded)['error']);
    var message = asStringOrNull(error['message']);
    if (message == null || message.trim().isEmpty) {
      message = _fallbackMessage(response.statusCode);
    }
    return ApiException(
      message,
      statusCode: response.statusCode,
      code: asStringOrNull(error['code']),
      details: error['details'],
    );
  }

  String _fallbackMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'The request was invalid.';
      case 401:
        return 'You are not authorised. Please sign in again.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'The requested record was not found.';
      case 409:
        return 'This action conflicts with the current state.';
      case 422:
        return 'The submitted data could not be processed.';
      case 500:
        return 'The server encountered an error.';
      default:
        return 'Request failed (HTTP $statusCode).';
    }
  }
}
