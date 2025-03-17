import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foqquscashless/models/table/table_model.dart';
import 'package:foqquscashless/utils/tables.dart';
class TableService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> createTable(TableModel table) async {
    try {
      await _firestore.collection(DB.table).add(table.toJson());
      return true;
    } catch (e) {
      print('Error creating table: $e');
      return false;
    }
  }
}