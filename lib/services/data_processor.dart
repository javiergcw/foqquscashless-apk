import 'package:flutter/services.dart';
import '../services/manilla_service.dart';

class DataProcessor {
  final ManillaService _manillaService = ManillaService();
  final MethodChannel _platform =
      const MethodChannel('com.example.foqquscashless/app');

  Future<Map<String, dynamic>> handleReadWristband(
      String? clientId) async {
    try {
      print('Iniciando handleReadWristband con clientId: $clientId');

      if (clientId == null || clientId.isEmpty) {
        throw Exception('El clientId no puede estar vacío');
      }

      // Solo procesar los datos recibidos, sin simular lectura NFC
      return {
        'clientId': clientId,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error en handleReadWristband: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> simularLecturaNFC(String? clientId) async {
    try {
      if (clientId == null || clientId.isEmpty) {
        throw Exception('El clientId no puede estar vacío para simular lectura NFC');
      }

      const CASHLESSID = 'CASH1234';
      print('Simulando lectura NFC con token: $CASHLESSID');

      final manilla = await _manillaService.getManillaByToken(
          clientId: clientId, token: CASHLESSID);
      if (manilla == null) {
        throw Exception('No se encontró la manilla en el sistema');
      }
      print('Manilla encontrada: ${manilla.toJson()}');

      return {
        'cashlessId': manilla.cashlessId,
        'clientId': clientId,
        'token': manilla.token,
        "cuentaId": manilla.cuentaId,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error al simular lectura NFC DATA PROCESSOR: $e');
      rethrow;
    }
  }
}
