class ApiConfig {
  static const String defaultBaseUrl = 'https://internhub-sas-production-b44c.up.railway.app';

  static String baseUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: defaultBaseUrl);

  /// Absolute URL for an uploaded file: files kept on the API server come back as `/uploads/...`.
  static String mediaUrl(String url) => url.startsWith('/') ? '$baseUrl$url' : url;

  static String url(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$cleanPath';
  }

  // Validation Limits matching web frontend (src/lib/validation.ts)
  static const int textLimitShort = 100;
  static const int textLimitMedium = 300;
  static const int textLimitLong = 1000;
  static const int textLimitXLong = 3000;
  static const int passwordMin = 8;
  static const int passwordMax = 100;
  static const int phoneDigitLimit = 10;

  static final RegExp phoneRegex = RegExp(r'^(?:\+91)?[6-9]\d{9}$');
  static final RegExp emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp nameRegex = RegExp(r"^[\p{L}\s'\-\.]+$", unicode: true);

  static bool isValidEmail(String email) {
    return emailRegex.hasMatch(email.trim());
  }

  static bool isValidPhone(String phone) {
    final clean = phone.replaceAll(RegExp(r'[\s\-]'), '');
    return phoneRegex.hasMatch(clean);
  }

  static bool isValidName(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty && trimmed.length <= textLimitShort && nameRegex.hasMatch(trimmed);
  }

  /// The server's rule for every password endpoint: 8+ characters with at least one number.
  static bool isValidPassword(String password) {
    return password.length >= passwordMin && password.length <= passwordMax && password.contains(RegExp(r'\d'));
  }

  static const String passwordRule = 'At least $passwordMin characters, including a number';
}
