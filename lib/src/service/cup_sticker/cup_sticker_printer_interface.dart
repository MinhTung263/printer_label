import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../enums/enum.src.dart';
import 'cup_sticker_printer_impl.dart';

abstract class CupStickerPrinterPlatform extends PlatformInterface {
  CupStickerPrinterPlatform() : super(token: _token);

  static const Object _token = Object();

  static CupStickerPrinterPlatform _instance = CupStickerPrinterImpl();

  static CupStickerPrinterPlatform get instance => _instance;

  static set instance(CupStickerPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> printSticker({
    String? deviceId,
    PrinterConnectionType? connectionType,
    required List<Uint8List> imageBytesList,
    required CupStickerSize size,
  });

  Future<void> printWithWidgets({
    required List<Widget> widgets,
    BuildContext? context,
    required CupStickerSize size,
    int? widthOffsetMm,
    double? paddingMm,
    String? deviceId,
    PrinterConnectionType? connectionType,
  });

  Future<Uint8List> captureSticker({
    required Widget widget,
    required CupStickerSize size,
    BuildContext? context,
    double? paddingMm,
  });
}
