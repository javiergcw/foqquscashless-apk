import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

import 'package:foqquscashless/utils/keys.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:foqquscashless/services/nfc_service.dart';
import 'package:flutter/services.dart';

const bool isProduction = true;

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
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF007AFF),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
      ),
      home: const NFCScreen(),
    );
  }
}

class NFCScreen extends StatefulWidget {
  const NFCScreen({super.key});

  @override
  State<NFCScreen> createState() => _NFCScreenState();
}

class _NFCScreenState extends State<NFCScreen> with WidgetsBindingObserver {
  final MethodChannel _platform =
      const MethodChannel('com.example.foqquscashless/app');
  String? sessionId;
  String? clientId;
  String? nfcData;
  String? accion;
  String? timestamp;
  String? type;
  bool isReading = false;
  bool _isChannelReady = false;
  final bool _useRealNFC = true;

  // Lista para almacenar logs
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  // Variables de control de UI
  bool _showLogs = true; // Cambiado a true para que esté visible por defecto
  bool _showDataReceived = false;
  bool _showAdvancedOptions = false;
  bool _hasWrittenToNFC = false;
  String _logFilter = 'ALL'; // ALL, ERROR, WARNING, INFO
  bool _logsExpanded = false; // Para expandir/contraer logs

  // Constantes para los tipos de acción
  static const Map<String, String> ActionType = {
    'READ': 'READ',
    'CREATE': 'CREATE',
    'ASSIGN_ACCOUNT': 'ASSIGN_ACCOUNT',
    'UPDATE_STATUS': 'UPDATE_STATUS',
  };

  // Método para agregar logs
  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';

    setState(() {
      _logs.add(logMessage);
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });

    if (_showLogs) {
      debugPrint(logMessage);
    }

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

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
    _addLog('Logs limpiados');
  }

  void _copyLogs() {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay logs para copiar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final logsText = _logs.join('\n');
    Clipboard.setData(ClipboardData(text: logsText));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiados al portapapeles'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _exportLogs() {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay logs para exportar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final timestamp = DateTime.now().toString().replaceAll(':', '-').substring(0, 19);
    final logsText = _logs.join('\n');
    final exportData = '''
=== FOQQUS CASHLESS LOGS ===
Fecha: ${DateTime.now().toString()}
Session ID: $sessionId
Client ID: $clientId
Acción: $accion
Tipo: $type

=== LOGS ===
$logsText
''';

    Clipboard.setData(ClipboardData(text: exportData));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logs exportados al portapapeles (${_logs.length} entradas)'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Copiar',
          textColor: Colors.white,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: exportData));
          },
        ),
      ),
    );
  }

  List<String> _getFilteredLogs() {
    if (_logFilter == 'ALL') return _logs;
    
    return _logs.where((log) {
      switch (_logFilter) {
        case 'ERROR':
          return log.contains('ERROR');
        case 'WARNING':
          return log.contains('ADVERTENCIA');
        case 'INFO':
          return !log.contains('ERROR') && !log.contains('ADVERTENCIA');
        default:
          return true;
      }
    }).toList();
  }

  void _setLogFilter(String filter) {
    setState(() {
      _logFilter = filter;
    });
  }

  void _toggleLogsExpanded() {
    setState(() {
      _logsExpanded = !_logsExpanded;
    });
  }

  double _getResponsiveFontSize(double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final isLandscape = screenWidth > screenHeight;
    
    if (isTablet) {
      return baseSize * 0.8;
    } else if (isLandscape) {
      return baseSize * 0.9;
    } else {
      return baseSize;
    }
  }

  double _getResponsiveSpacing(double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return isTablet ? baseSpacing * 1.2 : baseSpacing;
  }

  List<Widget> _buildLogActionButtons() {
    final iconSize = _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.035);
    final spacing = _getResponsiveSpacing(MediaQuery.of(context).size.width * 0.01);

    return [
      // Botón expandir/contraer
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF6C757D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(
            _logsExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            color: const Color(0xFFE9ECEF),
            size: iconSize,
          ),
          onPressed: _toggleLogsExpanded,
          tooltip: _logsExpanded ? 'Contraer logs' : 'Expandir logs',
        ),
      ),
      
      SizedBox(width: spacing),
      
      // Botón copiar
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF6C757D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(Icons.copy, color: const Color(0xFFE9ECEF), size: iconSize),
          onPressed: _copyLogs,
          tooltip: 'Copiar logs',
        ),
      ),
      
      SizedBox(width: spacing),
      
      // Botón exportar
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF6C757D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(Icons.download, color: const Color(0xFFE9ECEF), size: iconSize),
          onPressed: _exportLogs,
          tooltip: 'Exportar logs',
        ),
      ),
      
      SizedBox(width: spacing),
      
      // Botón limpiar
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF6C757D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(Icons.clear, color: const Color(0xFFE9ECEF), size: iconSize),
          onPressed: _clearLogs,
          tooltip: 'Limpiar logs',
        ),
      ),
    ];
  }

  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
    });
    _addLog('Logs ${_showLogs ? 'activados' : 'desactivados'}');
  }

  void _toggleDataReceived() {
    setState(() {
      _showDataReceived = !_showDataReceived;
    });
  }

  void _toggleAdvancedOptions() {
    setState(() {
      _showAdvancedOptions = !_showAdvancedOptions;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addLog('NFCScreen inicializado');
    _initializeChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
      } else {
        _addLog('No se recibió resultado del intent inicial');
      }
    } on PlatformException catch (e) {
      _addLog('Error processing initial intent: ${e.message}');
    } catch (e) {
      _addLog('Error general: $e');
    }
  }

  Future<void> _handleIntentData(Map<String, dynamic> data) async {
    _addLog('Datos recibidos en _handleIntentData: $data');

    final dynamic rawData = data['data'];
    if (rawData == null) {
      _addLog('No se encontró el objeto data en la respuesta');
      return;
    }

    final Map<String, dynamic> responseData =
        Map<String, dynamic>.from(rawData);

    final accion = responseData['accion'] as String? ?? '';
    final timestamp = responseData['timestamp'] as String? ?? '';
    final sessionId = responseData['sessionId'] as String? ?? '';
    final clientId = responseData['clientId'] as String? ?? '';
    final type = responseData['type'] as String? ?? '';

    _addLog(
        'Parámetros procesados - accion: $accion, timestamp: $timestamp, sessionId: $sessionId, type: $type');

    setState(() {
      this.accion = accion;
      this.timestamp = timestamp;
      this.sessionId = sessionId;
      this.clientId = clientId;
      this.type = type;
    });
    
    // Verificar que los datos se establecieron correctamente
    _addLog('Verificación después de setState:');
    _addLog('- sessionId: ${this.sessionId}');
    _addLog('- type: ${this.type}');
    _addLog('- accion: ${this.accion}');

    _addLog('Datos actualizados en el estado');
    _addLog('sessionId después de setState: $sessionId');
    _addLog('type después de setState: $type');

    // Mostrar mensaje informativo según la acción
    _addLog('Comparando acción: "${accion.toUpperCase()}" con "${ActionType['READ']}"');
    
    if (accion.toUpperCase() == ActionType['READ'] || accion.toUpperCase() == 'READWRISTBAND') {
      _addLog('Acción READ detectada - Iniciando lectura NFC automáticamente');
      
      // Establecer estado de lectura automáticamente
      setState(() {
        isReading = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leyendo NFC...'),
          backgroundColor: Colors.blue,
        ),
      );
      
      // Iniciar lectura NFC automáticamente después de un breve delay
      if (mounted) {
        _addLog('Llamando a _startNFCReading automáticamente...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _startNFCReading();
      }
    } else if (accion.toUpperCase() == ActionType['CREATE']) {
      _addLog('Acción CREATE detectada - Presiona "Escribir en NFC" para escribir el clientId');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Acción CREATE detectada. Presiona "Escribir en NFC" para escribir el clientId: $clientId'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _acceptAction() async {
    _addLog('=== _acceptAction iniciado ===');
    _addLog('sessionId: $sessionId');
    _addLog('type: $type');
    _addLog('nfcData actual: $nfcData');

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
      final dataToSend = nfcData ?? '';
      await _sendDataToBackend(dataToSend, type: type);
      _addLog('Datos guardados exitosamente en Firebase');

      _addLog('Retornando a web...');
      await _returnToWeb();
      _addLog('Retorno a web completado');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Acción completada exitosamente${nfcData != null ? ' - Serial: $nfcData' : ''}'),
          backgroundColor: Colors.green,
        ),
      );
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
    _addLog('=== _startNFCReading iniciado ===');
    _addLog('sessionId actual: $sessionId');
    _addLog('type actual: $type');
    _addLog('isReading actual: $isReading');
    
    if (sessionId == null) {
      _addLog('ERROR: sessionId es nulo');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId')),
      );
      return;
    }

    _addLog('Iniciando lectura NFC...');
    _addLog('sessionId: $sessionId');
    _addLog('useRealNFC: $_useRealNFC');
    setState(() => isReading = true);

    try {
      if (_useRealNFC) {
        _addLog('Leyendo serial NFC con NFCService...');
        try {
          final String? serial = await NFCService.readNFCTag();
          if (serial == null) {
            _addLog('ERROR: NFCService retornó null');
            throw Exception('No se pudo obtener el serial del tag');
          }
          _addLog('Serial NFC leído: $serial');
          await _processNFCData(serial);

          // Para acción READ, retornar automáticamente a la web después de leer
          if (type?.toUpperCase() == 'READ') {
            _addLog('Lectura READ completada, retornando automáticamente a web');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Lectura exitosa. Regresando a Foqqus...'),
                  backgroundColor: Colors.green,
                ),
              );
              await Future.delayed(const Duration(seconds: 2));
              await _returnToWeb();
            }
          }
        } on PlatformException catch (e) {
          _addLog('ERROR de plataforma al leer NFC: ${e.message}');
          _addLog('Código de error: ${e.code}');
          if (e.code == 'TIMEOUT') {
            // Mostrar popup con opciones
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    backgroundColor: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(18),
                            child: const Icon(
                              Icons.nfc,
                              color: Color(0xFF007AFF),
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No se pudo leer la manilla',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '¿Quieres volver a Foqqus o intentar la lectura nuevamente?',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF6C757D),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _returnToWeb();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE9ECEF),
                                    foregroundColor: const Color(0xFF1A1A1A),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: const Text(
                                    'Volver a Foqqus',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _startNFCReading();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF007AFF),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: const Text(
                                    'Reintentar',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error NFC: ${e.message}')),
            );
          }
        }
      } else {
        _addLog('Usando NFC simulado...');
        await Future.delayed(const Duration(seconds: 2));
        const simulatedData = 'CASH1234';
        _addLog('Datos simulados: $simulatedData');
        await _processNFCData(simulatedData);
        
        // Para acción READ, retornar automáticamente a la web después de leer
        if (type?.toUpperCase() == 'READ') {
          _addLog('Lectura READ completada (simulada), retornando automáticamente a web');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Lectura exitosa. Regresando a Foqqus...'),
                backgroundColor: Colors.green,
              ),
            );
            await Future.delayed(const Duration(seconds: 2));
            await _returnToWeb();
          }
        }
      }
    } catch (e) {
      _addLog('ERROR general en _startNFCReading: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _addLog('Finalizando _startNFCReading');
      setState(() => isReading = false);
      if (_useRealNFC) {
        try {
          NfcManager.instance.stopSession();
          _addLog('Sesión NFC detenida');
        } catch (_) {
          _addLog('Sesión NFC ya estaba detenida');
        }
      }
    }
  }

  Future<void> _writeToNFC() async {
    _addLog('=== _writeToNFC iniciado ===');
    if (sessionId == null || clientId == null) {
      _addLog('ERROR: sessionId o clientId son nulos');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId o clientId')),
      );
      return;
    }

    _addLog('Iniciando escritura NFC...');
    _addLog('sessionId: $sessionId');
    _addLog('clientId a escribir: $clientId');
    _addLog('useRealNFC: $_useRealNFC');
    setState(() => isReading = true);

    try {
      if (_useRealNFC) {
        _addLog('Escribiendo clientId en NFC con NFCService...');
        try {
          final bool writeSuccess = await NFCService.writeToNFCTag(clientId!);
          if (!writeSuccess) {
            _addLog('ERROR: NFCService retornó false');
            throw Exception('No se pudo escribir en el tag NFC');
          }
          _addLog('ClientId escrito exitosamente en NFC: $clientId');
          setState(() => _hasWrittenToNFC = true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ClientId escrito exitosamente en NFC: $clientId'),
              backgroundColor: Colors.green,
            ),
          );
        } on PlatformException catch (e) {
          _addLog('ERROR de plataforma al escribir NFC: ${e.message}');
          _addLog('Código de error: ${e.code}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error NFC: ${e.message}')),
          );
        }
      } else {
        _addLog('Usando NFC simulado para escritura...');
        await Future.delayed(const Duration(seconds: 2));
        _addLog('ClientId simulado escrito: $clientId');
        setState(() => _hasWrittenToNFC = true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ClientId simulado escrito exitosamente: $clientId'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _addLog('ERROR general en _writeToNFC: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _addLog('Finalizando _writeToNFC');
      setState(() => isReading = false);
      if (_useRealNFC) {
        try {
          NfcManager.instance.stopSession();
          _addLog('Sesión NFC detenida');
        } catch (_) {
          _addLog('Sesión NFC ya estaba detenida');
        }
      }
    }
  }

  Future<void> _processNFCData(String data) async {
    _addLog('=== _processNFCData iniciado ===');
    _addLog('Datos NFC recibidos: $data');
    setState(() => nfcData = data);
    _addLog('Estado actualizado con nfcData: $nfcData');
    await _sendDataToBackend(data, type: type);
    _addLog('Datos enviados a Firebase exitosamente');
    _addLog('=== _processNFCData completado ===');
  }

  Future<void> _verifyNFCWrite() async {
    _addLog('=== _verifyNFCWrite iniciado ===');
    if (sessionId == null || clientId == null) {
      _addLog('ERROR: sessionId o clientId son nulos');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId o clientId')),
      );
      return;
    }

    if (!_hasWrittenToNFC) {
      _addLog('ERROR: No se ha escrito en NFC aún');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debes escribir en NFC')),
      );
      return;
    }

    _addLog('Verificando escritura NFC...');
    _addLog('sessionId: $sessionId');
    _addLog('clientId esperado: $clientId');
    setState(() => isReading = true);

    try {
      if (_useRealNFC) {
        _addLog('Leyendo contenido NFC para verificar escritura...');
        try {
          final String? readData = await NFCService.readNFCTagContent();
          if (readData == null) {
            _addLog('ERROR: No se pudo leer el contenido del tag NFC');
            throw Exception('No se pudo leer el contenido del tag NFC');
          }
          
          _addLog('Datos leídos del NFC: "$readData"');
          _addLog('ClientId esperado: "$clientId"');
          _addLog('Longitud datos leídos: ${readData.length}');
          _addLog('Longitud clientId esperado: ${clientId!.length}');
          _addLog('¿Son iguales?: ${readData == clientId}');
          
          bool exactMatch = readData == clientId;
          bool flexibleMatch = readData.trim() == clientId!.trim();
          
          _addLog('Comparación exacta: $exactMatch');
          _addLog('Comparación flexible: $flexibleMatch');
          
          if (exactMatch || flexibleMatch) {
            _addLog('¡ÉXITO! Los datos coinciden');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('¡ÉXITO! ClientId verificado: $clientId'),
                backgroundColor: Colors.green,
              ),
            );
            
            if (type?.toUpperCase() == 'CREATE') {
              _addLog('Almacenando en Firebase que se guardó el clientId: $clientId');
              await _sendDataToBackend(clientId!, type: type, isCreateAction: true);
            } else {
              await _sendDataToBackend(clientId!, type: type);
            }
            
            await _returnToWeb();
          } else {
            _addLog('ERROR: Los datos no coinciden');
            _addLog('Datos leídos (hex): ${readData.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(' ')}');
            _addLog('ClientId esperado (hex): ${clientId!.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(' ')}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ERROR: Datos no coinciden. Esperado: "$clientId", Leído: "$readData"'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } on PlatformException catch (e) {
          _addLog('ERROR de plataforma al verificar NFC: ${e.message}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error NFC: ${e.message}')),
          );
        }
      } else {
        _addLog('Usando NFC simulado para verificación...');
        await Future.delayed(const Duration(seconds: 2));
        _addLog('Verificación simulado exitosa: $clientId');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡ÉXITO! ClientId verificado (simulado): $clientId'),
            backgroundColor: Colors.green,
          ),
        );
        
        if (type?.toUpperCase() == 'CREATE') {
          _addLog('Almacenando en Firebase que se guardó el clientId (simulado): $clientId');
          await _sendDataToBackend(clientId!, type: type, isCreateAction: true);
        } else {
          await _sendDataToBackend(clientId!, type: type);
        }
        
        await _returnToWeb();
      }
    } catch (e) {
      _addLog('ERROR general en _verifyNFCWrite: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      _addLog('Finalizando _verifyNFCWrite');
      setState(() => isReading = false);
      if (_useRealNFC) {
        try {
          NfcManager.instance.stopSession();
          _addLog('Sesión NFC detenida');
        } catch (_) {
          _addLog('Sesión NFC ya estaba detenida');
        }
      }
    }
  }

  Future<void> _sendDataToBackend(String data,
      {bool isError = false, String? type, bool isCreateAction = false}) async {
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

      final existingDoc = await firestore.collection('nfcReader').doc(sessionId).get();
      if (existingDoc.exists) {
        _addLog('Documento existente encontrado, procederemos a fusionar datos');
        _addLog('Datos actuales del documento: ${existingDoc.data()}');
      } else {
        _addLog('Documento no existe, se creará uno nuevo');
      }

      final updateData = <String, dynamic>{
        'status': isError ? 'failed' : 'completed',
        'type': type ?? 'READ',
        'updatedAt': FieldValue.serverTimestamp(),
        'actionCompleted': true,
        'completedAt': FieldValue.serverTimestamp(),
      };

      if (!isError) {
        if (data.isNotEmpty) {
          updateData['serial'] = data;
        }
        updateData['actionResult'] = 'success';
        
        if (isCreateAction) {
          updateData['clientIdWritten'] = data;
          updateData['createAction'] = true;
          updateData['message'] = 'ClientId escrito exitosamente en manilla NFC';
          _addLog('Datos específicos de CREATE agregados: clientIdWritten=$data');
        }
      } else {
        updateData['actionResult'] = 'failed';
        updateData['errorMessage'] = 'Acción cancelada por el usuario';
      }
      
      _addLog('Datos de actualización: $updateData');
      _addLog('Actualizando documento: $sessionId');

      await firestore
          .collection('nfcReader')
          .doc(sessionId)
          .set(updateData, SetOptions(merge: true));
      
      _addLog('Documento actualizado exitosamente en Firestore');
      _addLog('Documento ID: $sessionId');
      _addLog('Colección: nfcReader');
      
      final updatedDoc = await firestore.collection('nfcReader').doc(sessionId).get();
      if (updatedDoc.exists) {
        _addLog('Documento verificado - actualización exitosa');
        _addLog('Datos actualizados del documento: ${updatedDoc.data()}');
      } else {
        _addLog('ADVERTENCIA: Documento no encontrado después de actualizar');
      }
      
    } catch (e) {
      _addLog('ERROR en _sendDataToBackend: $e');
      _addLog('Stack trace: ${StackTrace.current}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar datos en Firestore: $e')),
      );
      rethrow;
    }
  }

  Future<void> _simulateError() async {
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró sessionId')),
      );
      return;
    }

    setState(() => isReading = true);

    try {
      await Future.delayed(const Duration(seconds: 2));
      await _sendDataToBackend('', isError: true);
      await _returnToWeb();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isReading = false);
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
      rethrow;
    }
  }

  Future<void> _testFirebaseConnection() async {
    _addLog('=== Probando conexión a Firebase ===');
    try {
      final firestore = FirebaseFirestore.instance;
      _addLog('Firestore instance obtenida');
      
      final testDocId = 'test_connection_${DateTime.now().millisecondsSinceEpoch}';
      final testData = {
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'Prueba de conexión Firebase',
        'sessionId': testDocId,
      };
      
      _addLog('Creando documento de prueba: $testDocId');
      await firestore.collection('nfcReader').doc(testDocId).set(testData);
      _addLog('Documento de prueba creado exitosamente');
      
      final docSnapshot =
          await firestore.collection('nfcReader').doc(testDocId).get();
      if (docSnapshot.exists) {
        _addLog(
            'Documento de prueba verificado - Firebase funciona correctamente');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase funciona correctamente')),
        );
        
        Future.delayed(const Duration(seconds: 5), () async {
          await firestore.collection('nfcReader').doc(testDocId).delete();
          _addLog('Documento de prueba eliminado');
        });
      } else {
        _addLog('ERROR: Documento de prueba no encontrado');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: Documento no encontrado en Firebase')),
        );
      }
      
    } catch (e) {
      _addLog('ERROR en prueba de Firebase: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión Firebase: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/foqqus.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Foqqus Pay v.1.2',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF007AFF),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                _showAdvancedOptions ? Icons.settings : Icons.more_horiz,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _toggleAdvancedOptions,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
          ),
        ),
        child: Column(
          children: [
            // Estado principal - Interfaz limpia como datáfono
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icono NFC principal con diseño mejorado
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF007AFF).withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        child: Icon(
                          Icons.nfc,
                          size: 64,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Título de estado con diseño mejorado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _getStatusTitle(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Descripción con diseño mejorado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusDescription(),
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF6C757D),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Botones principales según el tipo de acción
                    if (type?.toUpperCase() == 'READ' || accion?.toUpperCase() == 'READWRISTBAND') ...[
                      // El botón se presiona automáticamente, no se muestra al usuario
                      if (isReading) ...[
                        _buildMainButton(
                          'Leyendo NFC...',
                          Icons.nfc,
                          const Color(0xFF007AFF),
                          null,
                          'Leyendo...',
                        ),
                      ],
                    ] else if (type?.toUpperCase() == 'CREATE') ...[
                      _buildMainButton(
                        'Escribir en NFC',
                        Icons.edit,
                        const Color(0xFFFF9500),
                        isReading ? null : _writeToNFC,
                        isReading ? 'Escribiendo...' : 'Escribir en NFC',
                      ),
                      
                      if (_hasWrittenToNFC) ...[
                        const SizedBox(height: 16),
                        _buildMainButton(
                          'Verificar Escritura',
                          Icons.check_circle,
                          const Color(0xFF34C759),
                          isReading ? null : _verifyNFCWrite,
                          isReading ? 'Verificando...' : 'Verificar Escritura',
                        ),
                      ],
                    ],
                    
                    // Indicador de escritura exitosa con diseño mejorado
                    if (_hasWrittenToNFC) ...[
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF34C759).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'ClientId escrito: $clientId',
                              style: const TextStyle(
                                color: Color(0xFF34C759),
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          
          // Panel de opciones avanzadas (oculto por defecto)
          if (_showAdvancedOptions) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF000000),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                    blurStyle: BlurStyle.outer,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle indicador
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Opciones Avanzadas',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF6C757D)),
                          onPressed: _toggleAdvancedOptions,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Botones de opciones avanzadas
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildOptionButton(
                        'Ver Datos',
                        Icons.info_outline,
                        _toggleDataReceived,
                      ),
                      _buildOptionButton(
                        'Ocultar Logs',
                        Icons.visibility_off,
                        _toggleLogs,
                      ),
                      _buildOptionButton(
                        'Probar Firebase',
                        Icons.cloud_outlined,
                        _testFirebaseConnection,
                      ),
                      _buildOptionButton(
                        'Simular Error',
                        Icons.error_outline,
                        _simulateError,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
          // Panel de datos recibidos (oculto por defecto)
          if (_showDataReceived) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F8FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF007AFF),
                    blurRadius: 15,
                    offset: Offset(0, -3),
                    blurStyle: BlurStyle.outer,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle indicador
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Datos Recibidos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF007AFF)),
                          onPressed: _toggleDataReceived,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF007AFF).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildDataRow('Acción:', accion ?? 'No recibido'),
                        _buildDataRow('Timestamp:', timestamp ?? 'No recibido'),
                        _buildDataRow('Session ID:', sessionId ?? 'No recibido'),
                        _buildDataRow('Client ID:', clientId ?? 'No recibido'),
                        _buildDataRow('Tipo:', type ?? 'No recibido'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          

          
          // Panel de logs siempre visible en la parte inferior
          if (_showLogs) ...[
            Container(
              height: _logsExpanded 
                  ? MediaQuery.of(context).size.height * 0.4 
                  : MediaQuery.of(context).size.height * 0.12,
              constraints: BoxConstraints(
                minHeight: _logsExpanded ? 200 : 60,
                maxHeight: _logsExpanded ? MediaQuery.of(context).size.height * 0.6 : 100,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF000000),
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header de logs con controles
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.04,
                      vertical: MediaQuery.of(context).size.height * 0.015,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Información de logs
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.015),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.list_alt,
                                  color: Colors.white,
                                  size: MediaQuery.of(context).size.width * 0.04,
                                ),
                              ),
                              SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Logs de Debug',
                                      style: TextStyle(
                                        fontSize: _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.035),
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFFE9ECEF),
                                      ),
                                    ),
                                    Text(
                                      '${_logs.length} entradas',
                                      style: TextStyle(
                                        fontSize: _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.025),
                                        color: const Color(0xFF6C757D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Controles de logs
                        Expanded(
                          flex: 3,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Filtro rápido
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: MediaQuery.of(context).size.width * 0.02,
                                  vertical: MediaQuery.of(context).size.height * 0.01,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButton<String>(
                                  value: _logFilter,
                                  dropdownColor: const Color(0xFF2A2A2A),
                                  style: TextStyle(
                                    color: const Color(0xFFE9ECEF),
                                    fontSize: _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.03),
                                  ),
                                  underline: Container(),
                                  items: const [
                                    DropdownMenuItem(value: 'ALL', child: Text('TODOS')),
                                    DropdownMenuItem(value: 'ERROR', child: Text('ERROR')),
                                    DropdownMenuItem(value: 'WARNING', child: Text('WARN')),
                                    DropdownMenuItem(value: 'INFO', child: Text('INFO')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) _setLogFilter(value);
                                  },
                                ),
                              ),
                              
                              SizedBox(width: MediaQuery.of(context).size.width * 0.02),
                              
                              // Botones de acción
                              ..._buildLogActionButtons(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Contenido de logs (solo visible cuando está expandido)
                  if (_logsExpanded) ...[
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.04,
                        ),
                        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
                        decoration: BoxDecoration(
                          color: const Color(0xFF000000),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF6C757D).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: _getFilteredLogs().isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: const Color(0xFF6C757D),
                                      size: MediaQuery.of(context).size.width * 0.08,
                                    ),
                                    SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                                    Text(
                                      _logs.isEmpty ? 'No hay logs aún...' : 'No hay logs con el filtro seleccionado',
                                      style: TextStyle(
                                        color: const Color(0xFF6C757D),
                                        fontStyle: FontStyle.italic,
                                        fontSize: _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.03),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _logScrollController,
                                itemCount: _getFilteredLogs().length,
                                itemBuilder: (context, index) {
                                  final log = _getFilteredLogs()[index];
                                  final isError = log.contains('ERROR');
                                  final isWarning = log.contains('ADVERTENCIA');

                                  return Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: MediaQuery.of(context).size.height * 0.002,
                                    ),
                                    child: Text(
                                      log,
                                      style: TextStyle(
                                        color: isError
                                            ? const Color(0xFFFF6B6B)
                                            : isWarning
                                                ? const Color(0xFFFFB74D)
                                                : const Color(0xFF4CAF50),
                                        fontSize: _getResponsiveFontSize(MediaQuery.of(context).size.width * 0.025),
                                        fontFamily: 'SF Mono',
                                        height: 1.3,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ));
  }

  Widget _buildMainButton(String text, IconData icon, Color color, VoidCallback? onPressed, String loadingText) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          shadowColor: color.withOpacity(0.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Text(
              onPressed == null ? loadingText : text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(String text, IconData icon, VoidCallback onPressed) {
    return Container(
      width: 140,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF6C757D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          shadowColor: Colors.black.withOpacity(0.1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF007AFF)),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF6C757D),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusTitle() {
    if (type?.toUpperCase() == 'READ' || accion?.toUpperCase() == 'READWRISTBAND') {
      return 'Lectura NFC';
    } else if (type?.toUpperCase() == 'CREATE') {
      return 'Configuración NFC';
    } else {
      return 'Esperando Acción';
    }
  }

  Widget _buildFilterChip(String label, String filter) {
    final isSelected = _logFilter == filter;
    return GestureDetector(
      onTap: () => _setLogFilter(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFF007AFF) 
              : const Color(0xFF6C757D).withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFFE9ECEF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _getStatusDescription() {
    if (type?.toUpperCase() == 'READ' || accion?.toUpperCase() == 'READWRISTBAND') {
      if (isReading) {
        return 'Leyendo manilla NFC... Acerca el dispositivo';
      } else {
        return 'Preparando lectura automática...';
      }
    } else if (type?.toUpperCase() == 'CREATE') {
      if (_hasWrittenToNFC) {
        return 'ClientId escrito exitosamente. Verifica la escritura';
      } else {
        return 'Escribe el ClientId en la manilla NFC';
      }
    } else {
      return 'Esperando instrucciones del sistema';
    }
  }
}


