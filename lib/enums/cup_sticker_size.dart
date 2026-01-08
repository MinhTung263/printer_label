/// Size tem ly (đơn vị: mm)
/// Dùng class + const để app khác có thể mở rộng
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
