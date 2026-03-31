import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'activation_config.dart';

class ActivationService {
  static const _tokenKey = 'act_tok_v1';
  static const _didKey = 'act_did_v1';

  /// Returns the unique Android ID of this device (16 hex chars).
  static Future<String> getDeviceId() async {
    final plugin = DeviceInfoPlugin();
    final info = await plugin.androidInfo;
    return info.id.toLowerCase();
  }

  /// Returns true if this device has a valid activation token.
  static Future<bool> isActivated() async {
    try {
      final deviceId = await getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final storedDid = prefs.getString(_didKey);

      if (token == null || storedDid == null) return false;
      // Device ID must match what was stored at activation time
      if (storedDid != deviceId) return false;

      return _verifyToken(token, deviceId);
    } catch (_) {
      return false;
    }
  }

  /// Verifies [token] against the embedded public key and [deviceId].
  static String? lastError;

  static bool _verifyToken(String token, String deviceId) {
    try {
      if (kEcPublicKeyPem.contains('PLACEHOLDER')) {
        lastError = 'PLACEHOLDER key';
        return false;
      }
      final jwt = JWT.verify(token, ECPublicKey(kEcPublicKeyPem));
      final payload = jwt.payload as Map<String, dynamic>;
      final jwtDeviceId = payload['deviceId'] as String?;
      final jwtApp = payload['app'] as String?;
      if (jwtDeviceId != deviceId) {
        lastError = 'deviceId mismatch: JWT=$jwtDeviceId device=$deviceId';
        return false;
      }
      if (jwtApp != kAppId) {
        lastError = 'app mismatch: JWT=$jwtApp expected=$kAppId';
        return false;
      }
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// Tries to activate this device with [token].
  /// Returns true on success, false if token is invalid.
  static Future<bool> activate(String token) async {
    try {
      final deviceId = await getDeviceId();
      if (!_verifyToken(token, deviceId)) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_didKey, deviceId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes activation (for testing / revocation).
  static Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_didKey);
  }

  /// Formats a raw token (base64url chars) for display: groups of 6, separated
  /// by dashes so it is easier to read aloud (e.g. ABCDEF-GHIJKL-...).
  static String formatToken(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 6 == 0) buf.write('-');
      buf.write(clean[i]);
    }
    return buf.toString();
  }

  static String stripFormatting(String input) =>
      input.replaceAll('-', '').replaceAll(' ', '').trim();
}
