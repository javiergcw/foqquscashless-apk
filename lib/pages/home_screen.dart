/* import 'package:flutter/material.dart';
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
  String? type;
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

  // Lista para almacenar logs
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  
  // Variable para controlar visibilidad de logs
  bool _showLogs = true; // Cambiar a false para ocultar logs

  // Constantes para los tipos de acción
  static const Map<String, String> ActionType = {
    'READ': 'READ',
    'CREATE': 'CREATE',
    'ASSIGN_ACCOUNT': 'ASSIGN_ACCOUNT',
    'UPDATE_STATUS': 'UPDATE_STATUS',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addLog('HomeScreen inicializado');
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
      _addLog('Inicializando canal...');
      await Future.delayed(const Duration(milliseconds: 500));
      _setupMethodChannel();
      _isChannelReady = true;
      _addLog('Canal inicializado correctamente');
      await _processInitialIntent();
    } catch (e) {
      _addLog('Error initializing channel: $e');
    }
  }

  void _setupMethodChannel() {
    _platform.setMethodCallHandler((call) async {
      _addLog('Método recibido: ${call.method}');
      _addLog('Argumentos recibidos: ${call.arguments}');

      if (call.method == 'handleIntent') {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(call.arguments);
        _addLog('Datos del intent: $data');
        await _handleIntentData(data);
      }
      return null;
    });
  }

  Future<void> _processInitialIntent() async {
    if (!_isChannelReady) {
      _addLog('Canal no está listo aún');
      return;
    }

    try {
      _addLog('Procesando intent inicial...');
      final result = await _platform.invokeMethod('getInitialIntent');
      _addLog('Resultado del intent inicial: $result');

      if (result != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(result);
        _addLog('Datos recibidos: $data');
        await _handleIntentData(data);
      }
    } on PlatformException catch (e) {
      _addLog('Error processing initial intent: ${e.message}');
    } catch (e) {
      _addLog('Error general: $e');
    }
  }

  Future<void> _handleIntentData(Map<String, dynamic> data) async {
    _addLog('Datos recibidos en _handleIntentData: $data');

    final Map<String, dynamic>? responseData =
        data['data'] as Map<String, dynamic>?;
    if (responseData == null) {
      _addLog('No se encontró el objeto data en la respuesta');
      return;
    }

    final accion = responseData['accion'] as String? ?? '';
    final timestamp = responseData['timestamp'] as String? ?? '';
    final sessionId = responseData['sessionId'] as String? ?? '';
    final type = responseData['type'] as String? ?? '';

    _addLog('Parámetros procesados - accion: $accion, timestamp: $timestamp, sessionId: $sessionId, type: $type');

    setState(() {
      this.accion = accion;
      this.timestamp = timestamp;
      this.sessionId = sessionId;
      this.type = type;
      _lastAction = accion;
      _lastTimestamp = timestamp;
    });

    _addLog('Datos actualizados en el estado');
  }

  Future<void> _acceptAction() async {
    _addLog('=== _acceptAction iniciado ===');
    _addLog('sessionId: $sessionId');
    _addLog('type: $type');
    
    if (sessionId == null || type == null) {
      _addLog('ERROR: sessionId o type son nulos');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId o type')),
      );
      return;
    }

    _addLog('Iniciando proceso de aceptación...');
    setState(() => isReading = true);

    try {
      _addLog('Guardando en Firebase...');
      // Guardar en Firebase con el type
      await _sendDataToBackend('', type: type);
      _addLog('Datos guardados exitosamente en Firebase');
      
      _addLog('Retornando a web...');
      await _returnToWeb();
      _addLog('Retorno a web completado');
    } catch (e) {
      _addLog('ERROR en _acceptAction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _addLog('Finalizando _acceptAction');
      setState(() => isReading = false);
    }
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

  Future<void> _sendDataToBackend(String data, {bool isError = false, String? type}) async {
    _addLog('=== _sendDataToBackend iniciado ===');
    _addLog('sessionId: $sessionId');
    _addLog('data: $data');
    _addLog('isError: $isError');
    _addLog('type: $type');
    
    if (sessionId == null || sessionId!.isEmpty) {
      _addLog('ERROR: sessionId es nulo o vacío');
      throw Exception('sessionId es requerido');
    }
    
    try {
      final firestore = FirebaseFirestore.instance;
      _addLog('Firestore instance obtenida');

      final documentData = {
        'nfcData': isError ? null : data,
        'timestamp': FieldValue.serverTimestamp(),
        'status': isError ? 'failed' : 'completed',
        'type': type ?? 'READ',
        'sessionId': sessionId, // Asegurar que sessionId esté en los datos
        'accion': accion,
        'timestamp_param': timestamp,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      _addLog('Datos a guardar: $documentData');
      _addLog('Guardando en colección: nfcReader, documento: $sessionId');

      // Usar set con merge para asegurar que se guarde
      await firestore.collection('nfcReader').doc(sessionId).set(
        documentData,
        SetOptions(merge: true)
      );
      
      _addLog('Datos guardados exitosamente en Firestore');
      _addLog('Documento ID: $sessionId');
      _addLog('Colección: nfcReader');
      
      // Verificar que se guardó correctamente
      final docSnapshot = await firestore.collection('nfcReader').doc(sessionId).get();
      if (docSnapshot.exists) {
        _addLog('Documento verificado - existe en Firebase');
        _addLog('Datos del documento: ${docSnapshot.data()}');
      } else {
        _addLog('ADVERTENCIA: Documento no encontrado después de guardar');
      }
      
    } catch (e) {
      _addLog('ERROR en _sendDataToBackend: $e');
      _addLog('Stack trace: ${StackTrace.current}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar datos en Firestore: $e')),
      );
      rethrow; // Re-lanzar el error para que _acceptAction lo capture
    }
  }

  Future<void> _returnToWeb() async {
    _addLog('=== _returnToWeb iniciado ===');
    try {
      _addLog('Invocando método returnToWeb en platform channel...');
      await _platform.invokeMethod('returnToWeb');
      _addLog('Método returnToWeb invocado exitosamente');
    } catch (e) {
      _addLog('ERROR en _returnToWeb: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al volver al navegador: $e')),
      );
      rethrow; // Re-lanzar el error para que _acceptAction lo capture
    }
  }

  Future<void> _testFirebaseConnection() async {
    _addLog('=== Probando conexión a Firebase ===');
    try {
      final firestore = FirebaseFirestore.instance;
      _addLog('Firestore instance obtenida');
      
      // Crear un documento de prueba
      final testDocId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testData = {
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'Prueba de conexión Firebase'
      };
      
      _addLog('Creando documento de prueba: $testDocId');
      await firestore.collection('nfcReader').doc(testDocId).set(testData);
      _addLog('Documento de prueba creado exitosamente');
      
      // Verificar que existe
      final docSnapshot = await firestore.collection('nfcReader').doc(testDocId).get();
      if (docSnapshot.exists) {
        _addLog('Documento de prueba verificado - Firebase funciona correctamente');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase funciona correctamente')),
        );
      } else {
        _addLog('ERROR: Documento de prueba no encontrado');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Documento no encontrado en Firebase')),
        );
      }
      
    } catch (e) {
      _addLog('ERROR en prueba de Firebase: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión Firebase: $e')),
      );
    }
  }

  // Método para agregar logs
  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19); // HH:MM:SS
    final logMessage = '[$timestamp] $message';
    
    // Siempre agregar el log a la lista
    setState(() {
      _logs.add(logMessage);
      // Mantener solo los últimos 50 logs
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });
    
    // Solo hacer debugPrint si los logs están activos
    if (_showLogs) {
      debugPrint(logMessage);
    }
    
    // Auto-scroll al final solo si los logs están visibles
    if (_showLogs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // Método para limpiar logs
  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
    _addLog('Logs limpiados');
  }

  // Método para alternar visibilidad de logs
  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
    });
    _addLog('Logs ${_showLogs ? 'activados' : 'desactivados'}');
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
                        _buildDataRow('Tipo:', type ?? 'No recibido'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isReading ? null : () {
                    _addLog('=== Botón Aceptar presionado ===');
                    _acceptAction();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(isReading ? 'Procesando...' : 'Aceptar'),
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
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: isReading ? null : _testFirebaseConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Probar Firebase'),
                ),
                if (nfcData != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Datos NFC: $nfcData',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 20),
                // Botón para alternar logs
                ElevatedButton(
                  onPressed: _toggleLogs,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showLogs ? Colors.blue.shade600 : Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(_showLogs ? 'Ocultar Logs' : 'Mostrar Logs'),
                ),
                const SizedBox(height: 20),
                // Widget de logs (solo se muestra si _showLogs es true)
                if (_showLogs) ...[
                  Card(
                    color: Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Logs de Debug:',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: _clearLogs,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey.shade600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Limpiar'),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_logs.length} logs',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: _logs.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No hay logs aún...',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _logScrollController,
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _logs.length,
                                    itemBuilder: (context, index) {
                                      final log = _logs[index];
                                      final isError = log.contains('ERROR');
                                      final isWarning = log.contains('ADVERTENCIA');
                                      
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 1),
                                        child: Text(
                                          log,
                                          style: TextStyle(
                                            color: isError 
                                                ? Colors.red.shade300
                                                : isWarning 
                                                    ? Colors.orange.shade300
                                                    : Colors.green.shade300,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
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
 */