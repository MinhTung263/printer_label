This is a source copy of `printer_label` 2.3.0, selected by the workspace's
`dependency_overrides`. The upstream LICENSE and platform SDKs are included.

Local changes:

- Capture label widgets at the configured printer width (8 dots/mm), keeping
  the existing logical layout and gaps. The capture rebuild delay defaults to
  20ms and can be supplied by callers through `captureDelay`.
- On iOS, combine up to 10 complete TSPL rows or 256 KiB per transport job.
  An oversized row remains intact.
- Honor `is_last_batch` on iOS LAN: retain an idle socket for an intermediate
  batch, with a 15-second watchdog, and use the usual idle close after the last.
- Keep the LAN send queue blocked while a previous job awaits confirmation.
- Return targeted iOS BLE completion after its write finishes, so Dart can bound
  the amount of queued work and receive write errors.

Validation from the workspace root:

```sh
flutter test --no-pub packages/printer_label/test/label_from_widget_test.dart app/features/print_config/test/core/utils/label_batch_pipeline_test.dart
swiftc packages/printer_label/ios/Classes/LabelPayloadBatcher.swift packages/printer_label/test/label_payload_batcher_test.swift -o /tmp/label-payload-test
/tmp/label-payload-test
swiftc packages/printer_label/ios/Classes/PrintTransfer.swift packages/printer_label/ios/Classes/PrinterCapabilities.swift packages/printer_label/ios/Classes/LANPrinterConnection.swift packages/printer_label/test/lan_batch_connection_test.swift -o /tmp/lan-batch-test
/tmp/lan-batch-test
```

The Swift executables require macOS. The LAN regression test uses a loopback
fake printer; paper output, barcode readability, and sustained Bluetooth sends
still need a physical printer check. Rebuild the app after dependency changes
to load native plugin changes.


## Native discovery

Byte pacing was removed: receipt/label writes go out at the speed the transport
allows, as upstream 2.3.0 does. Throttling the feed starved the print engine and
made the motor stutter. Flow control that reflects real readiness is kept — iOS
BLE still waits for `peripheralIsReady` / write ACK, LAN still waits for the
printer to confirm a job, and `WRITE_STALL_TIMEOUT_MS` still kills a dead socket.
No status requests are inserted into bitmap data; the configured raster, SDK TSPL
encoding, feed/cut commands and copies retain their byte order.

Discovery runs while creating a printer, under the same send lock/queue as
printing. Each language requires two correctly framed status replies. Neither a
connection nor a timeout establishes support. Results contain:

- `languages.escpos` / `languages.tspl`: `confirmed` or `unknown`, including dual
  evidence. Positive status evidence is not exclusive-language detection.
- `features.nativeText`, `raster`, `barcode`, `qrCode`: `not_tested`; status alone
  does not validate optional commands, font coverage, or barcode readability.
- `receiveBufferBytes`: null; no portable status query reports this reliably.
- `reason`: `status_reply`, `no_response`, `no_read_channel`, `offline`, etc.

BLE discovery requires a notify/indicate return channel. Native iOS subscribes
when discovering characteristics and keeps probes in the peripheral's serial
write queue. Printers without a usable return channel remain `unknown`.
The app persists capability evidence separately from legacy routing preferences,
displays it on the creation form, and does not change the user's print role.
Background post-print protocol probes were removed so queries cannot enter a
still-printing job.

Additional validation:

```sh
flutter test --no-pub packages/printer_label/test/printer_capabilities_test.dart app/features/print_config/test/core/utils/printer_capabilities_routing_test.dart
cd app/android
./gradlew :printer_label:testDebugUnitTest
```

Swift transfer/discovery tests (from the workspace root):

```sh
swiftc packages/printer_label/ios/Classes/PrintTransfer.swift packages/printer_label/ios/Classes/PrinterCapabilities.swift packages/printer_label/test/print_transfer_test.swift -o /tmp/print-transfer-test
/tmp/print-transfer-test
swiftc packages/printer_label/ios/Classes/PrintTransfer.swift packages/printer_label/ios/Classes/PrinterCapabilities.swift packages/printer_label/ios/Classes/LANPrinterConnection.swift packages/printer_label/test/lan_capabilities_transfer_test.swift -o /tmp/lan-capabilities-test
/tmp/lan-capabilities-test
```

The loopback test checks ESC/POS, TSPL, dual replies, silence, echoed queries,
and a 32 KiB binary payload preserved byte for byte through the rate limiter.
Android tests compare the SDK's old/new command bytes and simulate partial
writes. Paper output and physical receive-buffer behavior still need a printer.
