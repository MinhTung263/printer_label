## [2.1.1] - 2026-07-03

### 🚀 Core Architecture & Package Restructuring
- **PlatformInterface Restructuring**: Redesigned and restructured package services to align with Flutter's recommended `PlatformInterface` layout for clean separation of concerns and stable cross-platform method channel behavior.
- **Modular Native Code**: Modularized native Android side, simplified the MethodChannel enum, and added multi-brand POS device detection/support.
- **API Simplifications**: Simplified `printLabels` API signature and cleaned up compiler warnings across the codebase. Removed the redundant `Dimensions` helper class.

### 📶 Connection Management & Discovery
- **Connection Diagnostics**: Implemented `checkPrinterStatus` and added connection verification for LAN and Bluetooth devices prior to actual print actions.
- **Smart BLE Features**: Added Bluetooth enabled checks across platforms. On iOS, implemented reconnect functionality for BLE printers without needing a full device scan. Optimized BLE connection timeout to 5s.
- **Reliable USB Discovery**: Implemented automatic USB device scanning at app startup and improved USB identification by saving and mapping raw USB device IDs.
- **Error Isolation & Retry**: Implemented automatic retry on LAN/Wi-Fi socket write failure and isolated connection failures when using concurrent multiple printer execution.

### 🖨️ Android & iOS Native Printing Optimizations
- **Automatic Command Set Detection**: Implemented automatic printer command set validation and detection (e.g. automatically verifying ESC/POS vs TSPL) to prevent corrupt commands.
- **BLE Write Flow Pacing (iOS)**: Optimized iOS Bluetooth print flow by restricting write chunk sizes to a safe limit of 180 bytes and implementing a dynamic pacing delay (16 KB/s) to prevent printer buffer overflows and motor starvation.
- **High-Contrast Binarization**: Developed custom integer-based luminance algorithm (threshold 200) to force light/transparent pixels to white and dark pixels to solid black, resolving blurry text/barcodes on iOS and Android.
- **Image Resizing & Precision Mapping**: 
  - Android: Enabled dynamic target width calculation based on physical dot calculations (`sizeWidth * 8`).
  - iOS: Implemented native `CGImage` scaling/resizing to fit exact physical print width. Adjusted `startX` coordinate (subtracted 20 dots) on iOS to prevent right-shifting on 1-label templates.
  - Corrected gap size and bitmap width on TSPL printing to eliminate label misalignment.

### ⚡ Performance & Rendering Speed
- **Parallel Image Capture**: Drastically improved print rendering performance by capturing multiple widget layouts in parallel using `Future.wait`.
- **Pixel-Perfect Widget Capturing**: Optimized pixel-perfect 1:1 widget capturing and stabilized Bluetooth delays.
- **Direct Widget Printing**: Improved widget capture and added support for direct widget printing.

### 📱 Example App Redesign & Documentation
- **UX & UI Redesign**: Fully overhauled and split the example dashboard app features into separate modular tab files.
- **Instant Preview**: Implemented instant widget print preview to see layout changes before printing.
- **Interactive Redesigns**: Redesigned the Cup Sticker tab UI, merged bluetooth scan/connect flows into a smart single-entry button, unified top-sliding snackbars, and optimized Bluetooth filtering.
- **Documentation**: Overhauled `README.md` with updated screenshots (devices, labels, receipts, cup stickers) hosted directly on raw GitHub for pub.dev compatibility.

## [2.1.0] - 2026-05-25

- Add Bluetooth connection support for iOS
- Support multiple printer connections

## [2.0.9] - 2026-04-9

- Fix connect USB

## [2.0.8] - 2026-01-22

- Fixed app crash when connecting to printer on Android 6

## [2.0.7] - 2026-01-19

- Fixed app crash when connecting to printer on Android

## [2.0.6] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.5] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.4] - 2026-01-15

- Bug fixes and minor improvements

## [2.0.3] - 2026-01-12

- Bug fixes and minor improvements

## [v2.0.2] - 2026/01/12

- Fixed issue where printing two labels in one row did not work correctly

## [v2.0.1] - 2026/01/08

- Add run with Simulator
- Config print Cup Sticker
- Fix other bug

## [v2.0.0] - 2026/01/07

New Features

- Added support for printing on iOS.

- Improvements

- Refactored and reconfigured print styles.

Added print size configuration options.

## [v1.0.10] - 2025/10/03

- Upgrade fvm 3.35.4, intl 0.20.2

## [v1.0.9] - 2025/09/22

Network Connectivity

- Fixed LAN connection issues on Android devices.

## [v1.0.8] - 2025/06/28

- Fixed installation issue on devices that do not support USB host feature.

## [v1.0.7] - 2025/03/11

- downgrade intl: ^0.19.0

## [v1.0.6] - 2025/03/11

- Fix print only android

## [v1.0.5] - 2025/03/07

- Added thermal printer result output.

## [v1.0.4] - 2025/03/05

- Fix connect USB

## [v1.0.3] - 2025/02/26

Bug Fixes

- Fixed USB connection issues.
- Added automatic USB connection configuration.

- Implemented connection status checking.

## [v1.0.0] - 2025/02/05

Initial Release

- First public release.
