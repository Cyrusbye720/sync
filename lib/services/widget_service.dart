import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper to update the native Android Home Screen AppWidget.
class WidgetService {
  WidgetService._();

  static const _channel = MethodChannel('syncalarm/widget');

  static const _keyPartnerName = 'widget_partner_name';
  static const _keyStatus = 'widget_status';
  static const _keyTimeText = 'widget_time_text';
  static const _keyBattery = 'widget_battery';

  static Future<void> updateWidget({
    required String partnerName,
    required String status,
    required String timeText,
    required String battery,
  }) async {
    try {
      // Persist to SharedPreferences so the native widget provider
      // can read cached data on periodic onUpdate() calls.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPartnerName, partnerName);
      await prefs.setString(_keyStatus, status);
      await prefs.setString(_keyTimeText, timeText);
      await prefs.setString(_keyBattery, battery);

      await _channel.invokeMethod('updateWidget', {
        'partnerName': partnerName,
        'status': status,
        'timeText': timeText,
        'battery': battery,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[WidgetService] updateWidget error: $e');
    }
  }

  /// Read cached widget data from SharedPreferences.
  /// Returns null values if nothing cached yet.
  static Future<Map<String, String?>> getCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'partnerName': prefs.getString(_keyPartnerName),
        'status': prefs.getString(_keyStatus),
        'timeText': prefs.getString(_keyTimeText),
        'battery': prefs.getString(_keyBattery),
      };
    } catch (_) {
      return {};
    }
  }
}
