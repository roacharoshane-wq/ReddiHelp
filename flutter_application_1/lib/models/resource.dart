class Resource {
  final String type;
  final int quantity;
  final String unit;

  Resource({required this.type, required this.quantity, required this.unit});

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      type: json['type'],
      quantity: json['quantity'],
      unit: json['unit'],
    );
  }
}
