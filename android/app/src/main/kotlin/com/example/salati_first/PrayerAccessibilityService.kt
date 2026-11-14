package com.example.salati_first

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class PrayerAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var isRunning: Boolean = false
    }

    private var lastRedirect = 0L
    private val safePackages = setOf(
        "com.android.systemui",
        "com.android.settings",
        "com.android.phone",
        "com.google.android.dialer",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
        "com.android.launcher3",
        "com.miui.home",
        "com.mi.android.globallauncher",
        "com.example.salati_first"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val prefs = getSharedPreferences("salati_native", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("strict_enabled", false)) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        if (safePackages.contains(pkg)) return

        // Restrict only during the first 60 minutes after a prayer time.
        val now = System.currentTimeMillis()
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        val prayerKeys = listOf("fajr", "dhuhr", "asr", "maghrib", "isha")
        var inPrayerWindow = false
        for (key in prayerKeys) {
            val prayerEpoch = prefs.getLong("time_$key", -1L)
            val completed = prefs.getBoolean("done_${date}_$key", false)
            if (prayerEpoch > 0L && !completed && now >= prayerEpoch && now < prayerEpoch + 60L * 60L * 1000L) {
                inPrayerWindow = true
                break
            }
        }
        if (!inPrayerWindow) return

        val elapsed = SystemClock.elapsedRealtime()
        if (elapsed - lastRedirect < 1200) return
        lastRedirect = elapsed

        val launch = packageManager.getLaunchIntentForPackage("com.example.salati_first") ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra("strict_redirect", true)
        startActivity(launch)
    }

    override fun onInterrupt() {}
    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }
}
