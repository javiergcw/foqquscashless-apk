import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foqquscashless/models/billing/billing_model.dart';
import 'package:foqquscashless/utils/tables.dart';

class BillingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // crear una cuenta
  Future<bool> createBilling(BillModel billing) async {
    try {
      await _firestore.collection(DB.bill).add(billing.toMap());
      return true;
    } catch (e) {
      print('Error creating beading: $e');
      return false;
    }
  }

  // agregar un fidelizado a la lista
  Future<bool> addLoyalty(String documentId, String loyalty) async {
    try {
      DocumentReference docRef = _firestore.collection(DB.bill).doc(documentId);
      await docRef.update({
        'fidelizados': FieldValue.arrayUnion([loyalty])
      });
      return true;
    } catch (e) {
      print('Error adding fidelizado: $e');
      return false;
    }
  }

  // agregar un cashless a la lista 
  Future<bool> addCashlessToBilling(String documentId, String cashless) async {
    try {
      DocumentReference docRef = _firestore.collection(DB.bill).doc(documentId);
      await docRef.update({
        'cashlessId': FieldValue.arrayUnion([cashless])
      });
      return true;
    } catch (e) {
      print('Error adding cashless: $e');
      return false;
    }
  }

  // cerrar billing (cambiar estado a false)
  Future<bool> closeBilling(String documentId) async {
    try {
      DocumentReference docRef = _firestore.collection(DB.bill).doc(documentId);
      await docRef.update({'isActive': false});
      return true;
    } catch (e) {
      print('Error closing billing: $e');
      return false;
    }
  }

  // eliminar un fidelizado de la lista
  Future<bool> removeLoyalty(String documentId, String loyalty) async {
    try {
      DocumentReference docRef = _firestore.collection(DB.bill).doc(documentId);
      await docRef.update({
        'fidelizados': FieldValue.arrayRemove([loyalty])
      });
      return true;
    } catch (e) {
      print('Error removing fidelizado: $e');
      return false;
    }
  }

  Future<bool> removeCashlessFromBilling(String documentId, String cashless) async {
    try {
      DocumentReference docRef = _firestore.collection(DB.bill).doc(documentId);
      await docRef.update({
        'cashlessId': FieldValue.arrayRemove([cashless])
      });
      return true;
    } catch (e) {
      print('Error removing cashless: $e');
      return false;
    }
  }
}
