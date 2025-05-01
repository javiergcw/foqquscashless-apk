import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NFCService {
  static Future<String?> readNFCTag() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      throw PlatformException(
        code: 'NO_NFC',
        message: 'NFC no está disponible en este dispositivo',
      );
    }

    try {
      String? tagId;

      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          // Intentar obtener ID en diferentes formatos
          final identifierBytes =
              tag.data['nfca']?['identifier'] as List<int>? ??
                  tag.data['nfcb']?['identifier'] as List<int>? ??
                  tag.data['nfcf']?['identifier'] as List<int>? ??
                  tag.data['nfcv']?['identifier'] as List<int>?;

          if (identifierBytes != null) {
            tagId = _byteArrayToHexString(identifierBytes);
          }

          // Detener la sesión después de leer
          await NfcManager.instance.stopSession();
        },
      );

      // Esperar hasta que se lea un tag o se agote el tiempo
      int attempts = 0;
      while (tagId == null && attempts < 100) {
        // 10 segundos máximo
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (tagId == null) {
        throw PlatformException(
          code: 'TIMEOUT',
          message: 'Tiempo de espera agotado para leer NFC',
        );
      }

      return tagId;
    } catch (e) {
      if (e is PlatformException) {
        rethrow;
      }
      throw PlatformException(
        code: 'NFC_ERROR',
        message: 'Error al leer NFC: ${e.toString()}',
      );
    }
  }

  static String _byteArrayToHexString(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}
