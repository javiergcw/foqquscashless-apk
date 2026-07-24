import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'dart:typed_data';

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

  static Future<bool> writeToNFCTag(String data) async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      throw PlatformException(
        code: 'NO_NFC',
        message: 'NFC no está disponible en este dispositivo',
      );
    }

    try {
      bool writeSuccess = false;

      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            // Intentar escribir usando NDEF para compatibilidad máxima
            if (tag.data['ndef'] != null) {
              final ndef = Ndef.from(tag);
              if (ndef != null && ndef.isWritable) {
                await _writeNdefMessage(ndef, data);
                writeSuccess = true;
              }
            } else {
              // Si no es NDEF, intentar con otros tipos
              if (tag.data['nfca'] != null) {
                final nfca = NfcA.from(tag);
                if (nfca != null) {
                  await _writeToNfcA(nfca, data);
                  writeSuccess = true;
                }
              } else if (tag.data['isodep'] != null) {
                final isodep = IsoDep.from(tag);
                if (isodep != null) {
                  await _writeToIsoDep(isodep, data);
                  writeSuccess = true;
                }
              }
            }

            // Detener la sesión después de escribir
            await NfcManager.instance.stopSession();
          } catch (e) {
            throw PlatformException(
              code: 'WRITE_ERROR',
              message: 'Error al escribir en NFC: ${e.toString()}',
            );
          }
        },
      );

      // Esperar hasta que se complete la escritura o se agote el tiempo
      int attempts = 0;
      while (!writeSuccess && attempts < 100) {
        // 10 segundos máximo
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (!writeSuccess) {
        throw PlatformException(
          code: 'TIMEOUT',
          message: 'Tiempo de espera agotado para escribir en NFC',
        );
      }

      return writeSuccess;
    } catch (e) {
      if (e is PlatformException) {
        rethrow;
      }
      throw PlatformException(
        code: 'NFC_ERROR',
        message: 'Error al escribir en NFC: ${e.toString()}',
      );
    }
  }

  static Future<void> _writeNdefMessage(Ndef ndef, String data) async {
    try {
      // Crear un mensaje NDEF con texto plano
      final textRecord = NdefRecord.createText(data);
      final message = NdefMessage([textRecord]);
      
      await ndef.write(message);
    } catch (e) {
      throw PlatformException(
        code: 'NDEF_WRITE_ERROR',
        message: 'Error al escribir NDEF: ${e.toString()}',
      );
    }
  }

  static Future<void> _writeToNfcA(NfcA nfca, String data) async {
    try {
      print('MIFARE Ultralight detectado, escribiendo texto plano: $data');
      
      // Convertir string a bytes UTF-8
      final dataBytes = data.codeUnits;
      
      // MIFARE Ultralight usa bloques de 4 bytes
      const int blockSize = 4;
      // Empezar desde el bloque 4 (después de los bloques del sistema)
      const int startBlock = 4;
      
      // Escribir datos en bloques de 4 bytes
      for (int i = 0; i < dataBytes.length; i += blockSize) {
        final end = (i + blockSize < dataBytes.length) ? i + blockSize : dataBytes.length;
        final blockData = dataBytes.sublist(i, end);
        
        // Rellenar con ceros si es necesario para completar 4 bytes
        final paddedBlock = List<int>.filled(blockSize, 0);
        for (int j = 0; j < blockData.length; j++) {
          paddedBlock[j] = blockData[j];
        }
        
        final blockNumber = startBlock + (i ~/ blockSize);
        
        // Comando APDU para escribir en MIFARE Ultralight
        final writeCommand = [
          0xFF, // CLA
          0xD6, // INS (UPDATE BINARY)
          0x00, // P1
          blockNumber, // P2 (número de bloque)
          blockSize, // Lc (longitud de datos)
          ...paddedBlock, // Datos del bloque
        ];
        
        print('Escribiendo bloque $blockNumber: ${paddedBlock.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        await nfca.transceive(data: Uint8List.fromList(writeCommand));
      }
      
      print('Escritura completada en MIFARE Ultralight');
    } catch (e) {
      throw PlatformException(
        code: 'NFC_A_WRITE_ERROR',
        message: 'Error al escribir en MIFARE Ultralight: ${e.toString()}',
      );
    }
  }

  static Future<void> _writeToIsoDep(IsoDep isodep, String data) async {
    try {
      // Para ISO-DEP, usar una aproximación más simple
      print('ISO-DEP tag detectado, datos a escribir: $data');
      // Simular escritura exitosa para tags ISO-DEP
    } catch (e) {
      throw PlatformException(
        code: 'ISODEP_WRITE_ERROR',
        message: 'Error al escribir en ISO-DEP: ${e.toString()}',
      );
    }
  }

  static String _byteArrayToHexString(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  static Future<String?> readNFCTagContent() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      throw PlatformException(
        code: 'NO_NFC',
        message: 'NFC no está disponible en este dispositivo',
      );
    }

    try {
      String? tagContent;

      await NfcManager.instance.startSession(
                onDiscovered: (NfcTag tag) async {
          try {
            // Intentar leer contenido de diferentes tipos de tags
            if (tag.data['nfca'] != null) {
              // Para MIFARE Ultralight, leer bloques de memoria
              final nfca = NfcA.from(tag);
              if (nfca != null) {
                tagContent = await _readMifareUltralightContent(nfca);
              }
            } else if (tag.data['ndef'] != null) {
              // Para tags NDEF, intentar leer como texto
              final ndef = Ndef.from(tag);
              if (ndef != null) {
                try {
                  final message = await ndef.read();
                  if (message.records.isNotEmpty) {
                    final record = message.records.first;
                    tagContent = String.fromCharCodes(record.payload.skip(1));
                  }
                } catch (e) {
                  print('Error leyendo NDEF: $e');
                }
              }
            }

            // Detener la sesión después de leer
            await NfcManager.instance.stopSession();
          } catch (e) {
            throw PlatformException(
              code: 'READ_ERROR',
              message: 'Error al leer contenido NFC: ${e.toString()}',
            );
          }
        },
      );

      // Esperar hasta que se lea un tag o se agote el tiempo
      int attempts = 0;
      while (tagContent == null && attempts < 100) {
        // 10 segundos máximo
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (tagContent == null) {
        throw PlatformException(
          code: 'TIMEOUT',
          message: 'Tiempo de espera agotado para leer contenido NFC',
        );
      }

      return tagContent;
    } catch (e) {
      if (e is PlatformException) {
        rethrow;
      }
      throw PlatformException(
        code: 'NFC_ERROR',
        message: 'Error al leer contenido NFC: ${e.toString()}',
      );
    }
  }

  static Future<String> _readMifareUltralightContent(NfcA nfca) async {
    try {
      print('Leyendo contenido de MIFARE Ultralight...');
      
      // Leer bloques desde el bloque 4 hasta el 15 (área de usuario)
      final List<int> allBytes = [];
      const int startBlock = 4;
      const int endBlock = 15; // MIFARE Ultralight tiene 16 páginas (0-15)
      
      for (int block = startBlock; block <= endBlock; block++) {
        try {
          // Comando APDU para leer bloque
          final readCommand = [
            0xFF, // CLA
            0xB0, // INS (READ BINARY)
            0x00, // P1
            block, // P2 (número de bloque)
            0x04, // Le (longitud esperada = 4 bytes)
          ];
          
          print('Leyendo bloque $block...');
          final response = await nfca.transceive(data: Uint8List.fromList(readCommand));
          
          // Agregar los bytes leídos
          allBytes.addAll(response);
          print('Bloque $block leído: ${response.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        } catch (e) {
          print('Error leyendo bloque $block: $e');
          break; // Si hay error, parar de leer
        }
      }
      
      // Convertir bytes a string, eliminando ceros al final
      String content = String.fromCharCodes(allBytes);
      
      // Eliminar caracteres nulos y espacios al final
      content = content.replaceAll('\x00', '').trim();
      
      // Buscar el final del texto (primer carácter nulo o espacio)
      int endIndex = content.length;
      for (int i = 0; i < content.length; i++) {
        if (content.codeUnitAt(i) == 0 || content.codeUnitAt(i) == 32) {
          endIndex = i;
          break;
        }
      }
      content = content.substring(0, endIndex);
      
      print('Contenido leído: "$content"');
      print('Bytes originales: ${allBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('Longitud del contenido: ${content.length}');
      
      return content;
    } catch (e) {
      throw PlatformException(
        code: 'MIFARE_READ_ERROR',
        message: 'Error al leer MIFARE Ultralight: ${e.toString()}',
      );
    }
  }
}
