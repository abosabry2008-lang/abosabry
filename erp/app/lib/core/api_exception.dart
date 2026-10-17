/// Exception thrown by [ApiClient] for any non-successful request.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
    this.isNetworkError = false,
  });

  /// Human readable message, ready to be shown in the UI.
  final String message;

  /// HTTP status code, when the failure came from the server.
  final int? statusCode;

  /// Machine readable error code from the `error.code` envelope field.
  final String? code;

  /// Optional `error.details` payload.
  final Object? details;

  /// True when the request never reached the server.
  final bool isNetworkError;

  @override
  String toString() => message;
}
