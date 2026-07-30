import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Helper to update the native Android Home Screen AppWidget.
class WidgetService {
  WidgetService._();

  static const _channel = MethodChannel('syncalarm/widget');

  static Future<void> updateWidget({
    required String partnerName,
    required String status,
    required String timeText,
    required String battery,
  }) async {
    try {
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
}
