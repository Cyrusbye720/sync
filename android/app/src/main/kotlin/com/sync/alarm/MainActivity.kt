package com.sync.alarm

import android.os.Bundle
import android.view.WindowManager
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import dev.fluttercommunity.plus.alarm.AlarmService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Allow showing over lock screen when alarm fires.
        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Plug in the alarm package's alarm background service.
        AlarmService.setPluginRegistrant { registrar ->
            registrar?.platformViewRegistry
            FlutterLocalNotificationsPlugin()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Configure full-screen when-launched flag for the ring screen.
    }
}
