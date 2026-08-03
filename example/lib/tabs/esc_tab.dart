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

  Future<void> _openDrawer() async {
    try {
      await PrinterLabel.openDrawer();
      if (mounted) {
        showTopNotification(context, 'Đã gửi lệnh mở két sắt', isError: false);
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(context, 'Lỗi mở két sắt: $e');
      }
    }
  }

  Future<void> _printBatchThenOpenDrawer() async {
    await _openDrawer();
  }

  Future<void> _printRawText() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printText(
          deviceId: deviceId,
          text:
              'Printer Label - Test Raw Text Printing ESC/POS\nLine 2 - Hello World!\n\n',
        );
        if (mounted) {
          showTopNotification(context, 'Đã gửi lệnh in Text ESC tới $deviceId',
              isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Text trên $deviceId: $e');
        }
      }
    }
  }

  Future<void> _printRawBarcode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printBarcode(
          deviceId: deviceId,
          code: '123456789012',
          type: '128',
        );
        if (mounted) {
          showTopNotification(
              context, 'Đã gửi lệnh in Barcode ESC tới $deviceId',
              isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in Barcode trên $deviceId: $e');
        }
      }
    }
  }

  Future<void> _printRawQRCode() async {
    for (final deviceId in _targetDeviceIds) {
      try {
        await ESCPrintService.instance.printQRCode(
          deviceId: deviceId,
          code: 'https://github.com/MinhTung263/printer_label',
          size: 8,
        );
        if (mounted) {
          showTopNotification(
              context, 'Đã gửi lệnh in QR Code ESC tới $deviceId',
              isError: false);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(context, 'Lỗi in QR trên $deviceId: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Preview area ──────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PrintSectionHeader(
                  icon: Icons.receipt_long,
                  color: Color(0xFF6366F1),
                  title: 'In hoá đơn ESC/POS',
                  subtitle:
                      'Sử dụng giao thức in hoá đơn nhiệt ESC/POS thông thường.',
                ),

                // Chọn số lượng in
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Chọn khổ giấy
                      Row(
                        children: [
                          const Text('Khổ giấy: ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<TicketSize>(
                                value: _selectedSize,
                                isDense: true,
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: Color(0xFF6366F1)),
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                onChanged: (TicketSize? newSize) {
                                  if (newSize != null) {
                                    setState(() {
                                      _selectedSize = newSize;
                                    });
                                  }
                                },
                                items: const [
                                  DropdownMenuItem(
                                      value: TicketSize.mm80,
                                      child: Text('K80')),
                                  DropdownMenuItem(
                                      value: TicketSize.mm58,
                                      child: Text('K57')),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Chọn số lượng in
                      Row(
                        children: [
                          const Text('Số lượng: ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _printQuantity,
                                isDense: true,
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: Color(0xFF6366F1)),
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                onChanged: (int? newQty) {
                                  if (newQty != null) {
                                    setState(() {
                                      _printQuantity = newQty;
                                    });
                                  }
                                },
                                items: [1, 2, 3, 5, 10].map((int value) {
                                  return DropdownMenuItem<int>(
                                    value: value,
                                    child: Text('$value'),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Chọn Hóa đơn dài (~70cm)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Hóa đơn dài (~70cm):',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      Switch(
                        value: _isLongReceipt,
                        activeThumbColor: const Color(0xFF6366F1),
                        onChanged: (bool value) {
                          setState(() {
                            _isLongReceipt = value;
                          });
                        },
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
        // ─── Print & Drawer Action Buttons ─────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -4),
                blurRadius: 8,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Nút Mở Két Sắt Độc Lập
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: _isPrintingEsc ? null : () => _openDrawer(),
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text(
                      'MỞ KÉT',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Nút In Hoá Đơn Thường
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isPrintingEsc
                        ? null
                        : () {
                            if (widget.connectedDevices.isEmpty &&
                                !_isBuiltInPrinterActive) {
                              _showNoConnectionMsg();
                              return;
                            }
                            _printExample();
                          },
                    icon: _isPrintingEsc
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.print, size: 16),
                    label: Text(
                      _isPrintingEsc ? 'ĐANG IN...' : 'IN HÓA ĐƠN',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Nút In Bộ Vé Rồi Mới Mở Két (Test Scenario)
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: _isPrintingEsc
                        ? null
                        : () {
                            if (widget.connectedDevices.isEmpty &&
                                !_isBuiltInPrinterActive) {
                              _showNoConnectionMsg();
                              return;
                            }
                            _printBatchThenOpenDrawer();
                          },
                    icon: const Icon(Icons.point_of_sale, size: 16),
                    label: Text(
                      'IN $_printQuantity VÉ + KÉT',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ─── Raw print (dev) ───────────────────────────────────────────────
        buildRawPrintBar(
          color: Colors.indigo.shade600,
          title: 'In thô ESC/POS (dev)',
          buttons: [
            (label: 'Mở két sắt', onPressed: () => _openDrawer()),
            (
              label: 'In Text',
              onPressed: () =>
                  (widget.connectedDevices.isEmpty && !_isBuiltInPrinterActive)
                      ? _showNoConnectionMsg()
                      : _printRawText()
            ),
            (
              label: 'In Barcode',
              onPressed: () =>
                  (widget.connectedDevices.isEmpty && !_isBuiltInPrinterActive)
                      ? _showNoConnectionMsg()
                      : _printRawBarcode()
            ),
            (
              label: 'In QR',
              onPressed: () =>
                  (widget.connectedDevices.isEmpty && !_isBuiltInPrinterActive)
                      ? _showNoConnectionMsg()
                      : _printRawQRCode()
            ),
          ],
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
