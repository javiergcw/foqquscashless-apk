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
}
