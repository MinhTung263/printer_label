# printer_label

Make printer label easy.

## Features
- Print labels via LAN (Wi-Fi)
- Support barcode, image, and thermal printing
- Cross-platform Flutter support

---

## Platform Support

| Android | iOS |
|---------|-----|
| ✔       | ✔   |

### iOS
- Wi-Fi printing only

### Android
- Wi-Fi / USB (depends on printer)
- Required permissions:
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

## Installation

Add the dependency in your `pubspec.yaml` file:

```
dependencies:
  printer_label: ^<latest_version>
```

```dart
import 'package:printer_label/printer_label.dart';
```
🔧 Core Printing API

```dart

  Future<String?> get platformVersion;

  Future<bool> checkConnect();

  Future<bool> disconectPrinter();

  Future<bool> connectLan({
    required String ipAddress,
  });

  Future<void> printLabel({
    required LabelModel labelModel,
  });

  Future<void> printImage({
    required ImageModel imageModel,
  });

  Future<void> printBarcode({
    required BarcodeModel printBarcodeModel,
  });

  Future<void> printESC({
    required PrintThermalModel printThermalModel,
  });
```
🧾 Description

PrinterLabel is the core API for interacting with label printers.

Provides low-level access to:

Printer connection

LAN printing

Barcode printing

Image & thermal printing

All higher-level services are built on top of this API.

⚠️ Notes

checkConnect() is currently supported on Android only.

LAN printing requires the printer and device to be on the same network.

Most users should use:

LabelPrintService

CupStickerPrinter

Use PrinterLabel directly only when:

You need full control

You are implementing custom print logic

```dart
package:printer_label/service/label_printer_service.dart.

await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
    items: products,
    context: context,
    labelPerRow: _selectedRow,
    itemBuilder: (item, dimensions) => BarcodeView<ProductBarcodeModel>(
      data: ProductBarcodeModel(),
      dimensions: dimensions,
      nameBuilder: (p) => p.name,
      barcodeBuilder: (p) => p.barcode,
      priceBuilder: (p) => p.price,
    ),
  quantity: (p) => p.quantity,
);
```
LabelPrintService provides a high-level API for printing labels from data collections.

Uses Flutter widgets to build each label layout.

Automatically:

Renders widgets to images

Duplicates labels based on quantity

Aligns labels according to LabelPerRow


Cup Sticker Printing

Support printing cup stickers / drink labels from images or Flutter widgets.

Print Sticker from Images

Use this method when you already have sticker images (PNG/JPG) in bytes format.

```dart

class CupStickerPrinter {
  const CupStickerPrinter._();

  static Future<void> printSticker({
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  }) async {
    final images = <Uint8List>[];

    for (final bytes in imageBytesList) {
      images.add(
        await resizeImage(
          imageBytes: bytes,
          size: size,
        ),
      );
    }

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.single.copyWith(
        width: size.widthMm.toInt(),
        height: size.heightMm.toInt(),
        x: 0,
        y: 0,
      ),
    );
    await PrinterLabel.printLabel(
      barcodeImageModel: model,
    );
  }

  static Future<void> printWithWidgets({
    required List<Widget> widgets,
    BuildContext? context,
    required CupStickerSize size,
    int? widthOffsetMm,
    double? paddingMm,
  }) async {
    final images = <Uint8List>[];

    for (final widget in widgets) {
      final bytes = await LabelFromWidget.captureFromWidget(
        widget,
        context: context,
      );

      final resized = await resizeImage(
        imageBytes: bytes,
        size: size,
        paddingMm: paddingMm,
      );

      images.add(resized);
    }

    final widthMm = size.widthMm.toInt() + (widthOffsetMm ?? 0);
    final heightMm = size.heightMm.toInt();

    final model = LabelModel(
      images: images,
      labelPerRow: LabelPerRow.single.copyWith(
        width: widthMm,
        height: heightMm,
        x: 0,
        y: 0,
      ),
    );

    await PrinterLabel.printLabel(
      barcodeImageModel: model,
    );
  }
}



class CupStickerSize {
  final String key;
  final double widthMm;
  final double heightMm;

  const CupStickerSize({
    required this.key,
    required this.widthMm,
    required this.heightMm,
  });

  /// ===== DEFAULT MARKET SIZES =====

  /// 40 x 30 mm – tem rất nhỏ (nắp / ly mini)
  static const s40x30 = CupStickerSize(
    key: '40x30',
    widthMm: 40,
    heightMm: 30,
  );

  /// 50 x 30 mm – ly nhỏ
  static const s50x30 = CupStickerSize(
    key: '50x30',
    widthMm: 50,
    heightMm: 30,
  );

  /// 60 x 40 mm – ly vừa (phổ biến nhất)
  static const s60x40 = CupStickerSize(
    key: '60x40',
    widthMm: 60,
    heightMm: 40,
  );

  /// 70 x 50 mm – ly lớn
  static const s70x50 = CupStickerSize(
    key: '70x50',
    widthMm: 70,
    heightMm: 50,
  );

  /// 80 x 60 mm – ly lớn / topping nhiều
  static const s80x60 = CupStickerSize(
    key: '80x60',
    widthMm: 80,
    heightMm: 60,
  );

  /// Danh sách size mặc định package cung cấp
  static const List<CupStickerSize> defaults = [
    s40x30,
    s50x30,
    s60x40,
    s70x50,
    s80x60,
  ];

  @override
  String toString() => 'CupStickerSize($key: ${widthMm}x$heightMm)';
}
```
CupStickerPrinter is a utility class for printing cup stickers / drink labels.

Supports:

```
Printing from raw image bytes

Printing from Flutter widgets

Automatically:

Resizes images to match sticker size

Aligns labels correctly for thermal printers

Designed for single-label-per-row sticker printers.
```
Use Cases

```
Milk tea cup labels

Coffee shop stickers

Order number & customer name labels

POS / kitchen printing
```
###Capture Image from widget

```dart

class LabelFromWidget {
  const LabelFromWidget._();
  static Future<List<Uint8List>> captureImages<T>(
    List<T> products,
    BuildContext context, {
    required Widget Function(
      T product,
      Dimensions dimensions,
    ) itemBuilder,
    required int Function(T product) quantity,
    LabelPerRow labelPerRow = LabelPerRow.doubleLabels,
    double spacer = 60,
  }) async {
    Dimensions dimensions = labelPerRow == LabelPerRow.single
        ? Dimensions.large
        : Dimensions.defaultDimens;

    final int itemsPerRow = labelPerRow.count;
    final List<Uint8List> images = [];
    final List<T> expandedProducts = [];

    for (var product in products) {
      for (int i = 0; i < quantity(product); i++) {
        expandedProducts.add(product);
      }
    }

    final List<List<T>> groupedProducts = [];
    for (int i = 0; i < expandedProducts.length; i++) {
      if (i % itemsPerRow == 0) {
        groupedProducts.add([]);
      }
      groupedProducts.last.add(expandedProducts[i]);
    }

    for (var row in groupedProducts) {
      final List<Widget> productWidgets = [];

      for (int i = 0; i < row.length; i++) {
        productWidgets.add(
          itemBuilder(row[i], dimensions),
        );

        if (i < row.length - 1) {
          productWidgets.add(SizedBox(width: spacer));
        }
      }

      final itemsToAdd = itemsPerRow - row.length;
      for (int i = 0; i < itemsToAdd; i++) {
        productWidgets.add(
          SizedBox(
            width: dimensions.width + spacer,
            height: dimensions.height,
          ),
        );
      }

      final rowWidget = Row(children: productWidgets);

      final imageBytes = await ScreenshotController().captureFromLongWidget(
        rowWidget,
        context: context,
        constraints: const BoxConstraints.tightFor(),
      );

      images.add(imageBytes);
    }

    return images;
  }

  static Future<Uint8List> captureFromWidget(
    Widget widget, {
    BuildContext? context,
    double? pixelRatio,
  }) async {
    final imageBytes = await ScreenshotController().captureFromWidget(
      widget,
      context: context,
      pixelRatio: pixelRatio ?? 5,
    );
    return imageBytes;
  }
}
```


Print a sample thermal label image using the built-in ESC/POS service.

```dart

await ESCPrintService.instance.printExample();
```

Description

ESCPrintService is a singleton service used to handle thermal printing.

printExample() prints a demo label image bundled inside the package.

The example image is loaded from Flutter assets and sent directly to the thermal printer.

This is useful for:

Testing printer connectivity

Demo purposes

Verifying printer alignment and image quality



## Screenshot
![Image](https://github.com/user-attachments/assets/0fe164b2-9bf5-4a4a-a59e-f71a45fdef15)

## Result printer
![Image](https://github.com/user-attachments/assets/b41e5700-5462-4b79-bdb7-a729bff82e23)
