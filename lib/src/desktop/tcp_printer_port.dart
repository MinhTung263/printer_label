import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'dirty_store.dart';
import 'escpos_commands.dart';
import 'lan_printer_scanner.dart';
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

  /// Máy in bận (từ chối kết nối — đang phục vụ máy khác): CHƯA gửi byte nào
  /// nên thử lại an toàn sau các khoảng nghỉ này.
  static List<Duration> busyRetries = const [
    Duration(milliseconds: 300),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1200),
  ];

  /// Máy in không trả lời hỏi trạng thái (nhiều máy giá rẻ): khỏi hỏi lại trong
  /// [noStatusFor] — mỗi phiếu đỡ chờ [statusTimeout].
  /// Biên độ ngẫu nhiên (ms) cộng vào mỗi lần chờ thử lại khi máy in bận.
  static int retryJitterMs = 350;
  static final Random _jitter = Random();

  /// Số lần thử lại khi máy in BẬN (đang in cho thiết bị khác, từ chối socket này). Một bill chỉ in vài giây nên
  /// chờ thêm gần như chắc chắn tới lượt; giãn dần nhưng chặn trên [busyMaxDelay], ngẫu nhiên cộng thêm để các
  /// thiết bị cùng bị từ chối không thử lại đồng loạt. Tổng tối đa ~15s, dưới hạn giữ hàng đợi của [PortQueue].
  static int busyMaxAttempts = 12;
  static Duration busyMaxDelay = const Duration(milliseconds: 1500);

  /// Chờ sau khi gửi phần xả để biết máy in có TỪ CHỐI socket này không (máy in nhiệt chỉ in MỘT socket, socket khác
  /// bị reset ngay khi có byte tới). Phần xả vô hại nên bị từ chối ở bước này thì thử lại an toàn, chưa mất byte
  /// bill nào.
  static Duration busyProbe = const Duration(milliseconds: 30);

  /// Sổ "máy in có thể đang dở một lệnh ảnh", LƯU BỀN xuống đĩa. Lần gửi trước đứt GIỮA CHỪNG (rút dây, mất Wi-Fi,
  /// Agent bị tắt / crash) thì máy còn chờ nốt phần ảnh và NUỐT phiếu kế tiếp làm dữ liệu ảnh -> ký tự lạ, giấy dài.
  /// Trước đây chỉ là `Set` trong bộ nhớ nên Agent khởi động lại là mất. Ghi sổ TRƯỚC byte đầu, chỉ xoá khi gửi xong.
  static final DirtyStore dirtyStore = DirtyStore();

  /// 16384 byte 0x00 (lấp MỌI phần ảnh còn thiếu của một dải `GS v 0`: tối đa 128 dòng x 128 byte) + `ESC @`.
  /// Trước đây chỉ 1024 byte nên dải dở còn thiếu nhiều hơn vẫn nuốt phiếu sau. 0x00 thừa là lệnh rỗng, máy sạch bỏ qua.
  static final Uint8List _flushBytes = Uint8List(16384 + 2)
    ..[16384] = 0x1B
    ..[16385] = 0x40;

  /// Lệnh ESC/POS (bắt đầu bằng `ESC @` như [EscPosCommands.receipt] dựng) luôn được xả ở kết nối mới, KHÔNG phụ
  /// thuộc Agent này có biết máy in còn dở hay không: một thiết bị KHÁC (điện thoại, Agent khác) có thể vừa để máy in
  /// dở dang một lệnh ảnh mà sổ của Agent này không hề biết.
  static bool _isEscPos(Uint8List data) =>
      data.length >= 2 && data[0] == 0x1B && data[1] == 0x40;

  static Duration noStatusFor = const Duration(minutes: 10);
  static final Map<String, DateTime> _noStatusUntil = {};

  /// [tspl]: câu hỏi `<ESC>!?` của máy tem — nhớ riêng với câu hỏi `DLE EOT` (một máy tem
  /// có thể trả lời câu này mà im lặng với câu kia).
  bool _statusUnsupported({bool tspl = false}) {
    final until = _noStatusUntil[tspl ? '$id#tspl' : id];
    return until != null && DateTime.now().isBefore(until);
  }

  Future<_TcpConn> _open() async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _TcpConn.open(host, port, connectTimeout);
      } on SocketException catch (e) {
        if (!LanPrinterScanner.isRefused(e) || attempt >= busyRetries.length) {
          rethrow;
        }
        // Ngẫu nhiên thêm 0..350ms: nhiều máy cùng thấy cổng bận không thử lại ĐÚNG cùng lúc
        // (lại đụng nhau).
        await Future<void>.delayed(
          busyRetries[attempt] +
              Duration(milliseconds: _jitter.nextInt(retryJitterMs)),
        );
      }
    }
  }

  /// [tsplStatus]: hỏi trạng thái bằng `<ESC>!?` (máy tem TSPL) thay vì `DLE EOT` (máy hoá
  /// đơn) — hết giấy / mở nắp / kẹt giấy / hết mực thì KHÔNG gửi (nơi gọi giữ lệnh, tự in
  /// khi máy sẵn sàng); máy không trả lời thì in như thường.
  @override
  Future<void> send(
    Uint8List data, {
    bool checkStatus = true,
    bool tsplStatus = false,
  }) => PortQueue.run(id, () async {
    for (var attempt = 0; ; attempt++) {
      final conn = await _open();
      try {
        await _sendOn(
          conn,
          data,
          checkStatus: checkStatus,
          tsplStatus: tsplStatus,
        );
        await conn.close();
        // Đóng êm xong (FIN sau khi toàn bộ dữ liệu đã đẩy đi): mới xoá sổ "in dở".
        dirtyStore.clear(id);
        return;
      } on _PrinterBusy {
        // Máy in đang in cho thiết bị khác: CHƯA gửi byte bill nào, thử lại an toàn.
        if (attempt >= busyMaxAttempts) throw const PrinterBusyException();
        final base = Duration(
          milliseconds: min(
            busyMaxDelay.inMilliseconds,
            400 * (1 << min(attempt, 4)),
          ),
        );
        // Ngẫu nhiên 0.7-1.4 lần: nhiều thiết bị cùng bị từ chối không thử lại ĐÚNG cùng lúc.
        await Future<void>.delayed(base * (0.7 + _jitter.nextDouble() * 0.7));
      } finally {
        await conn.close();
      }
    }
  });

  /// [tsplStatus]: hỏi trạng thái bằng `<ESC>!?` (máy tem TSPL) thay vì `DLE EOT` (máy hoá
  /// đơn) — hết giấy / mở nắp / kẹt giấy / hết mực thì KHÔNG gửi (nơi gọi giữ lệnh, tự in
  /// khi máy sẵn sàng); máy không trả lời thì in như thường.
  Future<void> _sendOn(
    _TcpConn conn,
    Uint8List data, {
    required bool checkStatus,
    required bool tsplStatus,
  }) async {
    if (checkStatus && !_statusUnsupported(tspl: tsplStatus)) {
      final status = tsplStatus
          ? await _queryTsplOn(conn)
          : await _queryOn(conn);
      if (status == PaperStatus.unknown) {
        _noStatusUntil[tsplStatus ? '$id#tspl' : id] = DateTime.now().add(
          noStatusFor,
        );
      }
      if (status.blocksPrinting) throw PrinterStatusException(status);
    }
    // Xả bộ đệm máy in hoá đơn trước khi in (máy tem TSPL không cần): lệnh ESC/POS luôn xả; lệnh khác chỉ khi sổ
    // báo lần trước dở.
    if (!tsplStatus && (_isEscPos(data) || dirtyStore.isDirty(id))) {
      conn.socket.add(_flushBytes);
      await conn.socket.flush();
      // Phần xả vô hại nên cũng là "thăm dò": máy in bận (đang in cho thiết bị khác) reset socket này ngay khi có byte
      // tới -> chưa gửi byte bill nào, nơi gọi thử lại.
      await Future<void>.delayed(busyProbe);
      if (conn.peerGone) throw const _PrinterBusy();
    }
    // Ghi sổ TRƯỚC byte đầu của bill (ghi đĩa ngay): Agent bị kill / mất điện giữa chừng thì lần sau vẫn biết.
    dirtyStore.mark(id);
    var sent = 0;
    try {
      for (var off = 0; off < data.length; off += chunkSize) {
        final end = off + chunkSize < data.length
            ? off + chunkSize
            : data.length;
        conn.socket.add(Uint8List.sublistView(data, off, end));
        await conn.socket.flush();
        sent = end;
      }
    } on SocketException catch (e) {
      // Giữ cờ: lần gửi sau xả trước. Đã gửi một phần bill thì phiếu CÓ THỂ ra dở: báo bằng lỗi riêng để nơi gọi KHÔNG
      // tự in lại (sẽ ra hai bản).
      if (sent > 0) throw PrinterSendInterrupted(e, sent);
      rethrow;
    }
  }

  /// Gửi [request] rồi chờ máy in trả lời (tối đa [timeout]); `null` khi không có
  /// byte nào. Dùng để dò ngôn ngữ máy in ([PrinterLanguageProbe]).
  Future<Uint8List?> exchange(
    Uint8List request, {
    Duration timeout = const Duration(milliseconds: 700),
  }) => PortQueue.run(id, () async {
    final conn = await _open();
    try {
      conn.drain();
      conn.socket.add(request);
      await conn.socket.flush();
      return await conn.readAny(timeout);
    } finally {
      await conn.close();
    }
  });

  /// Hỏi lần lượt [requests] trên MỘT kết nối (xếp hàng cùng các việc khác tới máy này):
  /// máy in LAN giá rẻ chỉ nhận một kết nối, mở kết nối mới cho từng câu hỏi dễ đụng
  /// nhau / bị từ chối. Câu trả lời theo đúng thứ tự; `null` = không trả lời câu đó.
  Future<List<Uint8List?>> exchangeMany(
    List<Uint8List> requests, {
    Duration timeout = const Duration(milliseconds: 700),
  }) => PortQueue.run(id, () async {
    final conn = await _open();
    try {
      final replies = <Uint8List?>[];
      for (final request in requests) {
        conn.drain();
        conn.socket.add(request);
        await conn.socket.flush();
        replies.add(await conn.readAny(timeout));
      }
      return replies;
    } finally {
      await conn.close();
    }
  });

  @override
  Future<PaperStatus> queryStatus() => PortQueue.run(id, () async {
    final conn = await _open();
    try {
      return await _queryOn(conn);
    } finally {
      await conn.close();
    }
  });

  /// Hỏi `<ESC>!?` (máy tem TSPL) và đọc MỘT byte trạng thái.
  Future<PaperStatus> _queryTsplOn(_TcpConn conn) async {
    try {
      conn.drain();
      final reply = await conn.askTspl(statusTimeout);
      return reply == null ? PaperStatus.unknown : PaperStatus.parseTspl(reply);
    } on SocketException {
      return PaperStatus.unknown;
    }
  }

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
      onError: (Object e) {
        _error = e;
        _signal();
      },
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
  Object? _error;
  bool _closing = false;

  /// Máy in đã đóng / reset kết nối này (VD từ chối vì đang in cho thiết bị khác).
  bool get peerGone => _closed || _error != null;

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

  /// Gửi `<ESC>!?` và chờ byte trạng thái TSPL đầu tiên; `null` khi hết giờ / byte lạ.
  Future<int?> askTspl(Duration timeout) async {
    socket.add(EscPosCommands.tsplStatus);
    await socket.flush();
    final reply = await readAny(timeout);
    if (reply == null || reply.isEmpty) return null;
    final b = reply.first;
    return PaperStatus.isTsplStatusByte(b) ? b : null;
  }

  /// Chờ có byte nào đó trả về (tối đa [timeout]); trả hết byte đang có.
  Future<Uint8List?> readAny(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_rx.isEmpty) {
      final left = deadline.difference(DateTime.now());
      if (_closed || left <= Duration.zero) return null;
      final w = _waiter = Completer<void>();
      await w.future.timeout(left, onTimeout: () {});
    }
    // Chờ thêm chút để gom hết gói trả lời.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final out = Uint8List.fromList(_rx);
    _rx.clear();
    return out;
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      await socket.flush();
      await socket.close();
    } catch (_) {
      socket.destroy();
    }
    await _sub.cancel();
  }
}

/// Máy in từ chối kết nối này vì đang in cho thiết bị khác (chưa gửi byte bill nào).
class _PrinterBusy implements Exception {
  const _PrinterBusy();
}

/// Máy in BẬN mãi (đang in cho thiết bị khác, từ chối kết nối) sau [TcpPrinterPort.busyMaxAttempts] lần thử: CHƯA gửi
/// byte bill nào nên nơi gọi có thể thử lại sau. Vẫn là [SocketException] để mã cũ bắt như trước.
class PrinterBusyException implements SocketException {
  const PrinterBusyException();

  @override
  String get message => 'Máy in đang bận (từ chối kết nối)';

  @override
  OSError? get osError => null;

  @override
  InternetAddress? get address => null;

  @override
  int? get port => null;

  @override
  String toString() => 'PrinterBusyException: $message';
}

/// Đứt kết nối khi ĐANG gửi bill (đã gửi [bytesSent] byte): phiếu có thể đã ra một phần. Nơi gọi KHÔNG nên tự in lại
/// (có thể ra hai bản). Vẫn là [SocketException] để mã cũ bắt như trước.
class PrinterSendInterrupted implements SocketException {
  const PrinterSendInterrupted(this.cause, this.bytesSent);

  final SocketException cause;
  final int bytesSent;

  @override
  String get message =>
      'Đứt kết nối khi đang gửi ($bytesSent byte đã gửi): ${cause.message}';

  @override
  OSError? get osError => cause.osError;

  @override
  InternetAddress? get address => cause.address;

  @override
  int? get port => cause.port;

  @override
  String toString() => 'PrinterSendInterrupted: $message';
}
