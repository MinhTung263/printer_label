import 'dart:typed_data';

import '../enums/paper_size_enum.dart';

class PrintThermalModel {
  final Uint8List image;
  final TicketSize size;

  PrintThermalModel({
    required this.image,
    this.size = TicketSize.mm80,
  });

  Map<String, dynamic> toJson() {
    return {
      'image': image,
      'size': size.value,
    };
  }
}
