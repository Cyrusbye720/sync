package com.sync.alarm

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class SyncWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            partnerName: String = "YOUR PARTNER",
            status: String = "SCREEN ON · ACTIVE",
            timeText: String = "--:--",
            battery: String = "--%"
        ) {
            val views = RemoteViews(context.packageName, R.layout.sync_widget_layout)

            views.setTextViewText(R.id.widget_partner_name, partnerName.uppercase())
            views.setTextViewText(R.id.widget_status_text, status.uppercase())
            views.setTextViewText(R.id.widget_time_text, timeText)
            views.setTextViewText(R.id.widget_battery_text, battery)

            // Clicking the widget launches the app
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        fun updateAllWidgets(
            context: Context,
            partnerName: String,
            status: String,
            timeText: String,
            battery: String
        ) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, SyncWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            for (id in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, id, partnerName, status, timeText, battery)
            }
        }
    }
}
