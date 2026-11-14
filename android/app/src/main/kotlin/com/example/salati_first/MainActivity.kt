package com.example.salati_first

import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channel = "salati_first/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("salati_native", Context.MODE_PRIVATE)
            when (call.method) {
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "isAccessibilityEnabled" -> {
                    val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                    result.success(manager.isEnabled && PrayerAccessibilityService.isRunning)
                }
                "setStrictMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    prefs.edit().putBoolean("strict_enabled", enabled).apply()
                    result.success(true)
                }
                "setPrayerTimes" -> {
                    val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                    val editor = prefs.edit()
                    for (item in items) {
                        val key = item["key"]?.toString() ?: continue
                        val epoch = (item["epoch"] as? Number)?.toLong() ?: continue
                        editor.putLong("time_$key", epoch)
                    }
                    editor.putString("prayer_date", java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()))
                    editor.apply()
                    result.success(true)
                }
                "setPrayerCompleted" -> {
                    val key = call.argument<String>("key") ?: ""
                    val date = call.argument<String>("date") ?: ""
                    prefs.edit().putBoolean("done_${date}_$key", true).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
