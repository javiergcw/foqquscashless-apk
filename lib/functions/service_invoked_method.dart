import 'package:flutter/services.dart';
import 'package:foqquscashless/services/data_processor.dart';

class ServiceInvokedMethod {
  final MethodChannel _platform =
      const MethodChannel('com.example.foqquscashless/app');
  final DataProcessor _dataProcessor = DataProcessor();
  bool _isChannelReady = false;
  String? _storedClientId;

  Future<void> initializeChannel() async {
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
    
    final accion = data['accion'] as String?;
    final clientId = data['clientId'] as String?;
    final timestamp = data['timestamp'] as String?;

    print('Parámetros procesados - accion: $accion, clientId: $clientId, timestamp: $timestamp');

    if (accion != null && accion.isNotEmpty) {
      try {
        switch (accion) {
          case 'ReadWristband':
            if (clientId == null || clientId.isEmpty) {
              throw Exception('El clientId es requerido para ReadWristband');
            }
            _storedClientId = clientId;
            print('ClientId almacenado: $clientId');
            break;
          default:
            print('Acción no reconocida: $accion');
        }
      } catch (e) {
        print('Error al procesar la acción $accion: $e');
      }
    } else {
      print('La acción está vacía o es nula');
    }
  }

  Future<void> returnToWeb() async {
    try {
      print('Volviendo al navegador...');
      await _platform.invokeMethod('returnToWeb');
    } catch (e) {
      print('Error al volver al navegador: $e');
    }
  }

  Future<void> simularLecturaNFC(String? clientId) async {
    try {
      final clientIdToUse = clientId ?? _storedClientId;
      if (clientIdToUse == null) {
        throw Exception('No hay un clientId disponible para simular lectura NFC');
      }
      final result = await _dataProcessor.simularLecturaNFC(clientIdToUse);
      
      // Enviar los datos a la web
      final dataToSend = {
        'accion': 'ReadWristband',
        'cashlessId': result['cashlessId'],
        'cuentaId': result['cuentaId'],
        'status': result['status'],
        'token': result['token'],
        'timestamp': result['timestamp']
      };
      
      await _platform.invokeMethod('sendDataToWeb', dataToSend);
      
      // Finalizar la actividad
      await returnToWeb();
    } catch (e) {
      print('Error al simular lectura NFC SERVICE INVOKED: $e');
      rethrow;
    }
  }
}
