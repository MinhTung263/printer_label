# printer_label

[![pub package](https://img.shields.io/pub/v/printer_label.svg)](https://pub.dev/packages/printer_label)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Platform-Flutter-02569B.svg)](https://flutter.dev)

A comprehensive, high-performance Flutter printing package. Easily connect to and print on various printer hardware (supporting **TSPL** for labels/barcodes and **ESC/POS** for thermal receipts) via **Bluetooth BLE**, **LAN (Wi-Fi)**, and **USB** connections.

---

## 🚀 Features

- 📶 **Multi-Connection Support**: Print via Bluetooth BLE, LAN (Wi-Fi), or USB.
- 🏷️ **TSPL Printing (Labels)**: Build dynamic labels using Flutter widgets, render them automatically, and print them as single or multi-column layouts (`LabelPerRow`).
- 🧾 **ESC/POS Printing (Receipts)**: Print receipts from rasterized images or custom templates with automatic height scaling.
- 🥤 **Cup Sticker Service**: Custom service tailored for milk tea/coffee cup label printing with automatic resizing and layout alignment.
- 🔍 **Device Discovery**: Listen to real-time streams for Bluetooth BLE scanning and Android USB connection events.
- ⚡ **Asynchronous Bridging**: High-performance lazy stream caching and robust platform serialization.

---

## ⚡ Specialized Built-in Optimizations

Unlike standard printing packages, `printer_label` comes with pre-configured native performance tuning:

1. **High-Contrast Binarization (iOS & Android)**: Uses a custom integer-based luminance algorithm (threshold `200`) to force light/transparent pixels to white and dark pixels to solid black. This ensures text is sharp, dark, and highly legible on iOS, matching Android's print quality perfectly.
2. **BLE Write Flow Pacing**: Restricts chunk size to a safe limit of `180` bytes and introduces a continuous dynamic pacing delay (targeting `16 KB/s`) based on chunk sizes. This prevents printer buffer overflows (which cause corrupt characters/symbols) and motor starvation (which causes jerky, stuttering printing).
3. **Built-in POS Printer Toggle**: Full connect and disconnect support for integrated POS hardware printers (Sunmi, iMin, etc.) via `PrinterLabel.disconnectBuiltIn()`, allowing developers to cleanly disable built-in printing when testing external hardware.

---

## 📱 Platform & Connection Support Matrix

| Connection | Android | iOS | Protocol | Supported Formats |
| :--- | :---: | :---: | :---: | :--- |
| **LAN (Wi-Fi)** | ✔ | ✔ | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |
| **Bluetooth** | ✔ | ✔ (BLE) | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |
| **USB** | ✔ | ❌ | TSPL / ESC/POS | Widgets, Images, Direct Barcodes |

---

## 🖼️ Previews & Feature Output

Here are visual examples of the capabilities of the library:

### 🏷️ Sample Feature Previews
| Label Printing (TSPL) | Thermal Receipt (ESC/POS) | Cup Sticker |
| :---: | :---: | :---: |
| ![Label Print](https://raw.githubusercontent.com/MinhTung263/printer_label/master/images/label_tab_single.png) | ![Receipt Print](https://raw.githubusercontent.com/MinhTung263/printer_label/master/images/receipt_tab.png) | ![Cup Sticker Print](https://raw.githubusercontent.com/MinhTung263/printer_label/master/images/cup_sticker_tab.png) |

### 📱 Example Dashboard App
The package contains a fully optimized developer dashboard to test LAN, Bluetooth, and USB connection configurations, print layouts, and thermal templates:

![Developer Dashboard](https://github.com/user-attachments/assets/0fe164b2-9bf5-4a4a-a59e-f71a45fdef15)

### 🖨️ Physical Output Result
Example output on physical TSPL label & ESC/POS receipt paper:

![Physical Output](https://github.com/user-attachments/assets/b41e5700-5462-4b79-bdb7-a729bff82e23)

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

#### 🖨️ Built-in POS Printer Control (Android Only)
For devices with integrated thermal printers, you can connect or disconnect the hardware driver cleanly:
```dart
// Auto-connect to built-in printer
final bool connected = await PrinterLabel.autoConnectBuiltIn();

// Disconnect/Disable the built-in printer
final bool disconnected = await PrinterLabel.disconnectBuiltIn();
```

---

### 2. Bluetooth Scanning & Connecting

```dart
// 1. Start bluetooth scanning (required on iOS before listening)
if (Platform.isIOS) {
  await PrinterLabel.startBluetoothScan();
}

// 2. Subscribe to scan stream (invoke as a method call)
final subscription = PrinterLabel.bluetoothScanStream().listen((device) {
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
  itemBuilder: (product) => BarcodeView<ProductBarcodeModel>(
    data: product,
    stampWidth: LabelPerRow.single.stampWidth,
    stampHeight: LabelPerRow.single.stampHeight,
    nameBuilder: (p) => p.name,
    barcodeBuilder: (p) => p.barcode,
    priceBuilder: (p) => p.price,
  ),
  quantity: (p) => p.quantity,
);
```

#### 💡 Custom Widget Example (No `BarcodeView` dependency)
You can print **any** custom Flutter widget (e.g. price tags, milk tea labels, QR codes) by returning your own layout in `itemBuilder`:

```dart
await LabelPrintService.instance.printLabels<MyCustomProduct>(
  items: products,
  context: context,
  deviceId: DeviceId.lan('192.168.1.56'),
  labelPerRow: LabelPerRow.single,
  itemBuilder: (product) => Container(
    padding: const EdgeInsets.all(8),
    color: Colors.white,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          product.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text('Price: \$${product.price}'),
        // You can embed QR codes, icons, custom borders, etc.
      ],
    ),
  ),
  quantity: (p) => 1,
);
```

---

### 4. Direct Barcode & QR Code Printing (Native Commands)

If you don't need to print custom widgets, you can print barcodes and QR codes directly by sending raw printer commands (TSPL for labels, ESC/POS for receipts):

#### 🏷️ TSPL (Label Printer)
```dart
// Print raw barcode directly
await PrinterLabel.printBarcode(
  deviceId: DeviceId.lan('192.168.1.56'),
  code: "83868888",
  x: 20,
  y: 60,
  height: 100,
  type: "128",
);

// Print raw QR Code directly
await PrinterLabel.printQRCode(
  deviceId: DeviceId.lan('192.168.1.56'),
  code: "https://pub.dev/packages/printer_label",
  x: 20,
  y: 20,
  size: 5,
);
```

#### 🧾 ESC/POS (Receipt Printer)
```dart
// Print raw barcode directly
await ESCPrintService.instance.printBarcode(
  deviceId: DeviceId.lan('192.168.1.56'),
  code: "83868888",
);

// Print raw QR Code directly
await ESCPrintService.instance.printQRCode(
  deviceId: DeviceId.lan('192.168.1.56'),
  code: "https://pub.dev/packages/printer_label",
);
```

---

### 5. ESC/POS Receipt Printing (Thermal Receipts)

To print standard receipt layouts, you can print a Flutter widget directly (which automatically measures the widget's natural height to prevent cutoff or overflows) or send pre-rendered image bytes:

#### Option A: Print Directly from a Flutter Widget (Recommended)
```dart
await ESCPrintService.instance.printWidget(
  deviceId: DeviceId.lan('192.168.1.56'),
  widget: MyReceiptWidget(), // Any Flutter widget
  size: TicketSize.mm80, // Options: mm58, mm80
  pixelRatio: 2.5, // Resolution scale (2.5 is ideal for thermal printers)
);
```

#### Option B: Print from Image Bytes
```dart
await ESCPrintService.instance.print(
  deviceId: DeviceId.lan('192.168.1.56'),
  model: PrintThermalModel(
    image: rawImageBytes, // Uint8List of PNG image
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

### 7. Widget Capture Utility

If you need to capture Flutter widgets as images for custom printing pipelines or other purposes, you can use the `WidgetCaptureHelper` utility class. It handles offscreen rendering, proper text directionality, and scaling safety:

```dart
import 'package:printer_label/printer_label.dart';

// 1. Capture a standard widget (e.g. for label stickers)
final Uint8List labelBytes = await WidgetCaptureHelper.captureFromWidget(
  MyLabelWidget(),
  pixelRatio: 5.0, // High resolution for print clarity
);

// 2. Capture a potentially long widget (e.g. for long receipts)
// Automatically measures the widget's natural height to prevent cutoffs or overflows
final Uint8List receiptBytes = await WidgetCaptureHelper.captureFromLongWidget(
  MyReceiptWidget(),
  pixelRatio: 2.5,
);
```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
