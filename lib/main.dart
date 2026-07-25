import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foqquscashless/services/nfc_service.dart';
import 'package:foqquscashless/theme/foqqus_colors.dart';
import 'package:foqquscashless/utils/keys.dart';
import 'package:nfc_manager/nfc_manager.dart';

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: FoqqusColors.blue,
          primary: FoqqusColors.blue,
          secondary: FoqqusColors.teal,
          surface: FoqqusColors.surface,
        ),
        scaffoldBackgroundColor: FoqqusColors.canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          foregroundColor: FoqqusColors.ink,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoqqusColors.ink,
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

class _NFCScreenState extends State<NFCScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  bool _showDataReceived = false;
  bool _showAdvancedOptions = false;
  bool _hasWrittenToNFC = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const Map<String, String> ActionType = {
    'READ': 'READ',
    'CREATE': 'CREATE',
    'ASSIGN_ACCOUNT': 'ASSIGN_ACCOUNT',
    'UPDATE_STATUS': 'UPDATE_STATUS',
  };

  void _addLog(String message) {
    final stamp = DateTime.now().toString().substring(11, 19);
    debugPrint('[$stamp] $message');
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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
    _pulseController.dispose();
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
    final isRead = type?.toUpperCase() == 'READ' ||
        accion?.toUpperCase() == 'READWRISTBAND';
    final isCreate = type?.toUpperCase() == 'CREATE';
    final accent = isCreate ? FoqqusColors.orange : FoqqusColors.blue;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8F4FC),
              FoqqusColors.canvas,
              Color(0xFFD9F3F0),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(child: _buildBrandHeader()),
                    IconButton(
                      onPressed: _toggleAdvancedOptions,
                      icon: Icon(
                        _showAdvancedOptions
                            ? Icons.close_rounded
                            : Icons.more_horiz_rounded,
                        color: FoqqusColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: _buildHeroOrb(accent),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        _getStatusTitle(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: FoqqusColors.ink,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getStatusDescription(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: FoqqusColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (isRead && isReading)
                        _buildMainButton(
                          'Leyendo NFC...',
                          Icons.nfc_rounded,
                          FoqqusColors.blue,
                          null,
                          'Leyendo...',
                        ),
                      if (isCreate) ...[
                        _buildMainButton(
                          'Escribir en NFC',
                          Icons.edit_rounded,
                          FoqqusColors.orange,
                          isReading ? null : _writeToNFC,
                          isReading ? 'Escribiendo...' : 'Escribir en NFC',
                        ),
                        if (_hasWrittenToNFC) ...[
                          const SizedBox(height: 12),
                          _buildMainButton(
                            'Verificar Escritura',
                            Icons.verified_rounded,
                            FoqqusColors.success,
                            isReading ? null : _verifyNFCWrite,
                            isReading
                                ? 'Verificando...'
                                : 'Verificar Escritura',
                          ),
                        ],
                      ],
                      if (_hasWrittenToNFC) ...[
                        const SizedBox(height: 20),
                        _buildSuccessChip('ClientId escrito: $clientId'),
                      ],
                      const Spacer(flex: 3),
                      Text(
                        isReading
                            ? 'Mantén la manilla cerca del lector'
                            : 'Listo para recibir instrucciones',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 0.2,
                          color: FoqqusColors.inkMuted.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (_showAdvancedOptions) _buildAdvancedSheet(),
              if (_showDataReceived) _buildDataSheet(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/foqqus_cashless_icon.png',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Foqqus Cashless',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: FoqqusColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroOrb(Color accent) {
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 124,
          height: 124,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: FoqqusColors.surface,
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            isReading ? Icons.contactless_rounded : Icons.nfc_rounded,
            size: 56,
            color: accent,
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FoqqusColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: FoqqusColors.success.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: FoqqusColors.success, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: FoqqusColors.success,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSheet() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: FoqqusColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A0F1B2D),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FoqqusColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Opciones',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FoqqusColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOptionButton(
                  'Ver Datos',
                  Icons.info_outline_rounded,
                  _toggleDataReceived,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOptionButton(
                  'Probar Firebase',
                  Icons.cloud_outlined,
                  _testFirebaseConnection,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOptionButton(
                  'Simular Error',
                  Icons.error_outline_rounded,
                  _simulateError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataSheet() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: FoqqusColors.blue.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Datos recibidos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FoqqusColors.blueDeep,
                  ),
                ),
              ),
              IconButton(
                onPressed: _toggleDataReceived,
                icon: const Icon(Icons.close_rounded, color: FoqqusColors.blue),
              ),
            ],
          ),
          _buildDataRow('Acción:', accion ?? 'No recibido'),
          _buildDataRow('Timestamp:', timestamp ?? 'No recibido'),
          _buildDataRow('Session ID:', sessionId ?? 'No recibido'),
          _buildDataRow('Client ID:', clientId ?? 'No recibido'),
          _buildDataRow('Tipo:', type ?? 'No recibido'),
        ],
      ),
    );
  }

  Widget _buildMainButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback? onPressed,
    String loadingText,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Text(
              onPressed == null ? loadingText : text,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(String text, IconData icon, VoidCallback onPressed) {
    return Material(
      color: FoqqusColors.canvas,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: FoqqusColors.blue, size: 22),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FoqqusColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: FoqqusColors.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: FoqqusColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusTitle() {
    if (type?.toUpperCase() == 'READ' ||
        accion?.toUpperCase() == 'READWRISTBAND') {
      return 'Lectura NFC';
    } else if (type?.toUpperCase() == 'CREATE') {
      return 'Configuración NFC';
    } else {
      return 'Esperando Acción';
    }
  }

  String _getStatusDescription() {
    if (type?.toUpperCase() == 'READ' ||
        accion?.toUpperCase() == 'READWRISTBAND') {
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

