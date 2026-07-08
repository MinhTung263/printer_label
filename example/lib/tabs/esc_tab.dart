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

  bool get _isBuiltInPrinterActive => _hasBuiltInPrinter && widget.isBuiltInPrinterConnected;

  List<String?> get _targetDeviceIds {
    if (widget.connectedDevices.isNotEmpty) {
      return widget.connectedDevices.map((d) => d.id).toList();
    }
    if (_isBuiltInPrinterActive) {
      return [null]; // null đại diện cho máy in tích hợp sẵn
    }
    return [DeviceId.lan(widget.ipAddress)];
  }

  @override
  void initState() {
    super.initState();
    _checkBuiltInPrinter();
  }

  Future<void> _checkBuiltInPrinter() async {
    final paperSize = await PrinterLabel.getBuiltInPrinterPaperSize();
    final hasPrinter = paperSize > 0;
    if (mounted) {
      setState(() {
        _hasBuiltInPrinter = hasPrinter;
        // Tự động chọn khổ giấy mặc định khớp với máy in tích hợp sẵn (K57 hoặc K80)
        if (hasPrinter) {
          _selectedSize = paperSize == 80 ? TicketSize.mm80 : TicketSize.mm58;
        }
      });

    }
  }

  void _showNoConnectionMsg() {
    showTopNotification(context, 'Vui lòng kết nối máy in trước khi in!');
  }

  Future<void> _printBuiltInExample() async {
    setState(() => _isPrintingEsc = true);
    try {
      // In trực tiếp thông qua luồng tự động kết nối máy in tích hợp sẵn
      await ESCPrintService.instance.printWidget(
        widget: ThermalReceiptPreview(
          size: _selectedSize,
          isForPrinting: true,
        ),
        size: _selectedSize,
      );
      if (mounted) {
        showTopNotification(
          context,
          'Đã kết nối và gửi lệnh in máy in tích hợp sẵn thành công!',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(context, 'Lỗi in tự động máy in tích hợp: $e');
      }
    } finally {
      if (mounted) setState(() => _isPrintingEsc = false);
    }
  }

  Future<void> _printExample() async {
    if (widget.connectedDevices.isEmpty && !_isBuiltInPrinterActive) {
      _showNoConnectionMsg();
      return;
    }
    setState(() => _isPrintingEsc = true);
    try {
      // In toàn bộ hóa đơn dưới dạng hình ảnh trên tất cả thiết bị đang kết nối
      for (final deviceId in _targetDeviceIds) {
        try {
          await ESCPrintService.instance.printWidget(
            deviceId: deviceId,
            widget: ThermalReceiptPreview(
              size: _selectedSize,
              isForPrinting: true,
            ),
            size: _selectedSize,
          );
        } catch (e) {
          debugPrint('Lỗi in hóa đơn trên $deviceId: $e');
          if (mounted) {
            showTopNotification(context, 'Lỗi in trên $deviceId: $e');
          }
        }
      }
    } finally {
      if (mounted) setState(() => _isPrintingEsc = false);
    }
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

                // Khu vực hiển thị hóa đơn giả lập giống hệt ticket.png
                Center(
                  child: ThermalReceiptPreview(
                    size: _selectedSize,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        // ─── Print button & Dropdown ───────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, -4),
                blurRadius: 8,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Dropdown chọn khổ giấy
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TicketSize>(
                    value: _selectedSize,
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
                        child: Text('K80 (80mm)'),
                      ),
                      DropdownMenuItem(
                        value: TicketSize.mm58,
                        child: Text('K57 (58mm)'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Nút in thử
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isPrintingEsc
                      ? null
                      : () {
                          if (widget.connectedDevices.isEmpty &&
                              !_isBuiltInPrinterActive) {
                            _showNoConnectionMsg();
                            return;
                          }

                          if (widget.connectedDevices.isEmpty &&
                              _isBuiltInPrinterActive) {
                            _printBuiltInExample();
                          } else {
                            _printExample();
                          }
                        },
                  icon: _isPrintingEsc
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.print),
                  label: Text(
                      _isPrintingEsc ? 'Đang in...' : 'In thử hoá đơn ESC'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
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

  const ThermalReceiptPreview({
    super.key,
    required this.size,
    this.isForPrinting = false,
  });

  @override
  Widget build(BuildContext context) {
    // Chiều rộng động theo khổ giấy để tạo cảm giác thực tế
    final double width = size == TicketSize.mm58 ? 240.0 : 320.0;

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
              'PRINTER LABEL',
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
              'Hotline: 0202122223332',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              'Hà Nội',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const SizedBox(height: 8),
            const Text(
              '15-01-2026 17:07:19',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              'Ngày 15 tháng 01 năm 2026',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              '15/01/2026',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              '15-01-2026',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const SizedBox(height: 14),

            // Tên hóa đơn
            const Text(
              'HÓA ĐƠN BÁN HÀNG',
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
              left: 'DH1558',
              right: '15-01-2026 17:07:19',
              isLeftBold: true,
            ),
            const _ReceiptRow(
              left: 'Mã cơ quan thuế',
              right: 'M1-26-J1PP1-11031611359',
            ),
            const _ReceiptRow(
              left: 'Khách hàng',
              right: 'Khách lẻ không lấy hóa đơn',
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
              children: const [
                // Header của bảng
                TableRow(
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

                // Sản phẩm 1
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cà phê muối đặc biệt',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'serif')),
                          Text('Đơn giá: 35,000',
                              style:
                                  TextStyle(fontSize: 10, fontFamily: 'serif')),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('1',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('35,000',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                  ],
                ),

                // Sản phẩm 2
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Trà lài đác thơm',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'serif')),
                          Text('Đơn giá: 45,000',
                              style:
                                  TextStyle(fontSize: 10, fontFamily: 'serif')),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('2',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('90,000',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                  ],
                ),

                // Sản phẩm 3
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bánh sừng bò trứng muối',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'serif')),
                          Text('Đơn giá: 39,000',
                              style:
                                  TextStyle(fontSize: 10, fontFamily: 'serif')),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('1',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('39,000',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: 'serif')),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(color: Colors.black, height: 1, thickness: 0.5),
            const SizedBox(height: 8),

            // Phần tính tiền tổng cộng
            const _ReceiptRow(left: 'Tạm tính', right: '164,000'),
            const _ReceiptRow(left: 'Tổng cộng', right: '164,000'),
            const _ReceiptRow(
                left: 'Tổng tiền thuế (VAT 10%)', right: '16,400'),
            const _ReceiptRow(left: 'Giảm trừ thuế', right: ''),
            const _ReceiptRow(
              left: 'Khách phải trả',
              right: '180,400',
              isRightBold: true,
            ),

            const SizedBox(height: 8),
            const Divider(color: Colors.black, height: 1, thickness: 1),
            const SizedBox(height: 12),
            const Text(
              'Thanh toán Chuyển khoản',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              'CẢM ƠN QUÝ KHÁCH',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontFamily: 'serif'),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.black, height: 1, thickness: 1),
            const SizedBox(height: 12),
            // Mã QR tra cứu vẽ bằng QrImageView
            const Text(
              'Mã QR tra cứu',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const SizedBox(height: 8),
            Center(
              child: QrImageView(
                data: 'https://github.com/MinhTung263/printer_label',
                version: QrVersions.auto,
                size: 100.0,
                gapless: false,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Mã tra cứu',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              '4u2gzeq367i8',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontFamily: 'serif'),
            ),
            const Text(
              'Tra cứu hóa đơn tại',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'serif'),
            ),
            const Text(
              'https://github.com/MinhTung263/printer_label',
              textAlign: TextAlign.center,
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontFamily: 'serif',
                fontSize: 11,
              ),
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
        shadowColor: Colors.black.withOpacity(0.15),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String left;
  final String right;
  final bool isLeftBold;
  final bool isRightBold;

  const _ReceiptRow({
    required this.left,
    required this.right,
    this.isLeftBold = false,
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
              style: TextStyle(
                fontFamily: 'serif',
                fontWeight: isLeftBold ? FontWeight.bold : FontWeight.normal,
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
