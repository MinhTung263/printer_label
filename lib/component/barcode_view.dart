import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../enums/type_print_enum.dart';

class BarcodeView<T> extends StatelessWidget {
  const BarcodeView({
    super.key,
    required this.data,
    Dimensions? dimensions,
    required this.nameBuilder,
    required this.barcodeBuilder,
    required this.priceBuilder,
    this.labelColor,
    this.title = 'Printer Label',
  }) : dimensions = dimensions ?? Dimensions.defaultDimens;

  final T data;
  final Dimensions dimensions;
  final Color? labelColor;

  /// Builders
  final String Function(T data) nameBuilder;
  final String Function(T data) barcodeBuilder;
  final double Function(T data) priceBuilder;

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: labelColor ?? Colors.white,
      width: dimensions.width,
      height: dimensions.height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildText(title),
          _buildText(
            nameBuilder(data),
            fontWeight: FontWeight.bold,
          ),
          BarcodeWidget(
            barcode: Barcode.code93(),
            data: barcodeBuilder(data),
            width: dimensions.width,
            height: dimensions.barcodeHeight,
            drawText: true,
            style: const TextStyle(fontSize: 18),
          ),
          _buildText(
            formatVND(priceBuilder(data)),
            fontWeight: FontWeight.bold,
            addFontSize: 5,
          ),
        ],
      ),
    );
  }

  String formatVND(double price) {
    return price.toInt().toString().replaceAllMapped(
              RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
              (m) => '${m[1]}.',
            ) +
        ' VNĐ';
  }

  Widget _buildText(
    String text, {
    FontWeight? fontWeight,
    double? addFontSize,
  }) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: dimensions.fontSize + (addFontSize ?? 0),
        fontWeight: fontWeight,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
