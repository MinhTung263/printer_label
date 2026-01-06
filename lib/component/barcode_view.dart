import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src.dart';

class BarcodeView extends StatelessWidget {
  BarcodeView({
    super.key,
    required this.product,
    this.dimensions = Dimensions.defaultDimens,
    this.labelColor,
  });
  final ProductBarcodeModel product;
  final Dimensions dimensions;
  final Color? labelColor;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: labelColor ?? Colors.blue,
      width: dimensions.width,
      height: dimensions.height,
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
            width: dimensions.width,
            height: dimensions.barcodeHeight,
            drawText: true, // Hiển thị mã số dưới mã vạch
            style: const TextStyle(fontSize: 18),
          ),
          _buildText(
            NumberFormat.currency(
                  locale: 'vi_VN',
                  symbol: '',
                ).format(product.price) +
                "VNĐ",
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
        fontSize: dimensions.fontSize + (addFontSize ?? 0),
        fontWeight: fontWeight,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
