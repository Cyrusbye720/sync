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
            val (partnerName, status, timeText, battery) = readWidgetData(context)

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
            // Try to show a safe fallback on each widget
            for (appWidgetId in appWidgetIds) {
                try {
                    showFallbackWidget(context, appWidgetManager, appWidgetId)
                } catch (_: Exception) {}
            }
        }
    }

    /**
     * Safely read widget data from SharedPreferences.
     * Tries FlutterSharedPreferences first (flutter. prefix),
     * then falls back to unprefixed keys.
     */
    private fun readWidgetData(context: Context): WidgetData {
        return try {
            // Try FlutterSharedPreferences (standard Flutter plugin file with flutter. prefix)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var partnerName = prefs.getString("flutter.widget_partner_name", null) ?: ""
            var status = prefs.getString("flutter.widget_status", null) ?: ""
            var timeText = prefs.getString("flutter.widget_time_text", null) ?: ""
            var battery = prefs.getString("flutter.widget_battery", null) ?: ""

            // Fallback: try unprefixed keys (some plugin versions)
            if (partnerName.isEmpty()) {
                partnerName = prefs.getString("widget_partner_name", null) ?: ""
                status = prefs.getString("widget_status", null) ?: ""
                timeText = prefs.getString("widget_time_text", null) ?: ""
                battery = prefs.getString("widget_battery", null) ?: ""
            }

            WidgetData(partnerName, status, timeText, battery)
        } catch (e: Exception) {
            Log.e("SyncWidgetProvider", "readWidgetData failed", e)
            WidgetData("", "", "", "")
        }
    }

    /** Show a safe fallback when normal widget update fails. */
    private fun showFallbackWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        try {
            val views = RemoteViews(context.packageName, R.layout.sync_widget_layout)
            views.setTextViewText(R.id.widget_partner_name, "SYNC")
            views.setTextViewText(R.id.widget_status_text, "OPEN APP TO SYNC")
            views.setTextViewText(R.id.widget_time_text, "--:--")
            views.setTextViewText(R.id.widget_battery_text, "--%")
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            Log.e(TAG, "showFallbackWidget failed for id=$appWidgetId", e)
        }
    }

    private data class WidgetData(
        val partnerName: String,
        val status: String,
        val timeText: String,
        val battery: String
    )

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
