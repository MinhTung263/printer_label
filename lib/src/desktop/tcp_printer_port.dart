import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'escpos_commands.dart';
import 'paper_status.dart';
import 'port_queue.dart';
import 'printer_port.dart';

/// Máy in LAN nhận lệnh thô qua TCP (cổng 9100 — "RAW / JetDirect"). Chạy giống
/// nhau trên Windows / Linux / macOS, không cần driver.
///
/// Mỗi lệnh một kết nối (nhiều máy in LAN chỉ cho một kết nối một lúc và tự nhả
/// socket khi rảnh); các lệnh tới CÙNG máy được xếp hàng tuần tự trong tiến trình
/// này để byte của hai phiếu không chèn vào nhau.
class TcpPrinterPort implements PrinterPort {
  TcpPrinterPort(
    this.host, {
    this.port = 9100,
    this.connectTimeout = const Duration(seconds: 5),
    this.statusTimeout = const Duration(milliseconds: 800),
    this.chunkSize = 4096,
  });

  final String host;
  final int port;
  final Duration connectTimeout;

  /// Chờ mỗi câu trả lời trạng thái (Wi-Fi đông có khứ hồi dài).
  final Duration statusTimeout;

  /// Gửi theo gói: gửi cả cục ảnh vài trăm KB làm tràn bộ đệm máy in giá rẻ.
  final int chunkSize;

  @override
  String get id => 'tcp://$host:$port';

  @override
  Future<void> send(Uint8List data, {bool checkStatus = true}) =>
      PortQueue.run(id, () async {
        final conn = await _TcpConn.open(host, port, connectTimeout);
        try {
          if (checkStatus) {
            final status = await _queryOn(conn);
            if (status.blocksPrinting) throw PrinterStatusException(status);
          }
          for (var off = 0; off < data.length; off += chunkSize) {
            final end = off + chunkSize < data.length
                ? off + chunkSize
                : data.length;
            conn.socket.add(Uint8List.sublistView(data, off, end));
            await conn.socket.flush();
          }
        } finally {
          await conn.close();
        }
      });

  @override
  Future<PaperStatus> queryStatus() => PortQueue.run(id, () async {
    final conn = await _TcpConn.open(host, port, connectTimeout);
    try {
      return await _queryOn(conn);
    } finally {
      await conn.close();
    }
  });

  /// Hỏi TỪNG câu, chấp nhận trả lời lẻ: nhiều máy giá rẻ chỉ hiểu `DLE EOT 4`.
  /// Cuộn giấy hỏi trước — không trả lời thì máy không hỗ trợ, khỏi hỏi tiếp.
  Future<PaperStatus> _queryOn(_TcpConn conn) async {
    try {
      conn.drain();
      final roll = await conn.ask(4, statusTimeout);
      if (roll == null) return PaperStatus.unknown;
      final offline = await conn.ask(2, statusTimeout);
      return PaperStatus.parse(roll: roll, offline: offline);
    } on SocketException {
      return PaperStatus.unknown;
    }
  }
}

/// Một kết nối TCP kèm bộ đệm nhận (để đọc câu trả lời trạng thái).
class _TcpConn {
  _TcpConn(this.socket) {
    _sub = socket.listen(
      (data) {
        _rx.addAll(data);
        _signal();
      },
      onError: (_) => _signal(),
      onDone: () {
        _closed = true;
        _signal();
      },
      cancelOnError: false,
    );
  }

  static Future<_TcpConn> open(String host, int port, Duration timeout) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _TcpConn(socket);
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _sub;
  final List<int> _rx = [];
  Completer<void>? _waiter;
  bool _closed = false;

  void _signal() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// Bỏ byte cũ còn trong bộ đệm (VD máy in tự gửi trạng thái).
  void drain() => _rx.clear();

  /// Gửi `DLE EOT n` và chờ MỘT byte trạng thái hợp lệ; `null` khi hết giờ.
  Future<int?> ask(int n, Duration timeout) async {
    socket.add(EscPosCommands.realtimeStatus(n));
    await socket.flush();
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final i = _rx.indexWhere(PaperStatus.isStatusByte);
      if (i >= 0) {
        final b = _rx[i];
        _rx.removeRange(0, i + 1);
        return b;
      }
      _rx.clear();
      final left = deadline.difference(DateTime.now());
      if (_closed || left <= Duration.zero) return null;
      final w = _waiter = Completer<void>();
      await w.future.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() async {
    try {
      await socket.flush();
      await socket.close();
    } catch (_) {
      socket.destroy();
    }
    await _sub.cancel();
  }
}
