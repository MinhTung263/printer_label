## [2.1.1] - 2026-07-03

- **Feature (Platform)**: Added built-in POS printer API support for Android:
  - `PrinterLabel.autoConnectBuiltIn()` to automatically connect to integrated hardware printers (Sunmi, iMin, etc.).
  - `PrinterLabel.disconnectBuiltIn()` to cleanly disconnect/disable built-in printer drivers.
  - `PrinterLabel.getBuiltInPrinterPaperSize()` to retrieve the paper size of integrated printers.
- **Optimization (iOS/Android)**: Implemented high-contrast image binarization:
  - Custom integer-based luminance algorithm (threshold 200) to force light/transparent pixels to white and dark pixels to solid black, resulting in extremely sharp text/barcodes on iOS and Android.
- **Optimization (iOS)**: BLE transmission optimizations to prevent printer buffer overflow and motor starvation:
  - Restricts chunk size to a safe limit of 180 bytes.
  - Introduces dynamic write pacing/delay (targeting 16 KB/s).
- **Documentation**: Overhauled `README.md` with:
  - Clearer platform and connection support matrix.
  - Corrected raw command API signatures.
  - New, descriptive preview screenshots of the developer dashboard, TSPL label printing, ESC/POS receipts, and Cup Sticker functions.

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
