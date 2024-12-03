class ProductBarcodeModel {
  final String barcode;
  final String name;
  final double price;
  final int quantity;

  ProductBarcodeModel({
    required this.barcode,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  // Convert a Product object into a Map for easy JSON encoding or database storage
  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'name': name,
      'price': price,
      'quantity': quantity,
    };
  }

  // Create a Product object from a Map
  factory ProductBarcodeModel.fromMap(Map<String, dynamic> map) {
    return ProductBarcodeModel(
      barcode: map['barcode'] ?? '',
      name: map['name'] ?? '',
      price: map['price'] ?? '',
      quantity: map['quantity'] ?? 1,
    );
  }
}
