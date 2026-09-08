import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const String _keyToken = 'ih_auth_token';
  static const String _keyRemember = 'ih_remember_me';
  static const String _keyOrgId = 'ih_organization_id';
  static const String _keySavedEmail = 'ih_saved_email';

  static String? _inMemoryToken;
  static String? _inMemoryOrgId;

  static String? get inMemoryToken => _inMemoryToken;
  static String? get inMemoryOrgId => _inMemoryOrgId;

  static Future<void> saveSession({
    required String token,
    required bool remember,
    String? orgId,
    String? email,
  }) async {
    _inMemoryToken = token;
    _inMemoryOrgId = orgId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemember, remember);

    if (remember) {
      await prefs.setString(_keyToken, token);
      if (email != null && email.isNotEmpty) {
        await prefs.setString(_keySavedEmail, email);
      }
    } else {
      await prefs.remove(_keyToken);
    }

    if (orgId != null && orgId.isNotEmpty) {
      await prefs.setString(_keyOrgId, orgId);
    }
  }

  static Future<String?> getToken() async {
    if (_inMemoryToken != null && _inMemoryToken!.isNotEmpty) {
      return _inMemoryToken;
    }
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRemember) ?? false;
    if (remember) {
      _inMemoryToken = prefs.getString(_keyToken);
    }
    return _inMemoryToken;
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedEmail);
  }

  static Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRemember) ?? true;
  }

  static Future<String?> getOrgId() async {
    if (_inMemoryOrgId != null) return _inMemoryOrgId;
    final prefs = await SharedPreferences.getInstance();
    _inMemoryOrgId = prefs.getString(_keyOrgId);
    return _inMemoryOrgId;
  }

  static Future<void> clearSession() async {
    _inMemoryToken = null;
    _inMemoryOrgId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyOrgId);
  }
}
