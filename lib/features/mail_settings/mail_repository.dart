import '../../core/api/api_client.dart';
import 'models/mail_models.dart';

class MailRepository {
  final ApiClient _client;

  MailRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// GET /api/org/smtp
  Future<OrgSmtpConfig> getSmtpConfig() async {
    final res = await _client.get('/api/org/smtp');
    if (res is Map<String, dynamic>) {
      return normalizeOrgSmtpConfig(res);
    }
    throw Exception('Failed to load SMTP configuration');
  }

  /// PUT /api/org/smtp
  Future<OrgSmtpConfig> saveSmtpConfig(Map<String, dynamic> payload) async {
    final res = await _client.put('/api/org/smtp', body: payload);
    if (res is Map<String, dynamic>) {
      return normalizeOrgSmtpConfig(res);
    }
    throw Exception('Failed to save SMTP configuration');
  }

  /// POST /api/org/smtp/test
  Future<TestOrgSmtpResponse> testSmtp(Map<String, dynamic> payload) async {
    final res = await _client.post('/api/org/smtp/test', body: payload);
    if (res is Map<String, dynamic>) {
      return TestOrgSmtpResponse.fromJson(res);
    }
    throw Exception('Failed to send test email');
  }

  /// GET /api/org/smtp/logs?page&page_size&email_type&status
  Future<SmtpDeliveryLogsResponse> getDeliveryLogs({
    int page = 1,
    int pageSize = 20,
    String? emailType,
    String? status,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (emailType != null && emailType.isNotEmpty && emailType != 'all') {
      query['email_type'] = emailType;
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      query['status'] = status;
    }

    final res = await _client.get('/api/org/smtp/logs', queryParameters: query);
    if (res is Map<String, dynamic>) {
      return SmtpDeliveryLogsResponse.fromJson(res);
    }
    throw Exception('Failed to load delivery logs');
  }
}
