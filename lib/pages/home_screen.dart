import 'package:flutter/material.dart';
import 'package:foqquscashless/functions/service_invoked_method.dart';
import 'package:foqquscashless/widgets/data_display_widget.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ServiceInvokedMethod _serviceInvokedMethod = ServiceInvokedMethod();
  final MethodChannel _platform =
      const MethodChannel('com.example.foqquscashless/app');
  String? sessionId;
  String? nfcData;
  String? accion;
  String? timestamp;
  bool isReading = false;
  bool _isChannelReady = false;
  final bool _useRealNFC = false; // Cambiar a true para usar NFC real

  String _lastAction = '';
  String _lastTimestamp = '';
  String? _cashlessId;
  String? _cuentaId;
  String? _mesaId;
  Map<String, dynamic>? _datUpdate;
  String? _comandaId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceInvokedMethod.initializeChannel();
    _initializeChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _serviceInvokedMethod.initializeChannel();
      _initializeChannel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeChannel() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      _setupMethodChannel();
      _isChannelReady = true;
      await _processInitialIntent();
    } catch (e) {
      print('Error initializing channel: $e');
    }
  }

  void _setupMethodChannel() {
    _platform.setMethodCallHandler((call) async {
      print('Método recibido: ${call.method}');
      print('Argumentos recibidos: ${call.arguments}');

      if (call.method == 'handleIntent') {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(call.arguments);
        print('Datos del intent: $data');
        await _handleIntentData(data);
      }
      return null;
    });
  }

  Future<void> _processInitialIntent() async {
    if (!_isChannelReady) {
      print('Canal no está listo aún');
      return;
    }

    try {
      print('Procesando intent inicial...');
      final result = await _platform.invokeMethod('getInitialIntent');
      print('Resultado del intent inicial: $result');

      if (result != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(result);
        print('Datos recibidos: $data');
        await _handleIntentData(data);
      }
    } on PlatformException catch (e) {
      print('Error processing initial intent: ${e.message}');
    } catch (e) {
      print('Error general: $e');
    }
  }

  Future<void> _handleIntentData(Map<String, dynamic> data) async {
    print('Datos recibidos en _handleIntentData: $data');

    final Map<String, dynamic>? responseData =
        data['data'] as Map<String, dynamic>?;
    if (responseData == null) {
      print('No se encontró el objeto data en la respuesta');
      return;
    }

    final accion = responseData['accion'] as String? ?? '';
    final timestamp = responseData['timestamp'] as String? ?? '';
    final sessionId = responseData['sessionId'] as String? ?? '';

    print(
        'Parámetros procesados - accion: $accion, timestamp: $timestamp, sessionId: $sessionId');

    setState(() {
      this.accion = accion;
      this.timestamp = timestamp;
      this.sessionId = sessionId;
      _lastAction = accion;
      _lastTimestamp = timestamp;
    });

    print('Datos actualizados en el estado');
  }

  Future<void> _startNFCReading() async {
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId')),
      );
      return;
    }

    setState(() => isReading = true);

    try {
      if (_useRealNFC) {
        await NfcManager.instance.startSession(
          onDiscovered: (NfcTag tag) async {
            final ndef = Ndef.from(tag);
            if (ndef == null) {
              throw Exception('Tag no compatible con NDEF');
            }

            final message = await ndef.read();
            final records = message.records;

            if (records.isNotEmpty) {
              final data = String.fromCharCodes(records.first.payload);
              await _processNFCData(data);
            }
          },
        );
      } else {
        await Future.delayed(const Duration(seconds: 2));
        const simulatedData = 'CASH1234';
        await _processNFCData(simulatedData);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isReading = false);
      if (_useRealNFC) {
        NfcManager.instance.stopSession();
      }
    }
  }

  Future<void> _processNFCData(String data) async {
    setState(() => nfcData = data);
    await _sendDataToBackend(data);
    await _returnToWeb();
  }

  Future<void> _sendDataToBackend(String data, {bool isError = false}) async {
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('nfcReader').doc(sessionId).set({
        'nfcData': isError ? null : data,
        'timestamp': FieldValue.serverTimestamp(),
        'status': isError ? 'failed' : 'completed'
      });

      print('Datos NFC guardados en Firestore con sessionId: $sessionId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar datos en Firestore: $e')),
      );
    }
  }

  Future<void> _returnToWeb() async {
    try {
      print('Volviendo al navegador...');
      await _platform.invokeMethod('returnToWeb');
    } catch (e) {
      print('Error al volver al navegador: $e');
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
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Datos Recibidos:',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        _buildDataRow('Acción:', accion ?? 'No recibido'),
                        _buildDataRow('Timestamp:', timestamp ?? 'No recibido'),
                        _buildDataRow(
                            'Session ID:', sessionId ?? 'No recibido'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isReading ? null : _startNFCReading,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(isReading ? 'Leyendo...' : 'Leer NFC'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: isReading
                      ? null
                      : () => _sendDataToBackend('', isError: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Simular Error'),
                ),
                if (nfcData != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Datos NFC: $nfcData',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
