import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_exception.dart';
import 'auth_storage.dart';

typedef OnUnauthorizedCallback = void Function();

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final http.Client _client = http.Client();
  OnUnauthorizedCallback? onUnauthorized;

  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final parsed = Uri.parse(path);
    final rawPath = parsed.path.startsWith('/') ? parsed.path : '/${parsed.path}';
    final baseUri = Uri.parse(ApiConfig.baseUrl);

    final mergedQuery = <String, String>{};
    // Extract any query params embedded in path string (e.g. /api/users/dropdown?role=mentor)
    parsed.queryParameters.forEach((key, value) {
      mergedQuery[key] = value;
    });

    if (queryParameters != null) {
      queryParameters.forEach((key, value) {
        if (value != null) {
          mergedQuery[key] = value.toString();
        }
      });
    }

    return baseUri.replace(
      path: '${baseUri.path}$rawPath',
      queryParameters: mergedQuery.isEmpty ? null : mergedQuery,
    );
  }

  Future<Map<String, String>> _buildHeaders({bool isJson = true}) async {
    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';
    }

    final token = await AuthStorage.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final orgId = await AuthStorage.getOrgId();
    if (orgId != null && orgId.isNotEmpty) {
      headers['X-Organization-Id'] = orgId;
    }

    return headers;
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode == 204) {
      return null;
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }

    throw ApiException.fromResponse(
      response.statusCode,
      decoded,
      headers: response.headers,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders();
      final response = await _client.get(uri, headers: headers);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<dynamic> post(String path, {dynamic body, Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders();
      final payload = body != null ? (body is String ? body : jsonEncode(body)) : null;
      final response = await _client.post(uri, headers: headers, body: payload);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<dynamic> put(String path, {dynamic body, Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders();
      final payload = body != null ? (body is String ? body : jsonEncode(body)) : null;
      final response = await _client.put(uri, headers: headers, body: payload);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<dynamic> patch(String path, {dynamic body, Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders();
      final payload = body != null ? (body is String ? body : jsonEncode(body)) : null;
      final response = await _client.patch(uri, headers: headers, body: payload);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<dynamic> delete(String path, {dynamic body, Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders();
      final payload = body != null ? (body is String ? body : jsonEncode(body)) : null;
      final response = await _client.delete(uri, headers: headers, body: payload);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final headers = await _buildHeaders(isJson: false);
      final response = await _client.get(uri, headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      if (response.statusCode == 401) {
        onUnauthorized?.call();
      }
      throw ApiException.fromResponse(response.statusCode, response.body, headers: response.headers);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }

  Future<dynamic> postMultipart(
    String path, {
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final request = http.MultipartRequest('POST', uri);

      final headers = await _buildHeaders(isJson: false);
      request.headers.addAll(headers);

      if (fields != null) {
        request.fields.addAll(fields);
      }

      if (files != null) {
        request.files.addAll(files);
      }

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException.networkError();
    } on http.ClientException {
      throw ApiException.networkError();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: 500, message: e.toString());
    }
  }
}
