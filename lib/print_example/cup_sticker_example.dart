import 'package:flutter/material.dart';

import '../component/src.dart';
import '../enums/enum.src.dart';
import '../service/service.src.dart';

class CupStickerPrintExample {
  const CupStickerPrintExample._();

  static Future<void> printOrderCupSticker(
    CupStickerSize size, {
    BuildContext? context,
  }) async {
    final List<PreviewLabelModel> dataList = [
      PreviewLabelModel(
        code: "1213",
        productName: "Trà sữa",
        price: "27.000 đ",
        companyName: "Printer Label",
        note: "Test print",
        labelIndex: 1,
        billDate: "01/01/2026",
        totalLabels: 1,
        toppings: ["Đá", "Đường"],
      ),
      PreviewLabelModel(
        code: "1214",
        productName: "Trà đào",
        price: "30.000 đ",
        companyName: "Printer Label",
        note: "Order #2",
        labelIndex: 2,
        billDate: "02/01/2026",
        totalLabels: 2,
        toppings: ["Đá", "Trân châu"],
      ),
      PreviewLabelModel(
        code: "1215",
        productName: "Trà sữa matcha",
        price: "35.000 đ",
        companyName: "Printer Label",
        note: "Order #3",
        labelIndex: 3,
        billDate: "03/01/2026",
        totalLabels: 3,
        toppings: ["Đá", "Thạch", "Sữa đặc"],
      ),
    ];
    final List<Widget> stickerWidgets = dataList.map((data) {
      return PreviewCupSticker(data: data);
    }).toList();

    await CupStickerPrinter.printWithWidgets(
      widgets: stickerWidgets,
      size: size,
      context: context,
    );
  }
}
