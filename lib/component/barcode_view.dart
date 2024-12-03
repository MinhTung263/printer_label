import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../src.dart';

class BarcodeView extends StatelessWidget {
  const BarcodeView({
    super.key,
    required this.product,
    this.typePrintEnum,
  });
  final ProductBarcodeModel product;
  final TypePrintEnum? typePrintEnum;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: typePrintEnum?.width,
      height: typePrintEnum?.height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildText(
            "EasyPos",
          ),
          _buildText(
            product.name,
            fontWeight: FontWeight.bold,
          ),
          BarcodeWidget(
            barcode: Barcode.code93(), // Loại mã vạch (có thể thay đổi)
            data: product.barcode,
            width: typePrintEnum?.width,
            height: typePrintEnum?.barcodeHeight,
            drawText: true, // Hiển thị mã số dưới mã vạch
            style: const TextStyle(fontSize: 18),
          ),
          _buildText(
            product.price.toString(),
            fontWeight: FontWeight.bold,
            addFontSize: 5,
          ),
        ],
      ),
    );
  }

  Widget _buildText(
    String text, {
    FontWeight? fontWeight,
    double? addFontSize,
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: (typePrintEnum?.fontSize ?? 20) + (addFontSize ?? 0),
        fontWeight: fontWeight,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
