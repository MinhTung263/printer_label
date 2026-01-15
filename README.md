# printer_label

Make printer label easy.

## Features
- Print labels via LAN (Wi-Fi)
- Support barcode, image, and thermal printing
- Cross-platform Flutter support

---

## Platform Support

### iOS
- Wi-Fi printing only

### Android
- Wi-Fi / USB (depends on printer)
- Required permissions:
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />


import 'package:printer_label/printer_label.dart';

🔧 Core Printing API
Printer Connection
/// Check printer connection (Android only)
final connected = await PrinterLabel.checkConnect();

/// Connect to LAN printer
await PrinterLabel.connectLan(
  ipAddress: '192.168.1.100',
);

Print Label (Images)
await PrinterLabel.printLabel(
  barcodeImageModel: labelModel,
);

Print Image
await PrinterLabel.printPrintImage(
  model: imageModel,
);

Print Barcode
await PrinterLabel.printBarcode(
  printBarcodeModel: barcodeModel,
);

Print Thermal (ESC/POS)
await PrinterLabel.printThermal(
  printThermalModel: thermalModel,
);

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

CupStickerPrinter.printSticker(
  imageBytesList: images,
  size: CupStickerSize.medium,
);

CupStickerPrinter is a utility class for printing cup stickers / drink labels.

Supports:

Printing from raw image bytes

Printing from Flutter widgets

Automatically:

Resizes images to match sticker size

Aligns labels correctly for thermal printers

Designed for single-label-per-row sticker printers.

Use Cases

Milk tea cup labels

Coffee shop stickers

Order number & customer name labels

POS / kitchen printing




Print a sample thermal label image using the built-in ESC/POS service.

await ESCPrintService.instance.printExample();

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
