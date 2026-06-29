# printer_label

[![pub package](https://img.shields.io/pub/v/printer_label.svg)](https://pub.dev/packages/printer_label)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Platform-Flutter-02569B.svg)](https://flutter.dev)

A comprehensive, high-performance Flutter printing package. Easily connect to and print on various printer hardware (supporting **TSPL** for labels/barcodes and **ESC/POS** for thermal receipts) via **Bluetooth**, **LAN (Wi-Fi)**, and **USB** connections.

---

## 🚀 Features

- 📶 **Multi-Connection Support**: Print via Bluetooth, LAN (Wi-Fi), or USB.
- 🏷️ **TSPL Printing (Labels)**: Build dynamic labels using Flutter widgets, render them automatically, and print them as single or multi-column layouts (`LabelPerRow`).
- 🧾 **ESC/POS Printing (Receipts)**: Print receipts from rasterized images or custom templates.
- 🥤 **Cup Sticker Service**: Custom service tailored for milk tea/coffee cup label printing with automatic resizing and layout alignment.
- 🔍 **Device Discovery**: Listen to real-time streams for Bluetooth BLE scanning and Android USB connection events.
- ⚡ **Asynchronous Bridging**: High-performance lazy stream caching and robust platform serialization.

---

## 📱 Platform & Connection Support Matrix

| Connection | Android | iOS | Protocol | Supported Formats |
| :--- | :---: | :---: | :---: | :--- |
| **LAN (Wi-Fi)** | ✔ | ✔ | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |
| **Bluetooth** | ✔ | ✔ (BLE) | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |
| **USB** | ✔ | ❌ | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |

---

## 🛠️ Getting Started

### 1. Installation

Add `printer_label` as a dependency in your `pubspec.yaml`:

```yaml
dependencies:
  printer_label: ^latest_version
```

Then run:
```bash
flutter pub get
```

---

### 2. Platform Setup

#### 🤖 Android Configuration

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Internet & Network Status for LAN Printers -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    
    <!-- Bluetooth Permissions -->
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
</manifest>
```

#### 🍏 iOS Configuration

Add the following usage keys to your `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>We need bluetooth permission to discover and connect to Bluetooth printers.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>We need bluetooth permission to discover and connect to Bluetooth printers.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>We need local network permission to discover and connect to LAN printers.</string>
```

---

## 💡 Core Usage Guides

### 1. Connection Management

We provide a `DeviceId` utility helper to format and tag printer identifiers correctly.

```dart
import 'package:printer_label/printer_label.dart';

// Construct standardized IDs
final lanId = DeviceId.lan('192.168.1.56');
final btId = DeviceId.bluetooth('00:11:22:33:FF:EE');
final usbId = DeviceId.usb('/dev/bus/usb/001/002');

// Connect to a LAN (Wi-Fi) printer
final bool connected = await PrinterLabel.connectLan(ipAddress: '192.168.1.56');

// Check if a specific printer is active
final bool isActive = await PrinterLabel.checkConnect(deviceId: lanId);

// Disconnect printer
final bool disconnected = await PrinterLabel.disconnectPrinter(deviceId: lanId);
```

---

### 2. Bluetooth Scanning & Connecting

```dart
// 1. Start bluetooth scanning (required on iOS before listening)
if (Platform.isIOS) {
  await PrinterLabel.startBluetoothScan();
}

// 2. Subscribe to scan stream
final subscription = PrinterLabel.bluetoothScanStream.listen((device) {
  print("Discovered: ${device.name} - MAC/UUID: ${device.mac}");
});

// 3. Connect to target device
final bool connected = await PrinterLabel.connectBluetooth(macAddress: device.mac);

// 4. Stop scanning when finished
if (Platform.isIOS) {
  await PrinterLabel.stopBluetoothScan();
}
subscription.cancel();
```

---

### 3. TSPL Label Printing (From Flutter Widgets)

To print labels dynamically, use `LabelPrintService` to capture your widget layouts and format them based on your paper layout (`LabelPerRow`).

```dart
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';

await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
  items: products,
  context: context,
  deviceId: DeviceId.lan('192.168.1.56'),
  labelPerRow: LabelPerRow.single, // Or LabelPerRow.doubleLabels, LabelPerRow.tripleLabels
  itemBuilder: (product, stampWidth, stampHeight) => BarcodeView<ProductBarcodeModel>(
    data: product,
    stampWidth: stampWidth,
    stampHeight: stampHeight,
    nameBuilder: (p) => p.name,
    barcodeBuilder: (p) => p.barcode,
    priceBuilder: (p) => p.price,
  ),
  quantity: (p) => p.quantity,
);
```

---

### 4. Direct Barcode & Text Printing (Native Commands)

If you don't need widgets, you can print native text and barcodes directly by sending native TSPL commands:

```dart
final textElements = [
  TextData(y: 20, data: "iPhone 17 Pro Max"),
  TextData(y: 170, data: "28.990.000 VND"),
];

final model = BarcodeModel(
  barcodeY: 60,
  width: 300,
  barcodeContent: "83868888",
  textData: textElements,
  quantity: 1,
);

await PrinterLabel.printBarcode(
  deviceId: DeviceId.lan('192.168.1.56'),
  printBarcodeModel: model,
);
```

---

### 5. ESC/POS Receipt Printing

To print standard receipt layouts, load your image assets or render widgets and output them to thermal printers:

```dart
// Load receipt rasterized template
final Uint8List imageBytes = await ESCPrintService.instance.loadImageFromAssets(
  "assets/images/receipt_ticket.png",
);

await PrinterLabel.printESC(
  deviceId: DeviceId.lan('192.168.1.56'),
  printThermalModel: PrintThermalModel(
    image: imageBytes,
    size: TicketSize.mm80, // Options: mm58, mm80
  ),
);
```

---

### 6. Cup Sticker Printing (Tailored POS Service)

Perfect for quick milk tea cup labels or coffee kitchen tickets. Supports automatic resizing to common market paper sizes.

```dart
// Option A: Print directly from pre-rendered image bytes
await CupStickerPrinter.printSticker(
  deviceId: DeviceId.lan('192.168.1.56'),
  imageBytesList: [rawImageBytes],
  size: CupStickerSize.s60x40, // 60x40 mm - standard cup sticker size
);

// Option B: Print directly from Flutter widgets
await CupStickerPrinter.printWithWidgets(
  widgets: [
    MyStickerWidget(orderId: "102", title: "Matcha Latte"),
  ],
  context: context,
  size: CupStickerSize.s60x40,
  deviceId: DeviceId.lan('192.168.1.56'),
);
```

#### 📏 Standard Cup Sticker Sizes Provided:
* `CupStickerSize.s40x30`: 40 x 30 mm (Mini labels / Cup caps)
* `CupStickerSize.s50x30`: 50 x 30 mm (Small cups)
* `CupStickerSize.s60x40`: 60 x 40 mm (Standard size / Most popular)
* `CupStickerSize.s70x50`: 70 x 50 mm (Large cups)
* `CupStickerSize.s80x60`: 80 x 60 mm (Extra large labels)

---

## 📸 Preview Screens

### 📱 Example Dashboard App
The package contains a fully optimized developer dashboard to test LAN, Bluetooth, and USB connection configurations, print layouts, and thermal templates:

![Developer Dashboard](https://github.com/user-attachments/assets/0fe164b2-9bf5-4a4a-a59e-f71a45fdef15)

### 🖨️ Physical Output Result
Example output on physical TSPL label & ESC/POS receipt paper:

![Physical Output](https://github.com/user-attachments/assets/b41e5700-5462-4b79-bdb7-a729bff82e23)

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
