package com.printer.printer_label

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSConst
import net.posprinter.POSPrinter

/// Lớp tiện ích in nhiệt (ESC/POS) cho Flutter plugin.
/// build và gửi lệnh ESC/POS
class PrinterThermal {
    companion object {
        // Khóa gửi RIÊNG cho TỪNG máy in (theo đối tượng IDeviceConnection).
        // SDK POSConnect có hàng đợi + luồng gửi riêng cho mỗi connection, nên 2 máy
        // KHÁC nhau in được song song. Chỉ cần tuần tự hóa các lần gửi trên CÙNG một
        // máy (nhiều chunk/nhiều job vào chung 1 connection) để byte không chèn vào
        // nhau gây in ra ký tự rác. Nhờ vậy in cùng lúc 2 máy không phải đợi nhau.
        @JvmStatic
        val sendLocks = java.util.concurrent.ConcurrentHashMap<IDeviceConnection, Any>()

        // Khóa TOÀN CỤC riêng cho Bluetooth Classic — dùng chung cho MỌI connection
        // loại BT, kể cả máy in tích hợp (Sunmi/iMin/Pax connect qua Bluetooth nội bộ,
        // xem BluetoothPrinterManager.autoConnectBuiltIn). Lý do: built-in và một máy
        // Bluetooth ngoài tuy là 2 IDeviceConnection khác nhau nhưng CÙNG đi qua một
        // chip Bluetooth vật lý duy nhất của máy — nếu 2 job in Bluetooth chạy đúng
        // lúc (ví dụ printWidgetToDevices gọi Future.wait in built-in + máy ngoài cùng
        // lúc), tranh chấp ở tầng radio khiến dữ liệu của máy này bị đẩy nhầm sang máy
        // kia: built-in im lặng không ra giấy, còn máy ngoài lại nhận đủ dữ liệu của cả
        // hai lần in nên in ra 2 bản. Ép mọi lần ghi Bluetooth (dù built-in hay ngoài)
        // chạy tuần tự loại bỏ hoàn toàn khả năng ghi chồng lấn đó. LAN/USB không dùng
        // khóa này nên vẫn in song song với nhau và với Bluetooth như cũ.
        @JvmStatic
        val bluetoothGlobalLock = Any()

        @JvmStatic
        fun lockFor(conn: IDeviceConnection): Any {
            if (conn.getConnectType() == POSConnect.DEVICE_TYPE_BLUETOOTH) {
                return bluetoothGlobalLock
            }
            return sendLocks.getOrPut(conn) { Any() }
        }

        /**
         * Gửi hết [data] theo từng gói [chunkSize] và KIỂM TRA số byte thật sự gửi được.
         *
         * `sendSync` trả về số byte đã gửi, có thể NHỎ HƠN số byte đưa vào khi buffer
         * máy in/socket đầy (hay gặp với đơn dài, ảnh vài chục–trăm KB). Trước đây giá
         * trị trả về bị bỏ qua nên phần dữ liệu thiếu biến mất âm thầm: máy in vẫn đợi
         * cho đủ số byte mà lệnh `GS v 0` khai báo, treo luôn và ăn mất cả lệnh cắt lẫn
         * job in kế tiếp. Ở đây gửi tiếp đúng phần còn lại, và ném lỗi nếu không gửi
         * nổi để lớp trên báo thất bại thay vì báo thành công giả.
         */
        /**
         * Chờ tới khi SDK đã đẩy xong hàng đợi gửi nội bộ của [conn].
         *
         * `POSPrinter`/`TSPLPrinter` (đều kế thừa `net.posprinter.a`) gửi qua
         * `IDeviceConnection.sendData(byte[])` — hàm trả về `void` và BẤT ĐỒNG BỘ: nó chỉ
         * XẾP lệnh vào hàng đợi nội bộ rồi return ngay. Nên `result.success(true)` chạy khi
         * byte CHƯA ra khỏi máy. Hậu quả đã quan sát được:
         *  - In 5 tem chỉ ra 1–2 tem: lệnh in xong ở tầng Dart, socket LAN bị nhả (hoặc job
         *    kế tiếp chen vào) trong khi hàng đợi còn dữ liệu -> phần còn lại bị bỏ.
         *  - In tem mẫu KHÁC lại ra tem của lần in TRƯỚC: dữ liệu cũ còn tồn trong hàng đợi
         *    và được đẩy ra ở lần gửi sau.
         *
         * SDK không có API "đã gửi xong hết", nên ta gửi một byte NUL bằng `sendSync` (đồng
         * bộ) làm HÀNG RÀO: nó phải xếp sau toàn bộ dữ liệu đã queue trước đó, nên khi nó
         * trả về thì phần trước đã ra khỏi máy. NUL bị máy in bỏ qua ở cả TSPL và ESC/POS
         * nên không in thêm gì.
         */
        @JvmStatic
        fun awaitFlush(conn: IDeviceConnection) {
            runCatching { conn.sendSync(byteArrayOf(0x00)) }
        }

        /**
         * Chờ tới khi dữ liệu đã XẾP HÀNG của [conn] thực sự được ghi ra socket/OutputStream.
         *
         * KHÁC [awaitFlush]: `sendSync` ghi THẲNG ra stream, KHÔNG đi qua hàng đợi, nên byte
         * NUL của nó có thể VƯỢT MẶT phần dữ liệu còn nằm chờ trong queue — vừa không chứng
         * minh được hàng đợi đã cạn, vừa chen một byte lạ vào giữa luồng lệnh TSPL đang gửi
         * dở. Với ảnh bitmap (vài chục KB) thì đó đúng là lúc dễ hỏng nhất.
         *
         * Cách đúng theo SDK (net.posprinter.a.c): luồng consumer lấy từng gói khỏi hàng đợi,
         * ghi ra stream, RỒI mới gọi `IStatusCallback.receive(soByteDaGhi)`. Vậy callback là
         * tín hiệu "gói này đã ra khỏi máy". Ta đăng ký callback, chờ nó kêu, rồi gỡ ra.
         *
         * Có timeout để không treo vĩnh viễn nếu máy in rút dây/mất điện giữa chừng: quá hạn
         * thì trả về và để lớp trên xử lý như lỗi gửi bình thường.
         *
         * timeoutMs = 500: SDK (net.posprinter.a.c$a, đã decompile bytecode để xác nhận)
         * TỰ GIỚI HẠN tần suất gọi callback — nếu lần gọi trước cách chưa quá 2000ms thì gói
         * kế được ghi ra stream thành công NHƯNG SDK ÂM THẦM BỎ QUA việc gọi
         * `IStatusCallback.receive()` cho gói đó (không có API public nào khác để biết hàng
         * đợi đã cạn). Với in liên tiếp nhiều tem (mỗi tem ghi nhanh hơn 2s), khoảng phân nửa
         * số tem sẽ KHÔNG BAO GIỜ nhận được callback dù đã gửi xong -> timeout sẽ bị "ăn đủ"
         * ở đúng các tem đó. Vì vậy timeout càng ngắn càng đỡ lãng phí, miễn còn đủ cho
         * callback HỢP LỆ (tem không bị throttle) kịp về: bitmap tem (vài chục KB) ghi ra
         * socket LAN bình thường mất dưới 100ms, 500ms đã dư dả cho cả mạng chậm. Từng thử
         * 15000ms (in 5 tem mất cả phút) rồi 3000ms (vẫn còn ~6s lãng phí cho 2-3 tem bị
         * throttle) trước khi chốt 500ms.
         */
        @JvmStatic
        fun awaitLabelSent(conn: IDeviceConnection, timeoutMs: Long = 300L) {
            // Socket LAN tự quản: không bị throttle callback như SDK nên chờ được tới khi
            // gửi hết THẬT (mạng yếu có thể mất vài giây), và biết được là đã lỗi — trước
            // đây tem gửi lỗi vẫn bị báo in thành công.
            if (conn is LanSocketConnection) {
                if (!conn.awaitIdle(LAN_LABEL_SEND_TIMEOUT_MS)) {
                    Log.w("TSPL_FLUSH", "Quá ${LAN_LABEL_SEND_TIMEOUT_MS}ms chưa gửi xong tem qua LAN")
                }
                if (!conn.isConnect) {
                    throw java.io.IOException(conn.lastErrorMessage ?: "Mất kết nối tới máy in khi đang gửi tem")
                }
                return
            }
            val latch = java.util.concurrent.CountDownLatch(1)
            // Giữ tham chiếu MẠNH tới callback trong suốt lúc chờ. SDK chỉ giữ nó bằng
            // WeakReference (xem setSendCallback), nên nếu để lambda làm đối tượng tạm thì
            // GC có thể thu nó trước khi luồng consumer kịp gọi -> latch không bao giờ đếm
            // lùi và ta chờ tới hết timeout ở MỌI tem (in cực chậm mà vẫn không an toàn).
            val callback = net.posprinter.posprinterface.IStatusCallback { latch.countDown() }
            try {
                conn.setSendCallback(callback)
                if (!latch.await(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                    Log.w("TSPL_FLUSH", "Quá $timeoutMs ms không thấy xác nhận gửi tem")
                }
            } catch (e: Exception) {
                Log.w("TSPL_FLUSH", "Không chờ được xác nhận gửi: ${e.message}")
            } finally {
                // Gỡ callback để không giữ tham chiếu sang lần in sau.
                runCatching { conn.setSendCallback(null) }
                // Chạm vào `callback` sau khi chờ xong để chắc chắn nó còn sống tới đây,
                // không bị JIT coi là rác sớm.
                callback.hashCode()
            }
        }

        /**
         * Số lần thử lại CHỈ cho gói đầu tiên (offset 0) khi `sendSync` trả về <= 0.
         *
         * Máy in vừa kết nối xong (đặc biệt USB, ngay khi app mới mở) có thể đã báo
         * `CONNECT_SUCCESS` trước khi endpoint thực sự sẵn sàng nhận ghi -> gói đầu
         * tiên gửi thất bại ngay tại byte 0, các lần in sau đó lại bình thường. Đây là
         * cửa sổ "chưa kịp warm up" của SDK/driver, không phải mất kết nối thật, nên
         * retry ngắn ở ĐÚNG điểm này là hợp lý. Từ gói thứ 2 trở đi không retry nữa:
         * lỗi giữa chừng nghĩa là kết nối đã chết thật (rút dây, đầy buffer thật) và
         * cần ném lỗi ngay để lớp trên biết mà báo thất bại, không âm thầm nuốt lỗi.
         */
        // 3 lần/80ms (~240ms) không đủ trên một số thiết bị: cửa sổ "chưa sẵn sàng
        // ghi" của driver USB sau CONNECT_SUCCESS có thể kéo dài cả giây. Tăng lên
        // 8 lần, backoff tuyến tính 150ms/lần (150+300+450+...+1200 ≈ 2.4s tối đa)
        // để đủ chờ những thiết bị chậm nhất mà không giữ UI treo mãi khi kết nối
        // đã chết thật (rút dây) — trường hợp đó sendSync tiếp tục trả <=0 tới hết
        // số lần thử rồi mới ném lỗi như cũ.
        private const val FIRST_CHUNK_MAX_RETRY = 8

        /** Hạn chờ một tem gửi xong qua LAN tự quản (watchdog ghi tự cắt sớm hơn nếu kẹt). */
        private const val LAN_LABEL_SEND_TIMEOUT_MS = 30_000L
        private const val FIRST_CHUNK_RETRY_BASE_DELAY_MS = 150L

        /**
         * Gửi lại gói đầu tiên [chunk] khi `sendSync` ban đầu trả về <= 0, với backoff
         * TUYẾN TÍNH (150, 300, 450, ..., 1200ms — tổng tối đa ~2.4s): lần thử càng
         * muộn thì đợi càng lâu, để đủ cửa sổ cho driver USB chậm nhất mà không delay
         * quá lâu ở retry đầu (thường đã đủ trên máy bình thường). Trả về số byte đã
         * gửi (0 nếu vẫn thất bại sau tất cả các lần thử).
         */
        private fun retryFirstChunkSync(
            sendSync: (ByteArray) -> Int,
            chunk: ByteArray,
            logTag: String
        ): Int {
            var sent = 0
            for (attempt in 1 until FIRST_CHUNK_MAX_RETRY) {
                val delay = FIRST_CHUNK_RETRY_BASE_DELAY_MS * attempt
                Log.w(logTag, "Gói đầu tiên gửi thất bại (lần $attempt), thử lại sau ${delay}ms...")
                Thread.sleep(delay)
                sent = sendSync(chunk)
                if (sent > 0) break
            }
            return sent
        }

        @JvmStatic
        fun sendAllSync(conn: IDeviceConnection, data: ByteArray, chunkSize: Int) {
            var offset = 0
            while (offset < data.size) {
                val count = Math.min(chunkSize, data.size - offset)
                val chunk = data.copyOfRange(offset, offset + count)

                var sent = conn.sendSync(chunk)
                // Retry gói đầu là để chờ driver USB "warm up". Socket LAN tự quản trả -1 nghĩa
                // là kết nối đã chết thật (đã đóng) — thử lại chỉ tốn ~2.4s vô ích.
                if (sent <= 0 && offset == 0 && conn !is LanSocketConnection) {
                    sent = retryFirstChunkSync(conn::sendSync, chunk, "PRINT_SEND")
                }

                if (sent <= 0) {
                    val reason = (conn as? LanSocketConnection)?.lastErrorMessage
                    throw java.io.IOException(
                        "Gửi dữ liệu tới máy in thất bại tại byte $offset/${data.size} " +
                            (reason?.let { "($it)." }
                                ?: "(sendSync trả về $sent). Máy in có thể đã mất kết nối hoặc đầy buffer.")
                    )
                }
                // sendSync có thể gửi thiếu -> chỉ tiến đúng số byte đã gửi được.
                offset += sent
            }
        }

        /**
         * Hỏi cảm biến giấy/nắp của máy in trên CHÍNH kết nối sắp dùng để in, bằng
         * lệnh thời gian thực `DLE EOT 2` (nguyên nhân offline) và `DLE EOT 4` (cảm
         * biến cuộn giấy). Lệnh thời gian thực được máy in trả lời cả khi đang
         * offline vì hết giấy / mở nắp — đúng lúc cần hỏi.
         *
         * Chỉ hỏi qua LAN (socket tự quản) và USB. Bluetooth không hỏi: nhiều máy BT
         * không trả lời, mỗi lần in sẽ phí trọn thời gian chờ.
         *
         * Không trả lời / trả lời sai định dạng -> [PaperStatus.UNKNOWN]: vẫn in như
         * cũ, không chặn máy in không hỗ trợ lệnh này.
         */
        @JvmStatic
        fun queryPaperStatus(conn: IDeviceConnection): PaperStatus {
            val isLan = conn is LanSocketConnection
            if (!isLan && conn.getConnectType() != POSConnect.DEVICE_TYPE_USB) return PaperStatus.UNKNOWN
            // LAN tính thêm thời gian khứ hồi trên Wi-Fi đông; USB trả lời gần như tức thì.
            val timeoutMs = if (isLan) 800 else 300
            return try {
                // Bỏ byte cũ còn tồn trong bộ đệm nhận (VD máy in tự gửi trạng thái),
                // nếu không sẽ đọc nhầm thành câu trả lời.
                for (i in 0 until 4) {
                    if (conn.readSync(1) == null) break
                }
                // Hỏi TỪNG câu và chấp nhận trả lời lẻ: nhiều máy giá rẻ chỉ hiểu DLE EOT 4.
                // Cuộn giấy hỏi trước — không trả lời thì máy không hỗ trợ, khỏi hỏi tiếp.
                val roll = askRealtimeStatus(conn, 4, timeoutMs) ?: return PaperStatus.UNKNOWN
                val offline = askRealtimeStatus(conn, 2, timeoutMs)
                when {
                    offline != null && (offline and 0x04) != 0 -> PaperStatus.COVER_OPEN
                    (roll and 0x60) != 0 || (offline != null && (offline and 0x20) != 0) -> PaperStatus.PAPER_END
                    (roll and 0x0C) != 0 -> PaperStatus.NEAR_END
                    else -> PaperStatus.OK
                }
            } catch (e: Exception) {
                Log.w("PAPER_STATUS", "Không hỏi được trạng thái giấy: ${e.message}")
                PaperStatus.UNKNOWN
            }
        }

        /**
         * Gửi `DLE EOT n` và chờ MỘT byte trạng thái hợp lệ (bit 1, bit 4 = 1; bit 0,
         * bit 7 = 0). Trả null nếu hết [timeoutMs] mà không có.
         */
        private fun askRealtimeStatus(conn: IDeviceConnection, n: Int, timeoutMs: Int): Int? {
            if (conn.sendSync(byteArrayOf(0x10, 0x04, n.toByte())) <= 0) return null
            val deadline = System.currentTimeMillis() + timeoutMs
            while (true) {
                val left = (deadline - System.currentTimeMillis()).toInt()
                if (left <= 0) return null
                val data = conn.readSync(left) ?: continue
                data.map { it.toInt() and 0xFF }.firstOrNull { (it and 0x93) == 0x12 }?.let { return it }
            }
        }
    }

    enum class PaperStatus { OK, NEAR_END, PAPER_END, COVER_OPEN, UNKNOWN }

    /** Lỗi do trạng thái máy in (hết giấy, mở nắp) — mang mã lỗi riêng lên Dart. */
    class PrinterStatusException(val code: String, message: String) : Exception(message)

    fun printImageESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result,
        isTargetBuiltIn: Boolean = false
    ) {
        val type = call.argument<String>("type")
        if (type != "ESC") {
            result.success(false)
            return
        }
        
        // Chạy toàn bộ quá trình in trên luồng nền để tránh khóa UI
        kotlin.concurrent.thread {
            try {
                val image: ByteArray? = call.argument<ByteArray>("image")
                if (image == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Image data is null", null)
                    }
                    return@thread
                }
                val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size)
                if (bitmap == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Failed to decode bitmap image", null)
                    }
                    return@thread
                }
                val isBluetooth = curConnect.getConnectType() == POSConnect.DEVICE_TYPE_BLUETOOTH

                // USB từng đi qua `printBitmap` của SDK (để SDK tự dựng + gửi lệnh ảnh, tự
                // chia dải nên đơn dài in tốt). Nhưng với `quantity` > 1, lặp
                // `repeat(copies) { initializePrinter()...; awaitLabelSent() }` KHÔNG an
                // toàn: `awaitLabelSent` chỉ đợi ĐÚNG MỘT callback (một gói đã ghi ra
                // stream), trong khi `printBitmap` có thể chia một bitmap thành NHIỀU gói
                // nội bộ. Bản kế tiếp gọi `initializePrinter()` (ESC @, reset máy in) trong
                // lúc phần đuôi của bản trước vẫn còn nằm trong hàng đợi SDK -> phần đó bị
                // hủy, chỉ tờ cuối cùng in ra trọn vẹn (in 3 tờ ra 1 tờ qua USB).
                //
                // Giờ USB đi chung đường raster thủ công + `sendAllSync` bên dưới, giống
                // LAN/BLE: dữ liệu `copies` bản được NỐI SẴN thành một khối rồi gửi ĐỒNG BỘ
                // thật trong một lần, không còn khoảng hở giữa các bản để lệnh reset chen
                // vào. `getEscPosRasterBytes` đã tự chia dải 128 dòng nên đơn dài vẫn an
                // toàn qua đường này.

                // Dựng dữ liệu ảnh thô (GS v 0) sử dụng bộ nhị phân hóa chất lượng cao (threshold 200) để giữ nguyên chất lượng ảnh gốc của Flutter
                val rasterBytes = getEscPosRasterBytes(bitmap)
                bitmap.recycle()

                val stream = java.io.ByteArrayOutputStream()
                
                // 1. Initialize printer (ESC @)
                stream.write(byteArrayOf(0x1B, 0x40))
                
                // 2. Set alignment Center (ESC a 1)
                stream.write(byteArrayOf(0x1B, 0x61, 0x01))
                
                // 3. Write raster image data
                stream.write(rasterBytes)
                
                // 4. Feed 5 lines (LF)
                stream.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A, 0x0A))
                
                // 5. Cut paper (GS V 66 1)
                stream.write(byteArrayOf(0x1D, 0x56, 0x42, 0x01))
                
                val oneCopy = stream.toByteArray()

                // In [quantity] bản trong MỘT lời gọi: nối dữ liệu các bản lại rồi gửi
                // trong CÙNG một khối synchronized.
                //
                // Trước đây tầng Dart lặp `for (quantity)` và gọi print nhiều lần, nên giữa
                // hai bản có khoảng trống không job nào giữ socket -> với máy in LAN đang bật
                // chế độ nhả socket, socket bị đóng ngay giữa các bản và bản kế phải mở lại,
                // đụng đúng socket chưa giải phóng hẳn ("Máy in đang bận, thử lại sau
                // 400ms..."), làm in chậm và có bản không ra. Gộp ở đây thì socket được giữ
                // liên tục từ bản đầu tới bản cuối.
                val copies = (call.argument<Int>("quantity") ?: 1).coerceAtLeast(1)
                val allBytes = if (copies == 1) {
                    oneCopy
                } else {
                    val buf = java.io.ByteArrayOutputStream(oneCopy.size * copies)
                    repeat(copies) { buf.write(oneCopy) }
                    buf.toByteArray()
                }

                // Tuần tự hóa việc gửi TRÊN CÙNG máy này (khóa theo connection).
                // Các máy khác dùng khóa khác nên vẫn in song song, không đợi nhau.
                synchronized(lockFor(curConnect)) {
                    // Hết giấy / mở nắp: KHÔNG gửi phiếu. Nhiều máy vẫn nhận dữ liệu vào bộ
                    // nhớ rồi in khi thay giấy xong -> phiếu ra trễ, nhân viên đã in lại
                    // thì ra 2 phiếu. Báo lỗi ngay để người dùng xử lý rồi in lại.
                    when (queryPaperStatus(curConnect)) {
                        PaperStatus.PAPER_END -> throw PrinterStatusException(
                            "PRINTER_OUT_OF_PAPER", "Máy in hết giấy"
                        )
                        PaperStatus.COVER_OPEN -> throw PrinterStatusException(
                            "PRINTER_COVER_OPEN", "Máy in đang mở nắp"
                        )
                        else -> Unit
                    }
                    if (isBluetooth && !isTargetBuiltIn) {
                        // Cấu hình vừa tầm cân bằng cho máy in Bluetooth ngoài: Gói 120 bytes, delay 4ms, nghỉ 80ms mỗi 1500 bytes
                        // chunkSize, Thread.sleep và khoảng nghỉ giữa các gói quyết định: tốc độ in, độ ổn định (lỗi hay không - mất byte), 
                        // độ mượt (có bị giật hay không). 
                        //Thử nhiều lần với các máy in khác nhau, 120/4/1500/80 là cấu hình vừa đủ nhanh vừa ổn định. 
                        //- các máy có bộ đệm cao có thể chậm - đánh đổi độ ổn định cho máy in có bộ đệm thấp
                        val chunkSize = 120
                        var offset = 0
                        var bytesSentInBlock = 0
                        while (offset < allBytes.size) {
                            val count = Math.min(chunkSize, allBytes.size - offset)
                            val chunk = allBytes.copyOfRange(offset, offset + count)

                            var sent = curConnect.sendSync(chunk)
                            if (sent <= 0 && offset == 0) {
                                // Xem giải thích ở sendAllSync(): kết nối vừa mở (lần in đầu
                                // sau khi vào app) có thể báo thành công trước khi sẵn sàng ghi.
                                sent = retryFirstChunkSync(curConnect::sendSync, chunk, "PRINT_SEND")
                            }

                            if (sent <= 0) {
                                throw java.io.IOException(
                                    "Gửi dữ liệu tới máy in Bluetooth thất bại tại byte " +
                                        "$offset/${allBytes.size} (sendSync trả về $sent)."
                                )
                            }
                            // Tiến theo số byte THẬT SỰ gửi được, không phải số muốn gửi.
                            offset += sent
                            bytesSentInBlock += sent

                            Thread.sleep(4)
                            if (bytesSentInBlock >= 1500) {
                                Thread.sleep(80)
                                bytesSentInBlock = 0
                            }
                        }
                    } else {
                        // USB/LAN/máy in tích hợp: cũng phải chia gói. Gửi cả cục cho đơn
                        // dài (ảnh vài chục–trăm KB) làm tràn buffer máy in/socket:
                        // sendSync chỉ gửi được một phần, phần còn lại bị mất. Máy in vẫn
                        // đợi cho đủ số byte mà lệnh GS v 0 đã khai báo nên treo luôn —
                        // ăn mất cả lệnh cắt và job in kế tiếp.
                        // Gói 4KB lớn hơn Bluetooth nhiều nên vẫn nhanh, không cần sleep.
                        sendAllSync(curConnect, allBytes, 4096)
                    }
                }

                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            } catch (e: Exception) {
                val code = (e as? PrinterStatusException)?.code ?: "PRINT_ERROR"
                Handler(Looper.getMainLooper()).post {
                    result.error(code, e.message, null)
                }
            }
        }
    }

    private fun getEscPosRasterBytes(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val widthBytes = (width + 7) / 8

        val stream = java.io.ByteArrayOutputStream()

        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // Chia ảnh thành nhiều DẢI, mỗi dải là MỘT lệnh `GS v 0` riêng.
        //
        // Trước đây cả bill dài được nhồi vào một lệnh `GS v 0` duy nhất. Đơn ngắn thì
        // chạy tốt, nhưng đơn dài sinh ảnh cao hàng nghìn dòng — vượt giới hạn chiều cao
        // mỗi lệnh raster của máy in (máy Epson thường chỉ nhận vài trăm dòng/lệnh). Khi
        // vượt, máy in hủy chế độ raster và diễn giải các byte ảnh còn lại thành VĂN BẢN,
        // nên giấy ra đầy ký tự rác và không cắt.
        //
        // 128 dòng/dải nằm an toàn dưới giới hạn của mọi model phổ biến; các dải in liền
        // nhau nên ảnh vẫn liền mạch, không có khoảng trắng chen vào.
        val bandHeight = 128

        var y0 = 0
        while (y0 < height) {
            val bandRows = Math.min(bandHeight, height - y0)

            // GS v 0 m xL xH yL yH — yL/yH là chiều cao của DẢI này, luôn <= 128 nên
            // không bao giờ tràn 2 byte.
            stream.write(
                byteArrayOf(
                    0x1D, 0x76, 0x30, 0x00,
                    (widthBytes % 256).toByte(), (widthBytes / 256).toByte(),
                    (bandRows % 256).toByte(), (bandRows / 256).toByte()
                )
            )

            for (y in y0 until y0 + bandRows) {
                for (xByte in 0 until widthBytes) {
                    var byteVal = 0
                    for (bit in 0 until 8) {
                        val x = xByte * 8 + bit
                        if (x < width) {
                            val pixel = pixels[y * width + x]
                            val alpha = (pixel shr 24) and 0xff
                            if (alpha > 50) {
                                val red = (pixel shr 16) and 0xff
                                val green = (pixel shr 8) and 0xff
                                val blue = pixel and 0xff
                                val gray = (0.299 * red + 0.587 * green + 0.114 * blue).toInt()
                                // Ngưỡng 200 — KHÔNG hạ về 128 (xem lịch sử: 128 gây in mờ).
                                //
                                // Đầu in nhiệt chỉ có 1 bit: cháy hoặc trắng, không có mức xám.
                                // Chữ do Flutter render là anti-alias nên mỗi nét gồm lõi đậm
                                // bọc bởi dải xám. Ngưỡng 200 cho cháy tới xám 199 -> nét đủ dày.
                                // Ngưỡng 128 loại sạch dải 129-199; với cỡ chữ nhỏ dải này chiếm
                                // phần lớn nét nên chỉ còn bộ xương mảnh -> bản in RẤT MỜ (đã
                                // ghi nhận trên máy BLE ở cả iOS và Android).
                                //
                                // Đường raster thủ công này dùng chung cho MỌI loại kết nối
                                // (BLE, USB, LAN, máy in tích hợp), nên đổi ngưỡng ở đây ảnh
                                // hưởng tới bản in trên cả 4 loại.
                                if (gray < 200) {
                                    byteVal = byteVal or (1 shl (7 - bit))
                                }
                            }
                        }
                    }
                    stream.write(byteVal)
                }
            }

            y0 += bandRows
        }

        return stream.toByteArray()
    }

    fun printTextESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val text = call.argument<String>("text") ?: ""
        try {
            synchronized(lockFor(curConnect)) {
                printer.initializePrinter()
                    .printText(text, 0, POSConst.ALIGNMENT_LEFT, 0)
                    .feedLine()
                    .cutHalfAndFeed(1)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printBarcodeESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val printer = POSPrinter(curConnect)
        val code = call.argument<String>("code") ?: ""
        val typeVal = call.argument<String>("type") ?: "128"
        val width = call.argument<Int>("width") ?: 2
        val height = call.argument<Int>("height") ?: 162
        try {
            val type = when (typeVal) {
                "UPCA" -> 65
                "UPCE" -> 66
                "EAN13" -> 67
                "EAN8" -> 68
                "CODE39" -> 69
                "ITF" -> 70
                "CODEBAR" -> 71
                "CODE93" -> 72
                else -> 73
            }
            synchronized(lockFor(curConnect)) {
                printer.initializePrinter()
                    .printBarCode(code, type, width, height, 2)
                    .feedLine()
                    .cutHalfAndFeed(1)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun printQRCodeESC(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        val code = call.argument<String>("code") ?: ""
        val size = call.argument<Int>("size") ?: 8
        try {
            val stream = java.io.ByteArrayOutputStream()
            
            // 1. Initialize printer (ESC @)
            stream.write(byteArrayOf(0x1B, 0x40))
            
            // 2. Set alignment Center (ESC a 1)
            stream.write(byteArrayOf(0x1B, 0x61, 0x01))
            
            // 3. QR Code bytes
            val qrBytes = getQRCodeBytes(code, size)
            stream.write(qrBytes)
            
            // 4. Feed 5 lines (LF)
            stream.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x0A, 0x0A))
            
            // 5. Cut paper (GS V 66 1)
            stream.write(byteArrayOf(0x1D, 0x56, 0x42, 0x01))

            synchronized(lockFor(curConnect)) {
                curConnect.sendData(stream.toByteArray())
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private fun getQRCodeBytes(code: String, size: Int): ByteArray {
        val bytes = code.toByteArray(Charsets.UTF_8)
        val pL = (bytes.size + 3) % 256
        val pH = (bytes.size + 3) / 256
        
        val stream = java.io.ByteArrayOutputStream()
        
        // Set model (Model 2)
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x31, 0x00))
        
        // Set size
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.toByte()))
        
        // Set error correction level (L)
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x44, 0x30))
        
        // Store data
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, pL.toByte(), pH.toByte(), 0x31, 0x50, 0x30))
        stream.write(bytes)
        
        // Print QR code
        stream.write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30))
        
        return stream.toByteArray()
    }

    /** Gửi nguyên [call.bytes] xuống máy in (VD lệnh còi nhận diện máy), không thêm gì. */
    fun sendRawBytes(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        try {
            val bytes = call.argument<ByteArray>("bytes")
            if (bytes == null || bytes.isEmpty()) {
                result.success(false)
                return
            }
            synchronized(lockFor(curConnect)) {
                sendAllSync(curConnect, bytes, bytes.size)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    fun openDrawer(
        call: MethodCall,
        curConnect: IDeviceConnection,
        result: MethodChannel.Result
    ) {
        try {
            val stream = java.io.ByteArrayOutputStream()
            // ESC p 0 25 250 (Pin 2) & ESC p 1 25 250 (Pin 5)
            stream.write(byteArrayOf(0x1B, 0x70, 0x00, 0x19, 0xFA.toByte(), 0x1B, 0x70, 0x01, 0x19, 0xFA.toByte()))
            val bytes = stream.toByteArray()
            synchronized(lockFor(curConnect)) {
                curConnect.sendData(bytes)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }
}