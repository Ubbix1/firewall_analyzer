package com.plexaur.firewall_log_analyzer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import android.util.Log

class BatteryWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d("BatteryWidget", "onUpdate called for ${appWidgetIds.size} widget(s)")

        // Read directly from home_widget SharedPreferences
        val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, widgetData)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Also handle manual refresh broadcasts
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            Log.d("BatteryWidget", "Received APPWIDGET_UPDATE broadcast")
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.battery_widget)

        // 1. Bind data
        try {
            val battery = widgetData.getString("server_battery", "--%") ?: "--%"
            val rawStatus = widgetData.getString("server_status", "Offline") ?: "Offline"
            val temp = widgetData.getString("server_temp", "--°C") ?: "--°C"
            val rawSsh = widgetData.getString("server_ssh", "0 SSH") ?: "0 SSH"

            val isOnline = rawStatus.lowercase().let {
                it.contains("online") || it.contains("connecting") || it.contains("sync")
            }
            val statusText = if (isOnline) "● ${rawStatus.uppercase()}" else "● OFFLINE"
            val sshText = if (rawSsh.contains("active")) rawSsh else "${rawSsh.replace(" SSH", "")} active"

            Log.d("BatteryWidget", "Widget $appWidgetId: $battery | $rawStatus | $temp | $sshText")

            views.setTextViewText(R.id.widget_battery, battery)
            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_temp, temp)
            views.setTextViewText(R.id.widget_ssh, sshText)

            if (isOnline) {
                views.setTextColor(R.id.widget_status, Color.parseColor("#6EE7B7"))
            } else {
                views.setTextColor(R.id.widget_status, Color.parseColor("#FF5252"))
            }
        } catch (e: Exception) {
            Log.e("BatteryWidget", "Data bind error", e)
        }

        // 2. Tap to open app
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
        } catch (e: Exception) {
            Log.e("BatteryWidget", "PendingIntent error", e)
        }

        // 3. Push to launcher
        appWidgetManager.updateAppWidget(appWidgetId, views)
        Log.d("BatteryWidget", "✅ Widget $appWidgetId pushed to launcher")
    }
}
