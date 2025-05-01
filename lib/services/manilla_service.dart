import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foqquscashless/utils/tables.dart';
import '../models/cashless/manilla_model.dart';

class ManillaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> createManilla(Manilla manilla) async {
    try {
      await _firestore.collection(DB.cashless).add(manilla.toJson());
      return true;
    } catch (e) {
      print('Error creating manilla: $e');
      return false;
    }
  }

  Future<bool> updateManilla(Manilla manilla) async {
    try {
      await _firestore
          .collection(DB.cashless)
          .doc(manilla.token)
          .update(manilla.toJson());
      return true;
    } catch (e) {
      print('Error updating manilla: $e');
      return false;
    }
  }

  Future<Manilla?> getManillaByToken(
      {required String clientId, required String token}) async {
    try {
      if (clientId.isEmpty) {
        print('Error: clientId está vacío');
        return null;
      }

      if (token.isEmpty) {
        print('Error: token está vacío');
        return null;
      }

      print('Buscando manilla con clientId: $clientId y token: $token');

      final doc = await _firestore.collection(DB.cashless).doc(clientId).get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey(token)) {
          final manillaData = data[token];
          print('Manilla encontrada: $manillaData');
          return Manilla.fromJson(Map<String, dynamic>.from(manillaData));
        }
      }

      print('No se encontró la manilla');
      return null;
    } catch (e) {
      print('Error getting manilla by token: $e');
      return null;
    }
  }
}
