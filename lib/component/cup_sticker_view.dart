import 'package:flutter/material.dart';

class PreviewCupSticker extends StatelessWidget {
  const PreviewCupSticker({super.key, required this.data});
  final PreviewLabelModel data;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildText(data.code),
              _buildText(
                "#${data.labelIndex}/${data.totalLabels}",
              ),
            ],
          ),
          Divider(),
          _buildText(
            data.productName.toUpperCase(),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
          _buildTextDivider(),
          if (data.toppings.isNotEmpty) ...[
            ...data.toppings.map(
              (topping) => Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                ),
                child: _buildText(
                  "+ $topping",
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ],
          if (data.note.isNotEmpty) ...[
            _buildLabelRow(
              "Test",
              data.note,
              fontStyle: FontStyle.italic,
            ),
          ],
          _buildLabelRow(
            "Price",
            data.price,
            fontWeight: FontWeight.bold,
          ),
          Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            spacing: 5,
            children: [
              Expanded(
                child: _buildText(
                  data.companyName,
                  fontSize: 20,
                  textAlign: TextAlign.left,
                ),
              ),
              Expanded(
                child: _buildText(
                  data.billDate,
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextDivider() {
    return Text(
      "-" * 100,
      maxLines: 1,
    );
  }

  Widget _buildText(
    String title, {
    FontStyle? fontStyle,
    FontWeight? fontWeight,
    TextAlign? textAlign,
    double? fontSize = 20,
  }) {
    return Text(
      title,
      style: TextStyle(
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontWeight: fontWeight,
      ),
      textAlign: textAlign,
    );
  }

  Widget _buildLabelRow(String title, String value,
      {FontStyle? fontStyle, FontWeight? fontWeight}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: _buildText(
            title,
            fontStyle: fontStyle,
          ),
        ),
        _buildText(
          value,
          fontStyle: fontStyle,
          fontWeight: fontWeight,
        ),
      ],
    );
  }
}

class PreviewLabelModel {
  final String code;
  final String productName;
  final String price;
  final String companyName;
  final List<String> toppings;
  final String note;
  final String billDate;
  final int labelIndex;
  final int totalLabels;

  PreviewLabelModel({
    required this.code,
    required this.productName,
    required this.price,
    required this.companyName,
    required this.toppings,
    required this.note,
    required this.billDate,
    required this.labelIndex,
    required this.totalLabels,
  });
}
