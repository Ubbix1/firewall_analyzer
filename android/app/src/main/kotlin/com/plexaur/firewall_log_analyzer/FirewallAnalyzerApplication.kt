package com.plexaur.firewall_log_analyzer

import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class FirewallAnalyzerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val securityChannel = NotificationChannel(
            "security_alerts",
            "Security Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Critical and suspicious firewall alerts"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 200, 300)
        }
        val batteryChannel = NotificationChannel(
            "battery_alerts",
            "Battery Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Battery level and charging notifications"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
        }

        manager.createNotificationChannel(securityChannel)
        manager.createNotificationChannel(batteryChannel)
    }
}
