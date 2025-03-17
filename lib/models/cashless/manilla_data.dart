import 'dart:convert';

class ManillaData {
  final String accion;
  final String timestamp;

  ManillaData({
    required this.accion,
    required this.timestamp,
  });

  factory ManillaData.fromJson(Map<String, dynamic> json) {
    return ManillaData(
      accion: json['accion'] as String,
      timestamp: json['timestamp'] as String,
    );
  }

  static ManillaData? fromUri(Uri uri) {
    try {
      final jsonString = uri.toString().replaceFirst('manillasapp://', '');
      final decodedJson = json.decode(Uri.decodeComponent(jsonString));
      return ManillaData.fromJson(decodedJson);
    } catch (e) {
      print('Error parsing URI: $e');
      return null;
    }
  }
} 