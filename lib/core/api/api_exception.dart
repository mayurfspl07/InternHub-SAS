class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;
  final int? retryAfterSeconds;

  ApiException({
    required this.statusCode,
    required this.message,
    this.details,
    this.retryAfterSeconds,
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isValidationError => statusCode == 400 || statusCode == 422;
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => message;

  static ApiException fromResponse(int statusCode, dynamic body, {Map<String, String>? headers}) {
    String message = 'An error occurred. Please try again.';
    int? retryAfter;

    if (statusCode == 429) {
      final headerRetry = headers?['retry-after'];
      if (headerRetry != null) {
        retryAfter = int.tryParse(headerRetry);
      }
    }

    if (body is Map) {
      if (body['detail'] != null) {
        if (body['detail'] is String) {
          message = body['detail'] as String;
        } else if (body['detail'] is List) {
          final list = body['detail'] as List;
          final errors = list.map((e) {
            if (e is Map && e['msg'] != null) {
              return e['msg'].toString();
            }
            return e.toString();
          }).join(', ');
          if (errors.isNotEmpty) message = errors;
        }
      } else if (body['message'] != null) {
        message = body['message'].toString();
      } else if (body['error'] != null) {
        message = body['error'].toString();
      }

      if (retryAfter == null && body['retry_after'] != null) {
        retryAfter = int.tryParse(body['retry_after'].toString());
      }
    } else if (body is String && body.isNotEmpty) {
      message = body;
    }

    if (statusCode == 401 && message == 'An error occurred. Please try again.') {
      message = 'Session expired. Please sign in again.';
    } else if (statusCode == 403 && message == 'An error occurred. Please try again.') {
      message = 'You do not have permission to perform this action.';
    } else if (statusCode == 404 && message == 'An error occurred. Please try again.') {
      message = 'Resource not found.';
    } else if (statusCode == 429 && message == 'An error occurred. Please try again.') {
      message = 'Too many requests. Please wait a moment and try again.';
    }

    return ApiException(
      statusCode: statusCode,
      message: message,
      details: body,
      retryAfterSeconds: retryAfter,
    );
  }

  static ApiException networkError([String? customMessage]) {
    return ApiException(
      statusCode: 0,
      message: customMessage ?? 'Unable to connect. Please check your internet connection.',
    );
  }
}
