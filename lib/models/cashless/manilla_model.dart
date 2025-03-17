class Manilla {
  final String cashlessId;
  final String clientId;
  final bool status;
  final String token;

  Manilla({
    required this.cashlessId,
    required this.clientId,
    required this.status,
    required this.token,
  });

  factory Manilla.fromJson(Map<String, dynamic> json) {
    return Manilla(
      cashlessId: json['cashlessId'] as String,
      clientId: json['clientId'] as String,
      status: json['status'] as bool,
      token: json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cashlessId': cashlessId,
      'clientId': clientId,
      'status': status,
      'token': token,
    };
  }
} 