import 'package:example/connected_device.dart';
import 'package:example/widgets/print_preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:printer_label/printer_label.dart';
import 'package:qr_flutter/qr_flutter.dart';

class EscTab extends StatefulWidget {
  final String ipAddress;
  final List<ConnectedDevice> connectedDevices;
  final bool isBuiltInPrinterConnected;

  const EscTab({
    super.key,
    required this.ipAddress,
    required this.connectedDevices,
    this.isBuiltInPrinterConnected = false,
  });

  @override
  State<EscTab> createState() => _EscTabState();
}

class _EscTabState extends State<EscTab> {
  bool _isPrintingEsc = false;
  TicketSize _selectedSize = TicketSize.mm80;
  bool _hasBuiltInPrinter = false;
  int _printQuantity = 1; // Số lượng in
  bool _isLongReceipt = false; // Hóa đơn dài (~70cm)

  bool get _isBuiltInPrinterActive =>
      _hasBuiltInPrinter && widget.isBuiltInPrinterConnected;

  List<String?> get _targetDeviceIds {
    final ids = <String?>[];

    // Luôn thêm tất cả máy ngoài đang kết nối.
    if (widget.connectedDevices.isNotEmpty) {
      ids.addAll(widget.connectedDevices.map((d) => d.id));
    }

    // Máy in tích hợp chỉ in khi được chỉ định tường minh bằng DeviceId.builtIn.
    // Nếu built-in đang bật thì thêm vào danh sách để in song song cùng máy ngoài.
    if (_isBuiltInPrinterActive) {
      ids.add(DeviceId.builtIn);
    }

    // Không có máy nào ở trên: fallback in ra máy LAN theo IP đã nhập.
    if (ids.isEmpty) {
      ids.add(DeviceId.lan(widget.ipAddress));
    }

    return ids;
  }

  @override
  void initState() {
    super.initState();
    _checkBuiltInPrinter();
  }

  Future<void> _checkBuiltInPrinter() async {
    final type = await PrinterLabel.getBuiltInPrinterType();
    final hasPrinter = type != BuiltInPrinterType.none;
    if (mounted) {
      setState(() {
        _hasBuiltInPrinter = hasPrinter;
        // Tự động chọn khổ giấy mặc định khớp với máy in tích hợp sẵn (K57 hoặc K80)
        if (hasPrinter) {
          _selectedSize =
              type.paperSize == 80 ? TicketSize.mm80 : TicketSize.mm58;
        }
      });
    }
  }

  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  Future<void> _printExample() async {
    if (widget.connectedDevices.isEmpty && !_isBuiltInPrinterActive) {
      _showNoConnectionMsg();
      return;
    }
    setState(() => _isPrintingEsc = true);
    try {
      final deviceIds = _targetDeviceIds.whereType<String?>().toList();
      // Mỗi bản in: chụp ảnh MỘT lần rồi gửi SONG SONG tới tất cả máy.
      for (int i = 0; i < _printQuantity; i++) {
        try {
          await ESCPrintService.instance.printWidgetToDevices(
            deviceIds: deviceIds,
            widget: ThermalReceiptPreview(
              size: _selectedSize,
              isForPrinting: true,
              isLongReceipt: _isLongReceipt,
            ),
            size: _selectedSize,
            // Mở két như khi thanh toán tiền mặt. Chỉ ở BẢN IN ĐẦU: in nhiều liên
            // thì két đã mở sẵn rồi, không cần kích lại mỗi bản.
            openDrawer: i == 0,
          );
        } catch (e) {
          debugPrint('Lỗi in hóa đơn: $e');
          if (mounted) {
            showTopNotification(context, 'Lỗi in: $e');
          }
        }
        if (_printQuantity > 1 && i < _printQuantity - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      if (mounted) setState(() => _isPrintingEsc = false);
    }
  }

  Widget _buildPaperSizeOption(TicketSize size, String label) {
    final isSelected = _selectedSize == size;
    return GestureDetector(
      onTap: () => setState(() => _selectedSize = size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF6366F1) : Colors.black54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Preview area ──────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Thanh Cài Đặt Siêu Gọn ───────────────────────────────────
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Khổ giấy
                            Container(
                              height: 36,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPaperSizeOption(TicketSize.mm80, 'K80'),
                                  _buildPaperSizeOption(TicketSize.mm58, 'K57'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Số lượng (Stepper)
                            Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: const Icon(Icons.remove, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_printQuantity > 1) setState(() => _printQuantity--);
                                    },
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '$_printQuantity tờ',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: const Icon(Icons.add, size: 16, color: Colors.black54),
                                    onPressed: () {
                                      if (_printQuantity < 20) setState(() => _printQuantity++);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Hóa đơn dài
                            GestureDetector(
                              onTap: () => setState(() => _isLongReceipt = !_isLongReceipt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: _isLongReceipt ? const Color(0xFF6366F1) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: _isLongReceipt
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'In Dài',
                                  style: TextStyle(
                                    color: _isLongReceipt ? Colors.white : Colors.black54,
                                    fontWeight: _isLongReceipt ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                // Khu vực hiển thị hóa đơn giả lập giống hệt ticket.png
                Center(
                  child: ThermalReceiptPreview(
                    size: _selectedSize,
                    isLongReceipt: _isLongReceipt,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        // ─── Futuristic Print Button (Floating) ─────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: _isPrintingEsc ? null : const LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)], // Neon Cyan
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                color: _isPrintingEsc ? Colors.grey.shade400 : null,
                boxShadow: _isPrintingEsc
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0xFF4FACFE).withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        )
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _isPrintingEsc
                      ? null
                      : () {
                          if (widget.connectedDevices.isEmpty &&
                              !_isBuiltInPrinterActive) {
                            _showNoConnectionMsg();
                            return;
                          }
                          _printExample();
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isPrintingEsc)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          _isPrintingEsc ? 'ĐANG XỬ LÝ...' : 'IN HÓA ĐƠN',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
      ],
    );
  }
}

// ─── Hóa đơn nhiệt giả lập giống hệt ticket.png ───────────────────────────────
class ThermalReceiptPreview extends StatelessWidget {
  final TicketSize size;
  final bool isForPrinting; // Cờ xác định khi chụp ảnh in ấn
  final bool isLongReceipt; // Cờ xác định in hoá đơn dài test (~70cm)

  const ThermalReceiptPreview({
    super.key,
    required this.size,
    this.isForPrinting = false,
    this.isLongReceipt = false,
  });

  @override
  Widget build(BuildContext context) {
    // Chiều rộng động theo khổ giấy để tạo cảm giác thực tế
    final double width = size == TicketSize.mm58 ? 240.0 : 320.0;

    final List<ReceiptItem> items = [];
    if (isLongReceipt) {
      final candidates = [
        ('Cà phê muối đặc biệt', 35000.0),
        ('Trà lài đác thơm', 45000.0),
        ('Bánh sừng bò', 39000.0),
        ('Trà sữa trân châu', 40000.0),
        ('Nước cam ép tươi', 35000.0),
        ('Sinh tố bơ sáp', 50000.0),
        ('Cacao nóng cốt dừa', 45000.0),
        ('Bánh mì chảo đặc biệt', 55000.0),
        ('Mì Ý sốt bò bằm', 65000.0),
        ('Hồng trà sủi bọt', 38000.0),
        ('Matcha đá xay', 48000.0),
        ('Bạc sỉu cốt dừa', 35000.0),
        ('Trà đào cam sả', 42000.0),
        ('Khoai tây chiên bơ', 30000.0),
        ('Xúc xích nướng', 25000.0),
      ];
      for (int i = 0; i < 60; i++) {
        final cand = candidates[i % candidates.length];
        final name = '${cand.$1} #${i + 1}';
        final price = cand.$2;
        final qty = (i % 3) + 1;
        items.add(ReceiptItem(name: name, price: price, qty: qty));
      }
    } else {
      items.addAll([
        const ReceiptItem(name: 'Cà phê muối đặc biệt', price: 35000.0, qty: 1),
        const ReceiptItem(name: 'Trà lài đác thơm', price: 45000.0, qty: 2),
        const ReceiptItem(name: 'Bánh sừng bò', price: 39000.0, qty: 1),
      ]);
    }

    double subtotal = 0;
    for (final item in items) {
      subtotal += item.amount;
    }
    final discount = subtotal * 0.1;
    final totalToPay = subtotal - discount;
    final double cashReceived =
        ((totalToPay / 10000).ceil() * 10000).toDouble();
    final change = cashReceived - totalToPay;

    final content = Container(
      color: Colors
          .white, // Bắt buộc phải có nền trắng để ảnh chụp không bị trong suốt
      padding: EdgeInsets.fromLTRB(
        isForPrinting ? 2.0 : 16.0,
        24,
        isForPrinting ? 2.0 : 16.0,
        24,
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.black,
          fontFamily: 'serif',
          fontSize: 12,
          height: 1.3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header cửa hàng
            const Text(
              'PRINTER LABEL CAFE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                fontFamily: 'serif',
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Đ/c: 68 P. Tôn Thất Tùng, Đống Đa, Hà Nội',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              'Hotline: 0909.123.456',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const SizedBox(height: 14),

            // Tên hóa đơn
            const Text(
              'PHIẾU THANH TOÁN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                fontFamily: 'serif',
              ),
            ),
            const SizedBox(height: 10),

            // Thông tin chi tiết hóa đơn
            const _ReceiptRow(
              left: 'Số phiếu: HD-1558',
              right: 'Ngày: 15/01/2026 17:07',
            ),
            const _ReceiptRow(
              left: 'Thu ngân: Nguyễn Văn A',
              right: 'Bàn: 05',
            ),
            const SizedBox(height: 10),

            // Bảng danh sách sản phẩm canh chỉnh cột hoàn hảo
            Table(
              columnWidths: const {
                0: FlexColumnWidth(5), // Sản phẩm
                1: FlexColumnWidth(2), // Số lượng
                2: FlexColumnWidth(3), // Thành tiền
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Header của bảng
                const TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.black, width: 1),
                      bottom: BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Sản phẩm',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'serif')),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('SL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'serif')),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('T.Tiền',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'serif')),
                    ),
                  ],
                ),

                ...items.map((item) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'serif')),
                              Text('Đơn giá: ${_formatCurrency(item.price)}',
                                  style: const TextStyle(
                                      fontSize: 10, fontFamily: 'serif')),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('${item.qty}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontFamily: 'serif')),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(_formatCurrency(item.amount),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontFamily: 'serif')),
                        ),
                      ],
                    )),
              ],
            ),

            const Divider(color: Colors.black, height: 1, thickness: 0.5),
            const SizedBox(height: 8),

            // Phần tính tiền tổng cộng
            _ReceiptRow(left: 'Tổng tiền', right: _formatCurrency(subtotal)),
            _ReceiptRow(
                left: 'Giảm giá (10%)', right: '-${_formatCurrency(discount)}'),
            _ReceiptRow(
              left: 'Khách phải trả',
              right: _formatCurrency(totalToPay),
              isRightBold: true,
            ),
            const SizedBox(height: 4),
            _ReceiptRow(
                left: 'Tiền khách đưa', right: _formatCurrency(cashReceived)),
            _ReceiptRow(left: 'Tiền thối lại', right: _formatCurrency(change)),

            const SizedBox(height: 8),
            const Divider(color: Colors.black, height: 1, thickness: 1),
            const SizedBox(height: 12),
            const Text(
              'Wi-Fi: PrinterLabelCafe\nPass: 12345678',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif', fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'XIN CẢM ƠN VÀ HẸN GẶP LẠI!',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontFamily: 'serif'),
            ),
            const SizedBox(height: 12),
            // Mã QR tra cứu vẽ bằng QrImageView
            Center(
              child: QrImageView(
                data: 'https://github.com/MinhTung263/printer_label',
                version: QrVersions.auto,
                size: 80.0,
                gapless: false,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Quét để xem Menu',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif', fontSize: 11),
            ),
          ],
        ),
      ),
    );

    // Khi in, chỉ trả về nội dung phẳng, không có răng cưa hay bóng đổ
    if (isForPrinting) {
      return SizedBox(
        width: width,
        child: content,
      );
    }

    // Khi hiển thị trên màn hình, bọc ngoài bằng răng cưa và đổ bóng
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: PhysicalShape(
        clipper: TicketClipper(),
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String left;
  final String right;

  final bool isRightBold;

  const _ReceiptRow({
    required this.left,
    required this.right,
    this.isRightBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              left,
              style: const TextStyle(
                fontFamily: 'serif',
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              right,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'serif',
                fontWeight: isRightBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clipper tạo mép răng cưa xé giấy của hóa đơn nhiệt ──────────────────────
class TicketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Răng cưa mép trên
    path.moveTo(0, 0);
    double x = 0;
    double y = 0;
    const double increment = 4.0; // Kích thước răng cưa

    while (x < size.width) {
      x += increment;
      y = (y == 0) ? increment : 0;
      path.lineTo(x, y);
    }

    // Cạnh phải đi thẳng xuống
    path.lineTo(size.width, size.height);

    // Răng cưa mép dưới (vẽ ngược từ phải qua trái)
    x = size.width;
    y = size.height;
    while (x > 0) {
      x -= increment;
      y = (y == size.height) ? size.height - increment : size.height;
      path.lineTo(x, y);
    }

    // Cạnh trái đi thẳng lên
    path.lineTo(0, 0);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ReceiptItem {
  final String name;
  final double price;
  final int qty;

  const ReceiptItem({
    required this.name,
    required this.price,
    required this.qty,
  });

  double get amount => price * qty;
}

String _formatCurrency(double amount) {
  return amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
}
