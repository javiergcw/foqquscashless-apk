class Manilla {
  final String cashlessId;

  final bool status;
  final String? token;
  final String cuentaId;

  Manilla({
    required this.cashlessId,

    required this.status,
    required this.token,
    required this.cuentaId,
  });

  factory Manilla.fromJson(Map<String, dynamic> json) {
    return Manilla(
      cashlessId: json['cashlessId'] as String,

      status: json['status'] as bool,
      token: json['token'] as String,
      cuentaId: json['cuentaId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cashlessId': cashlessId,

      'status': status,
      'token': token,
      'cuentaId': cuentaId,
    };
  }
} 