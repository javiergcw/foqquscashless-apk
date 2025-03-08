package com.example.foqquscashless

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.foqquscashless/app"
    private var initialIntent: Intent? = null
    private lateinit var channel: MethodChannel
    private var isChannelReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "onCreate called")
        initialIntent = intent
        Log.d("MainActivity", "Initial intent stored: $initialIntent")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "Configurando FlutterEngine")
        
        try {
            channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler { call, result ->
                Log.d("MainActivity", "Method call received: ${call.method}")
                when (call.method) {
                    "getInitialIntent" -> {
                        Log.d("MainActivity", "getInitialIntent called")
                        handleIntent(initialIntent, result)
                    }
                    else -> {
                        Log.d("MainActivity", "Method not implemented: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
            isChannelReady = true
            Log.d("MainActivity", "Canal configurado exitosamente")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error configurando el canal: ${e.message}")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("MainActivity", "onNewIntent called with intent: $intent")
        setIntent(intent)
        initialIntent = intent
        handleIntent(intent, null)
    }

    private fun handleIntent(intent: Intent?, result: MethodChannel.Result?) {
        Log.d("MainActivity", "handleIntent called with intent: $intent")
        if (intent?.action == Intent.ACTION_VIEW) {
            val uri = intent.data
            Log.d("MainActivity", "URI received: $uri")
            if (uri != null) {
                val data = mutableMapOf<String, String>()
                data["accion"] = uri.getQueryParameter("accion") ?: ""
                data["timestamp"] = uri.getQueryParameter("timestamp") ?: ""
                
                Log.d("MainActivity", "Data extracted: $data")
                
                if (result != null) {
                    try {
                        result.success(data)
                        Log.d("MainActivity", "Data sent through result")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error sending data through result: ${e.message}")
                        result.error("INTENT_ERROR", "Error processing intent", e.message)
                    }
                } else if (isChannelReady) {
                    try {
                        runOnUiThread {
                            channel.invokeMethod("handleIntent", data)
                            Log.d("MainActivity", "Data sent through channel")
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error sending data through channel: ${e.message}")
                    }
                } else {
                    Log.e("MainActivity", "Channel not ready")
                }
            } else {
                Log.d("MainActivity", "No URI in intent")
                result?.success(null)
            }
        } else {
            Log.d("MainActivity", "Not a VIEW action or no intent")
            result?.success(null)
        }
    }
}
