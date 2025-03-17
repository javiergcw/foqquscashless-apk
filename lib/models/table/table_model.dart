class TableModel {
  final String cashlessId;

  TableModel({
    required this.cashlessId,
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    return TableModel(
      cashlessId: json['cashlessId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cashlessId': cashlessId,
    };
  }
  
  
}
