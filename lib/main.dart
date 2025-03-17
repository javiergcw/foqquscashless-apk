import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:foqquscashless/utils/keys.dart';
import 'package:foqquscashless/services/manilla_service.dart';
import 'package:foqquscashless/models/cashless/manilla_model.dart';

const bool isProduction = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: isProduction ? Keys.prodApiKey : Keys.devApiKey,
      appId: isProduction ? Keys.prodAppId : Keys.devAppId,
      messagingSenderId:
          isProduction ? Keys.prodMessagingSenderId : Keys.devMessagingSenderId,
      projectId: isProduction ? Keys.prodProjectId : Keys.devProjectId,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foqqus Cashless',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.foqquscashless/app');
  String _lastAction = '';
  String _lastTimestamp = '';
  bool _isChannelReady = false;
  final ManillaService _manillaService = ManillaService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChannel();
  }

  Future<void> _initializeChannel() async {
    try {
      await Future.delayed(const Duration(
          milliseconds: 500)); // Dar tiempo a que la plataforma se inicialice
      _setupMethodChannel();
      setState(() {
        _isChannelReady = true;
      });
      _processInitialIntent();
    } catch (e) {
      debugPrint('Error initializing channel: $e');
      _showMessage('Error al inicializar el canal: $e');
    }
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      debugPrint('Método recibido: ${call.method}');
      debugPrint('Argumentos recibidos: ${call.arguments}');

      if (call.method == 'handleIntent') {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(call.arguments);
        _handleIntentData(data);
      }
      return null;
    });
  }

  Future<void> _processInitialIntent() async {
    if (!_isChannelReady) {
      debugPrint('Canal no está listo aún');
      return;
    }

    try {
      debugPrint('Procesando intent inicial...');
      final result = await platform.invokeMethod('getInitialIntent');
      debugPrint('Resultado del intent inicial: $result');

      if (result != null) {
        _handleIntentData(Map<String, dynamic>.from(result));
      }
    } on PlatformException catch (e) {
      debugPrint('Error processing initial intent: ${e.message}');
      _showMessage('Error al procesar el intent inicial: ${e.message}');
    } catch (e) {
      debugPrint('Error general: $e');
      _showMessage('Error inesperado: $e');
    }
  }

  void _handleIntentData(Map<String, dynamic> data) {
    final accion = data['accion'] as String?;
    final timestamp = data['timestamp'] as String?;

    setState(() {
      _lastAction = accion ?? '';
      _lastTimestamp = timestamp ?? '';
    });

    if (accion != null && accion.isNotEmpty) {
      _showMessage('Acción recibida: $accion\nTimestamp: $timestamp');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processInitialIntent();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _volverAWeb() async {
    try {
      debugPrint('Volviendo al navegador...');
      await SystemNavigator.pop();
    } catch (e) {
      debugPrint('Error al volver al navegador: $e');
      _showMessage('Error al volver a la página web');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foqqus Cashless'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade100, Colors.white],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_lastAction.isNotEmpty) ...[
                  Text(
                    'Última acción recibida:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _lastAction,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Timestamp:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _lastTimestamp,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: _volverAWeb,
                    icon: const Icon(Icons.web),
                    label: const Text('Volver a la Web'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Esperando acciones...',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ElevatedButton(
                  onPressed: () async {
                    Manilla newManilla = Manilla(
                      cashlessId: '1234567890',
                      clientId: 'exampleClientId',
                      status: false,
                      token: 'exampleToken',
                    );
                    bool success =
                        await _manillaService.createManilla(newManilla);
                    if (success) {
                      _showMessage('Manilla creada exitosamente');
                    } else {
                      _showMessage('Error al crear la manilla');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Crear manilla'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Crear una carpeta de servicios para consultas a Firebase
// Crear un modelo de ejemplo

