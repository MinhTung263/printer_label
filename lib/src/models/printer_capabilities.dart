/// Positive status replies are evidence of a command language, not evidence
/// that every optional font, QR or raster command is implemented by a model.
class PrinterCapabilities {
  final String deviceId;
  final String escPos;
  final String tspl;
  final String reason;
  final Map<String, String> features;

  const PrinterCapabilities({
    required this.deviceId,
    this.escPos = 'unknown',
    this.tspl = 'unknown',
    this.reason = 'no_response',
    this.features = const {
      'nativeText': 'not_tested',
      'raster': 'not_tested',
      'barcode': 'not_tested',
      'qrCode': 'not_tested',
    },
  });

  factory PrinterCapabilities.fromMap(Map<dynamic, dynamic> value) {
    final languages = value['languages'] as Map? ?? const {};
    return PrinterCapabilities(
      deviceId: value['deviceId'] as String? ?? '',
      escPos: languages['escpos'] == 'confirmed' ? 'confirmed' : 'unknown',
      tspl: languages['tspl'] == 'confirmed' ? 'confirmed' : 'unknown',
      reason: value['reason'] as String? ?? 'no_response',
    );
  }

  bool get confirmsEscPos => escPos == 'confirmed';
  bool get confirmsTspl => tspl == 'confirmed';
  bool get hasConfirmedLanguage => confirmsEscPos || confirmsTspl;
  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'languages': {'escpos': escPos, 'tspl': tspl},
        'reason': reason,
        'features': features,
        // Status replies do not expose receive-buffer capacity in a portable way.
        'receiveBufferBytes': null,
      };
}
