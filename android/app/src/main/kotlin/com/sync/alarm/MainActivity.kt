package com.sync.alarm

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val DEEPLINK_CHANNEL = "syncalarm/deeplink"
    private val WIDGET_CHANNEL = "syncalarm/widget"
    private var deeplinkChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deeplinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEPLINK_CHANNEL)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                val partnerName = call.argument<String>("partnerName") ?: "YOUR PARTNER"
                val status = call.argument<String>("status") ?: "SCREEN ON · ACTIVE"
                val timeText = call.argument<String>("timeText") ?: "--:--"
                val battery = call.argument<String>("battery") ?: "--%"

                SyncWidgetProvider.updateAllWidgets(
                    context,
                    partnerName,
                    status,
                    timeText,
                    battery
                )
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "syncalarm" && data.host == "auth-callback") {
            val code = data.getQueryParameter("code")
            if (!code.isNullOrEmpty()) {
                deeplinkChannel?.invokeMethod("handleAuthCallback", code)
            }
        }
    }
}
