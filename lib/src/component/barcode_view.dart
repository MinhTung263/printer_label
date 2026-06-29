import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

class BarcodeView<T> extends StatelessWidget {
  const BarcodeView({
    super.key,
    required this.data,
    required this.nameBuilder,
    required this.barcodeBuilder,
    required this.priceBuilder,
    this.labelColor,
    this.title = 'Printer Label',
    this.stampWidth = 35.0,
    this.stampHeight = 22.0,
  });

  final T data;
  final Color? labelColor;
  final double stampWidth;
  final double stampHeight;

  /// Builders
  final String Function(T data) nameBuilder;
  final String Function(T data) barcodeBuilder;
  final double Function(T data) priceBuilder;

  final String title;

  double get widthPx => stampWidth * 6.57;
  double get heightPx => stampHeight * 6.57;

  @override
  Widget build(BuildContext context) {
    final double baseFontSize = heightPx * 0.09;
    final double priceFontSize = heightPx * 0.13;
    final double barcodeHeight = heightPx * 0.36;

    return Container(
      color: labelColor ?? Colors.white,
      width: widthPx,
      height: heightPx,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildText(
            title,
            fontWeight: FontWeight.bold,
            fontSize: baseFontSize * 0.9,
          ),
          _buildText(
            nameBuilder(data),
            fontWeight: FontWeight.bold,
            fontSize: baseFontSize,
          ),
          SizedBox(height: heightPx * 0.02),
          BarcodeWidget(
            barcode: Barcode.code93(),
            data: barcodeBuilder(data),
            width: widthPx - 20,
            height: barcodeHeight,
            drawText: true,
            style: TextStyle(fontSize: baseFontSize * 0.8),
          ),
          SizedBox(height: heightPx * 0.02),
          _buildText(
            formatVND(priceBuilder(data)),
            fontWeight: FontWeight.bold,
            fontSize: priceFontSize,
          ),
        ],
      ),
    );
  }

  String formatVND(double price) {
    final formatted = price.toInt().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return '$formatted VNĐ';
  }

  Widget _buildText(
    String text, {
    FontWeight? fontWeight,
    required double fontSize,
  }) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
