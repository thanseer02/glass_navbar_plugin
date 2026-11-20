package com.tnitish.native_glass_navbar

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeLiquidTabBarPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "native_liquid_tab_bar")
        channel.setMethodCallHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            "NativeTabBar",
            NativeTabBarFactory(binding.binaryMessenger)
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "isLiquidGlassSupported") {
            // Android 12+ (API 31+) has hardware RenderEffect blur and Android 13+ (API 33+) has AGSL shaders
            // Supports full native glass effect on API 31+
            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
