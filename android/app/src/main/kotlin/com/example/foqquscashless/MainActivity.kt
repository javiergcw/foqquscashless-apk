package com.example.foqquscashless

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.app.Activity

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
                    "sendDataToWeb" -> {
                        Log.d("MainActivity", "sendDataToWeb called")
                        val data = call.arguments as? Map<String, Any>
                        if (data != null) {
                            returnToWebWithData(data, result)
                        } else {
                            result.error("INVALID_DATA", "Los datos son nulos o inválidos", null)
                        }
                    }
                    "returnToWeb" -> {
                        Log.d("MainActivity", "returnToWeb called")
                        returnToWeb(result)
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
                val data = mutableMapOf<String, Any>()
                
                // Procesar cada parámetro individualmente
                val accion = uri.getQueryParameter("accion")
                val timestamp = uri.getQueryParameter("timestamp")
                val sessionId = uri.getQueryParameter("sessionId")
                
                Log.d("MainActivity", "Parámetros raw - accion: $accion, timestamp: $timestamp, sessionId: $sessionId")
                
                // Asignar valores procesados
                data["accion"] = accion?.trim() ?: ""
                data["timestamp"] = timestamp?.trim() ?: ""
                data["sessionId"] = sessionId?.trim() ?: ""
                
                Log.d("MainActivity", "Data extracted: $data")
                
                if (result != null) {
                    try {
                        result.success(data)
                        Log.d("MainActivity", "Data sent through result")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error sending data through result: ${e.message}")
                        result.error("INTENT_ERROR", "Error processing intent", e.message)
                    }
                }
                
                // Enviar datos a través del canal
                try {
                    runOnUiThread {
                        val responseData = mapOf(
                            "type" to "cashlessResponse",
                            "data" to data
                        )
                        channel.invokeMethod("handleIntent", responseData)
                        Log.d("MainActivity", "Data sent through channel")
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error sending data through channel: ${e.message}")
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

    private fun returnToWeb(result: MethodChannel.Result?) {
        try {
            Log.d("MainActivity", "Finalizando actividad para regresar a WebView")
            
            // Crear el Intent de retorno
            val returnIntent = Intent()
            
            // Establecer el resultado y finalizar la actividad
            setResult(Activity.RESULT_OK, returnIntent)
            finish()
            
            result?.success(true)
            Log.d("MainActivity", "Actividad finalizada exitosamente")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error al finalizar actividad: ${e.message}")
            result?.error("RETURN_ERROR", "Error al regresar a WebView", e.message)
        }
    }

    private fun returnToWebWithData(data: Map<String, Any>, result: MethodChannel.Result?) {
        try {
            Log.d("MainActivity", "Finalizando actividad para regresar a WebView con datos: $data")
            
            // Crear el Intent de retorno con los datos
            val returnIntent = Intent()
            
            // Convertir el Map a un Bundle para asegurar la compatibilidad
            val bundle = Bundle()
            for ((key, value) in data) {
                try {
                    when (value) {
                        is String -> bundle.putString(key, value)
                        is Int -> bundle.putInt(key, value)
                        is Boolean -> bundle.putBoolean(key, value)
                        is Long -> bundle.putLong(key, value)
                        is Double -> bundle.putDouble(key, value)
                        is Float -> bundle.putFloat(key, value)
                        null -> bundle.putString(key, "") // Manejar valores nulos
                        else -> bundle.putString(key, value.toString())
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error al procesar el valor para la clave $key: ${e.message}")
                    bundle.putString(key, "") // En caso de error, usar string vacío
                }
            }
            
            returnIntent.putExtra("cashlessData", bundle)
            
            // Establecer el resultado y finalizar la actividad
            setResult(Activity.RESULT_OK, returnIntent)
            finish()
            
            result?.success(true)
            Log.d("MainActivity", "Actividad finalizada exitosamente con datos")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error al finalizar actividad con datos: ${e.message}")
            result?.error("RETURN_ERROR", "Error al regresar a WebView con datos", e.message)
        }
    }
}
