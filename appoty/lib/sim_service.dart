import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.example.appoty/sim');
const _prefKey = 'preferred_sim_subscription_id';

class SimCard {
  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final int slotIndex;
  final String phoneNumber;

  const SimCard({
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    required this.slotIndex,
    this.phoneNumber = '',
  });

  String get label =>
      displayName.isNotEmpty ? displayName : 'SIM ${slotIndex + 1}';

  factory SimCard.fromMap(Map map) => SimCard(
    subscriptionId: map['subscriptionId'] as int,
    displayName: map['displayName'] as String? ?? '',
    carrierName: map['carrierName'] as String? ?? '',
    slotIndex: map['slotIndex'] as int,
    phoneNumber: map['phoneNumber'] as String? ?? '',
  );
}

class SimService {
  static Future<List<SimCard>> getSimCards() async {
    try {
      final result = await _channel.invokeMethod<List>('getSimCards');
      return (result ?? []).map((e) => SimCard.fromMap(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> callWithSim(String number, int subscriptionId) async {
    await _channel.invokeMethod('callWithSim', {
      'number': number,
      'subscriptionId': subscriptionId,
    });
  }

  /// Returns "ok" on USSD success, "fallback" if TelecomManager
  /// was used instead, or null on unexpected error.
  static Future<String?> callWithUssdFallback(
    String code,
    int subscriptionId,
  ) async {
    try {
      return await _channel.invokeMethod<String>('callWithUssdFallback', {
        'code': code,
        'subscriptionId': subscriptionId,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<int?> getPreferredSimId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKey);
  }

  static Future<void> savePreferredSimId(int subscriptionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, subscriptionId);
  }

  static Future<void> clearPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
