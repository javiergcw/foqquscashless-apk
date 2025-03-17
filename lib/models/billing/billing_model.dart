class BillModel {
  final String clientId;
  final String cashlessId;
  final List<String> fidelizados;
  final String mesas;
  final bool status;

  BillModel({
    required this.clientId,
    required this.cashlessId,
    required this.fidelizados,
    required this.mesas,
    required this.status,
  });

  // Método para convertir un Map en un objeto BillModel
  factory BillModel.fromMap(Map<String, dynamic> map) {
    return BillModel(
      clientId: map['clientId'] ?? '',
      cashlessId: map['cashlessId'] ?? '',
      fidelizados: List<String>.from(map['fidelizados'] ?? []),
      mesas: map['mesas'] ?? '',
      status: map['status'] ?? false,
    );
  }

  // Método para convertir un objeto BillModel en un Map
  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'cashlessId': cashlessId,
      'fidelizados': fidelizados,
      'mesas': mesas,
      'status': status,
    };
  }
}
