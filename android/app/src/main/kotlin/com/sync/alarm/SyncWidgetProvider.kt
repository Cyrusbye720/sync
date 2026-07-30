package com.sync.alarm

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews

class SyncWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        try {
            // Try FlutterSharedPreferences (standard Flutter plugin file with flutter. prefix)
            var prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var partnerName = prefs.getString("flutter.widget_partner_name", "") ?: ""
            var status = prefs.getString("flutter.widget_status", "") ?: ""
            var timeText = prefs.getString("flutter.widget_time_text", "") ?: ""
            var battery = prefs.getString("flutter.widget_battery", "") ?: ""

            // Fallback: try default SharedPreferences (some plugin versions use this)
            if (partnerName.isEmpty()) {
                prefs = context.getSharedPreferences("com.sync.alarm_preferences", Context.MODE_PRIVATE)
                partnerName = prefs.getString("widget_partner_name", "") ?: ""
                status = prefs.getString("widget_status", "") ?: ""
                timeText = prefs.getString("widget_time_text", "") ?: ""
                battery = prefs.getString("widget_battery", "") ?: ""
            }

            // Fallback: try default prefs file without prefix
            if (partnerName.isEmpty()) {
                prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                partnerName = prefs.getString("widget_partner_name", "") ?: ""
                status = prefs.getString("widget_status", "") ?: ""
                timeText = prefs.getString("widget_time_text", "") ?: ""
                battery = prefs.getString("widget_battery", "") ?: ""
            }

            for (appWidgetId in appWidgetIds) {
                updateAppWidget(
                    context, appWidgetManager, appWidgetId,
                    partnerName.ifEmpty { "YOUR PARTNER" },
                    status.ifEmpty { "SCREEN ON · ACTIVE" },
                    timeText.ifEmpty { "--:--" },
                    battery.ifEmpty { "--%" }
                )
            }
        } catch (e: Exception) {
            Log.e("SyncWidgetProvider", "onUpdate failed", e)
        }
    }

    companion object {
        private const val TAG = "SyncWidgetProvider"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            partnerName: String = "YOUR PARTNER",
            status: String = "SCREEN ON · ACTIVE",
            timeText: String = "--:--",
            battery: String = "--%"
        ) {
            try {
                val views = RemoteViews(context.packageName, R.layout.sync_widget_layout)

                views.setTextViewText(R.id.widget_partner_name, partnerName.uppercase())
                views.setTextViewText(R.id.widget_status_text, status.uppercase())
                views.setTextViewText(R.id.widget_time_text, timeText)
                views.setTextViewText(R.id.widget_battery_text, battery)

                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget failed for id=$appWidgetId", e)
            }
        }

        fun updateAllWidgets(
            context: Context,
            partnerName: String,
            status: String,
            timeText: String,
            battery: String
        ) {
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val componentName = ComponentName(context, SyncWidgetProvider::class.java)
                val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
                for (id in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, id, partnerName, status, timeText, battery)
                }
            } catch (e: Exception) {
                Log.e(TAG, "updateAllWidgets failed", e)
            }
        }
    }
}
