import 'dart:isolate';
import 'dart:typed_data';

import '../label/label_calibration.dart';
import '../label/label_calibration_image.dart';
import 'printer_port.dart';
import 'tspl_commands.dart';
import 'tspl_label_spec.dart';
import 'tspl_raster.dart';

/// In tem (TSPL) ra một [PrinterPort] — cùng luồng với app Android: mỗi ảnh là
/// MỘT hàng tem (1–4 tem), co về đúng khổ giấy (8 chấm/mm) rồi gửi `BITMAP` +
/// `PRINT`. Không hỏi trạng thái giấy (nhiều máy tem không hiểu `DLE EOT`).
abstract final class TsplPrinter {
  /// Số chấm trên 1mm của máy in tem 203dpi.
  static const int dotsPerMm = 8;

  /// [calibration]: chỉnh tem in lệch (mm, dương = sang phải / xuống).
  ///
  /// Ném [FormatException] nếu không đọc được ảnh, [SocketException]... khi không
  /// kết nối được máy in.
  static Future<void> printImages(
    PrinterPort port,
    List<Uint8List> images, {
    required TsplLabelSpec spec,
    int copies = 1,
    LabelCalibration calibration = LabelCalibration.none,
  }) async {
    if (images.isEmpty) return;
    // Chỉnh lệch làm NGAY trong ảnh (không dùng REFERENCE: nhiều máy in bỏ qua giá trị
    // âm hoặc hiểu khác nhau) nên cùng một độ chỉnh cho kết quả giống nhau mọi máy.
    final shiftX = spec.shiftXDots + calibration.offsetXDots;
    final shiftY = calibration.offsetYDots;
    // MỘT isolate cho cả job (mở isolate mỗi hàng tốn thêm), dựng sẵn lệnh của mọi hàng.
    final data = await Isolate.run(() {
      final out = BytesBuilder(copy: false);
      for (final png in images) {
        final raster = TsplRaster.encodeImageBytes(
          png,
          widthDots: spec.widthDots,
          heightDots: spec.heightDots,
          shiftXDots: shiftX,
          shiftYDots: shiftY,
        );
        if (raster == null) return null;
        out.add(
          TsplCommands.label(
            bitmap: raster.bits,
            widthBytes: raster.widthBytes,
            heightDots: spec.heightDots,
            widthMm: spec.widthMm,
            heightMm: spec.heightMm,
            gapMm: spec.gapMm,
            copies: copies,
            home: spec.home,
          ),
        );
      }
      return out.takeBytes();
    });
    if (data == null) throw const FormatException('Ảnh tem không hợp lệ');
    // MỘT kết nối cho cả job: mỗi lần gửi riêng tốn thêm kết nối + nghỉ
    // [PortQueue.cooldown] (máy in tem giá rẻ còn hay báo "bận" ở lần mở lại).
    await port.send(data, checkStatus: false);
  }

  /// In tem thử căn chỉnh ([repeat] hàng liền nhau trong một lần — để so độ lệch giữa hàng đầu và hàng cuối) ([LabelCalibrationImage]) đúng khổ [spec] với độ chỉnh
  /// [calibration] — nhìn tờ giấy để biết cần chỉnh thêm bao nhiêu mm. [labelsPerRow]
  /// khác `null`: in tem mẫu như ngoài thị trường (tên, giá, mã vạch) thay cho thước.
  static Future<void> printCalibration(
    PrinterPort port, {
    required TsplLabelSpec spec,
    LabelCalibration calibration = LabelCalibration.none,
    int? labelsPerRow,
    int? temWidthMm,
    int repeat = 1,
  }) => printImages(
    port,
    [
      for (var i = 0; i < repeat.clamp(1, 10); i++)
        LabelCalibrationImage.png(
          widthMm: spec.widthMm,
          heightMm: spec.heightMm,
          calibration: calibration,
          labelsPerRow: labelsPerRow,
          temWidthMm: temWidthMm,
        ),
    ],
    // Tem thử đã vẽ sát mép: không dịch ảnh, chỉ áp độ chỉnh.
    spec: TsplLabelSpec(
      widthMm: spec.widthMm,
      heightMm: spec.heightMm,
      gapMm: spec.gapMm,
      home: spec.home,
      shiftXDots: 0,
    ),
    calibration: calibration,
  );

  /// Bảo máy in dò khe cuộn tem ([TsplCommands.gapDetect]) — máy cuốn vài tem rồi
  /// nhớ bề dài tem + khe thật.
  static Future<void> detectGap(
    PrinterPort port, {
    required TsplLabelSpec spec,
  }) => port.send(
    TsplCommands.gapDetect(
      widthMm: spec.widthMm,
      heightMm: spec.heightMm,
      gapMm: spec.gapMm,
    ),
    checkStatus: false,
  );
}
