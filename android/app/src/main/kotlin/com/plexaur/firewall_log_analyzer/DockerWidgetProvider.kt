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

class DockerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d("DockerWidget", "onUpdate called for ${appWidgetIds.size} widget(s)")

        val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId, widgetData)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            Log.d("DockerWidget", "Received APPWIDGET_UPDATE broadcast")
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.docker_widget)

        // 1. Bind data
        try {
            val dockerCount = widgetData.getString("docker_count", "0/0") ?: "0/0"
            val rawStatus = widgetData.getString("server_status", "Offline") ?: "Offline"
            val healthMsg = widgetData.getString("docker_health", "No data") ?: "No data"

            val isOnline = rawStatus.lowercase().let {
                it.contains("online") || it.contains("connecting") || it.contains("sync")
            }
            val statusText = if (isOnline) "● ${rawStatus.uppercase()}" else "● OFFLINE"

            Log.d("DockerWidget", "Widget $appWidgetId: $dockerCount | $rawStatus | $healthMsg")

            views.setTextViewText(R.id.widget_docker_count, dockerCount)
            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_docker_health, healthMsg)

            // Status color
            if (isOnline) {
                views.setTextColor(R.id.widget_status, Color.parseColor("#6EE7B7"))
            } else {
                views.setTextColor(R.id.widget_status, Color.parseColor("#FF5252"))
            }

            // Health color
            try {
                val parts = dockerCount.split("/")
                if (parts.size == 2 && parts[0] == parts[1] && parts[0] != "0") {
                    views.setTextColor(R.id.widget_docker_health, Color.parseColor("#81C784"))
                } else if (dockerCount != "0/0") {
                    views.setTextColor(R.id.widget_docker_health, Color.parseColor("#FFA726"))
                } else {
                    views.setTextColor(R.id.widget_docker_health, Color.parseColor("#88FFFFFF"))
                }
            } catch (e: Exception) {
                views.setTextColor(R.id.widget_docker_health, Color.parseColor("#88FFFFFF"))
            }
        } catch (e: Exception) {
            Log.e("DockerWidget", "Data bind error", e)
        }

        // 2. Tap to open app
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    1,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.docker_widget_root, pendingIntent)
            }
        } catch (e: Exception) {
            Log.e("DockerWidget", "PendingIntent error", e)
        }

        // 3. Push to launcher
        appWidgetManager.updateAppWidget(appWidgetId, views)
        Log.d("DockerWidget", "✅ Widget $appWidgetId pushed to launcher")
    }
}
