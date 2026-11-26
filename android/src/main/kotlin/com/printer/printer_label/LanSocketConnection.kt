package com.printer.printer_label

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.IPOSListener
import net.posprinter.POSConnect
import net.posprinter.posprinterface.IDataCallback
import net.posprinter.posprinterface.IStatusCallback
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NoRouteToHostException
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Kết nối LAN (TCP 9100) tự quản lý, thay cho cổng Ethernet của SDK `printer-lib-3.2.0`.
 *
 * SDK đặt cứng các thông số không chịu được Wi-Fi đông (dịch ngược `net/posprinter/a/b`,
 * xem docs/IN_LAN_ON_DINH.md mục 5.2):
 *  - `connect(addr, 1000)`: chỉ chờ 1s, mỗi lần thử chỉ kịp gửi ĐÚNG 1 gói SYN (Android
 *    gửi lại SYN sau ~1s). Mất 1 gói hoặc trễ vọt >1s là hỏng, dù mạng vẫn dùng được.
 *  - `setSendBufferSize(512)`: tốc độ gửi tụt theo RTT (~15KB/s ở RTT 300ms).
 *  - Không có timeout ghi: mạng chết khi buffer đầy thì `write` treo tới ~15 phút, giữ
 *    luôn khóa gửi của máy in -> mọi bill sau treo theo.
 *  - `isConnect()` = `Socket.isConnected()`: true mãi kể cả khi máy in đã mất.
 *  - Callback "đã gửi" bị SDK giới hạn 1 lần/2s (xem `awaitLabelSent`).
 *
 * Lớp này cài `IDeviceConnection` nên `POSPrinter`/`TSPLPrinter` của SDK và toàn bộ code
 * in hiện có dùng lại được nguyên vẹn; chỉ thay phần socket.
 */
class LanSocketConnection(context: Context?) : IDeviceConnection {

    /** Lý do kết nối/ghi thất bại — quyết định có nên thử lại và báo gì cho người dùng. */
    enum class Failure {
        /** Không nhận được phản hồi trong CONNECT_TIMEOUT_MS: mạng yếu/mất hoặc máy in tắt. */
        TIMEOUT,
        /** Máy in từ chối/reset: thường do thiết bị khác đang giữ kênh in. */
        BUSY,
        /** Không có đường tới máy in: thiết bị không cùng mạng, Wi-Fi đã rớt. */
        UNREACHABLE,
        /** Đang gửi thì đứt (ghi lỗi hoặc kẹt quá WRITE_STALL_TIMEOUT_MS). */
        SEND_FAILED,
        OTHER,
    }

    companion object {
        private const val TAG = "LAN_SOCKET"
        const val DEFAULT_PORT = 9100

        /** Đủ cho Android gửi SYN 3 lần (t=0, ~1s, ~3s) trước khi bỏ cuộc một lượt thử. */
        const val CONNECT_TIMEOUT_MS = 6_000

        /** Một lượt bắt tay rồi mở socket mới (SYN mới đi ngay) — xem openSocket. Gprinter (đo
         *  được) bỏ qua lượt bắt tay đầu cả khi bình thường, socket mới thì nối trong ~20ms. */
        const val CONNECT_ATTEMPT_MS = 1_200

        /** Một gói (tối đa WRITE_CHUNK) ghi không xong trong khoảng này = coi như kết nối chết. */
        const val WRITE_STALL_TIMEOUT_MS = 10_000L

        /** Chia nhỏ mỗi lần ghi để watchdog đo được "có tiến triển" thay vì chờ cả khối lớn. */
        private const val WRITE_CHUNK = 4096

        /** Watchdog dùng chung: đóng socket khi một lần write bị kẹt (gỡ chặn luồng in). */
        private val watchdog = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "lan-write-watchdog").apply { isDaemon = true }
        }

        private val mainHandler = Handler(Looper.getMainLooper())

    }

    private val appContext = context?.applicationContext

    init {
        PrintDirtyStore.init(appContext)
    }

    @Volatile private var socket: Socket? = null
    @Volatile private var output: OutputStream? = null
    @Volatile private var input: InputStream? = null
    @Volatile private var alive = false
    @Volatile private var connectInfo: String = ""

    /**
     * true từ lúc mở socket tới khi lệnh in ESC/POS đầu tiên lấy đi ([takeFreshSocket]). Lệnh đầu tiên trên
     * socket mới phải xả bộ đệm máy in dù cờ "in dở" của THIẾT BỊ NÀY chưa bật: cờ nằm trên từng điện
     * thoại, mà cửa hàng đông nhân viên thì điện thoại khác có thể vừa để máy in dở một lệnh ảnh.
     */
    @Volatile private var freshSocket = false

    /**
     * Nơi sở hữu đã gọi [close] (nhả sau khi in, hoặc HẾT GIỜ nối ở
     * PrinterLabelPlugin.scheduleConnectTimeout) trong khi [openSocket] có thể vẫn đang thử nối ở
     * luồng khác. Bật cờ này để vòng nối dừng và đóng ngay socket nối được muộn — trước đây socket
     * đó sống tiếp ngoài danh sách kết nối, chiếm kết nối duy nhất của máy in (Gprinter/HPRT
     * không nhận kết nối thứ 2) nên lượt nối lại của chính app thất bại, bill không in.
     * Xoá khi có yêu cầu nối mới (connectSync) hoặc nối lại khi đang gửi ([reopen]).
     */
    @Volatile private var closedByOwner = false

    /** Lý do thất bại gần nhất (null = chưa lỗi). Đọc sau connectSync/sendSync để phân loại. */
    @Volatile var lastFailure: Failure? = null
        private set
    @Volatile var lastErrorMessage: String? = null
        private set

    @Volatile private var connectListener: IConnectListener? = null

    // Hàng đợi cho sendData() (đường POSPrinter/TSPLPrinter của SDK). sendSync() ghi thẳng.
    private val queue = LinkedBlockingQueue<ByteArray>()
    private val pending = AtomicInteger(0)
    @Volatile private var writer: Thread? = null
    private val writeLock = Any()
    private val readLock = Any()
    private val idleLock = Object()
    @Volatile private var sendCallback: IStatusCallback? = null

    private var wifiLock: WifiManager.WifiLock? = null

    // ─── Kết nối ─────────────────────────────────────────────────────────────

    // connect() bất đồng bộ: giống SDK, báo kết quả trên MAIN thread (POSConnect.mainThreadExecutor)
    // — makeConnectListener gọi Toast nên bắt buộc chạy trên main.
    override fun connect(info: String, listener: IConnectListener) {
        connectListener = listener
        closedByOwner = false
        Thread({
            val ok = openSocket(info)
            val msg = lastErrorMessage ?: ""
            mainHandler.post {
                runCatching {
                    listener.onStatus(if (ok) POSConnect.CONNECT_SUCCESS else POSConnect.CONNECT_FAIL, info, msg)
                }
            }
        }, "lan-connect").start()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun connect(info: String, listener: IPOSListener) {
        closedByOwner = false
        Thread({
            val ok = openSocket(info)
            val msg = lastErrorMessage ?: info
            mainHandler.post {
                runCatching { listener.onStatus(if (ok) POSConnect.CONNECT_SUCCESS else POSConnect.CONNECT_FAIL, msg) }
            }
        }, "lan-connect").start()
    }

    // connectSync(): chặn luồng gọi và báo kết quả NGAY trên luồng đó (giống SDK).
    // KHÔNG gọi từ main thread: một lượt có thể mất tới CONNECT_TIMEOUT_MS.

    @Suppress("OVERRIDE_DEPRECATION")
    override fun connectSync(info: String, listener: IPOSListener): Boolean {
        closedByOwner = false
        val ok = openSocket(info)
        runCatching {
            listener.onStatus(
                if (ok) POSConnect.CONNECT_SUCCESS else POSConnect.CONNECT_FAIL,
                lastErrorMessage ?: info
            )
        }
        return ok
    }

    override fun connectSync(info: String, listener: IConnectListener): Boolean {
        connectListener = listener
        closedByOwner = false
        val ok = openSocket(info)
        runCatching {
            listener.onStatus(
                if (ok) POSConnect.CONNECT_SUCCESS else POSConnect.CONNECT_FAIL,
                info,
                lastErrorMessage ?: ""
            )
        }
        return ok
    }

    private fun openSocket(info: String): Boolean {
        connectInfo = info
        lastFailure = null
        lastErrorMessage = null
        val host = info.substringBefore(':')
        val port = info.substringAfter(':', "").toIntOrNull() ?: DEFAULT_PORT
        // Máy in vừa khởi động lại mạng (VD vừa đặt IP mới) hay bỏ qua gói SYN đầu; một
        // connect() chờ cả CONNECT_TIMEOUT_MS chỉ gửi lại SYN ở ~1s, ~3s nên lỡ máy sẵn sàng
        // ở giây thứ 3–6. Chia thành các lượt CONNECT_ATTEMPT_MS, mỗi lượt một socket mới
        // (SYN đi ngay), trong tổng hạn cũ. Chỉ thử lại khi HẾT GIỜ (lỗi khác báo ngay).
        val deadline = System.currentTimeMillis() + CONNECT_TIMEOUT_MS
        while (true) {
            // Nơi gọi đã bỏ lượt nối này (hết giờ ở scheduleConnectTimeout -> close()): dừng,
            // KHÔNG nối tiếp ở nền — xem [closedByOwner].
            if (closedByOwner) return false
            val left = (deadline - System.currentTimeMillis()).toInt()
            val wait = minOf(CONNECT_ATTEMPT_MS, left).coerceAtLeast(500)
            val ok = openSocketOnce(info, host, port, wait)
            if (ok || lastFailure != Failure.TIMEOUT) return ok
            if (deadline - System.currentTimeMillis() < 300) return false
            Log.i(TAG, "$info chưa trả lời bắt tay sau ${wait}ms, mở lại kết nối")
        }
    }

    private fun openSocketOnce(info: String, host: String, port: Int, timeoutMs: Int): Boolean {
        lastFailure = null
        lastErrorMessage = null
        val s = Socket()
        try {
            val address = InetAddress.getByName(host)
            // Gắn socket vào đúng mạng Wi-Fi/Ethernet chứa máy in: khi Wi-Fi "không có
            // Internet", Android có thể đẩy mạng mặc định sang 4G và socket tới 192.168.x.x
            // đi nhầm đường -> thất bại dù máy in ngay cạnh.
            bindToLocalNetwork(s, address)
            s.tcpNoDelay = true
            s.keepAlive = true
            // Bộ đệm gửi 16KB. Trước đây ép 512 byte (như SDK) vì bộ đệm lớn từng in ra ký
            // tự rác — nguyên nhân thật là ảnh bill dồn vào MỘT lệnh `GS v 0` vượt giới
            // hạn chiều cao raster (nay đã chia dải 128 dòng, xem getEscPosRasterBytes).
            // 512 byte buộc mỗi lần ghi chờ ACK: chỉ ~60KB/s qua Wi-Fi, máy in 80mm cần
            // ~140KB/s nên in giật, ra giấy chậm (bill dài 97KB mất 1,65s chỉ để gửi).
            // 16KB: gửi xong ~65ms; TCP tự điều tiết theo bộ đệm máy in. Đã kiểm tra trên
            // Epson LAN: in đủ, không ký tự rác.
            s.sendBufferSize = 16 * 1024
            s.connect(InetSocketAddress(address, port), timeoutMs)
            if (closedByOwner) {
                // Nối được nhưng nơi gọi đã bỏ (hết giờ) trong lúc chờ bắt tay: đóng ngay. Giữ lại
                // thì socket "mồ côi" này chiếm kết nối DUY NHẤT của máy in nhiệt -> lượt nối kế
                // tiếp của chính app bị máy in từ chối tới khi máy tự đóng socket (~10s).
                Log.i(TAG, "$info nối được sau khi đã bị huỷ, đóng ngay")
                runCatching { s.close() }
                lastFailure = Failure.OTHER
                return false
            }
            s.soTimeout = 0
            socket = s
            output = s.getOutputStream()
            input = s.getInputStream()
            alive = true
            freshSocket = true
            acquireWifiLock()
            flushIfDirty(info)
            return true
        } catch (e: Exception) {
            lastFailure = classify(e)
            lastErrorMessage = e.message ?: e.javaClass.simpleName
            Log.w(TAG, "Kết nối $info thất bại (${lastFailure}): $lastErrorMessage")
            runCatching { s.close() }
            return false
        }
    }

    private fun classify(e: Exception): Failure = when (e) {
        is SocketTimeoutException -> Failure.TIMEOUT
        is NoRouteToHostException -> Failure.UNREACHABLE
        is ConnectException -> {
            val msg = e.message.orEmpty()
            when {
                msg.contains("ENETUNREACH") || msg.contains("EHOSTUNREACH") ||
                    msg.contains("unreachable", ignoreCase = true) -> Failure.UNREACHABLE
                msg.contains("ETIMEDOUT") -> Failure.TIMEOUT
                else -> Failure.BUSY // ECONNREFUSED / ECONNRESET
            }
        }
        else -> Failure.OTHER
    }

    private fun bindToLocalNetwork(s: Socket, target: InetAddress) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || target !is Inet4Address) return
        val cm = appContext?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        try {
            @Suppress("DEPRECATION")
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) continue
                val lp = cm.getLinkProperties(network) ?: continue
                val sameSubnet = lp.linkAddresses.any { la ->
                    val local = la.address
                    local is Inet4Address && sameSubnet(local, target, la.prefixLength)
                }
                if (sameSubnet) {
                    network.bindSocket(s)
                    return
                }
            }
        } catch (e: Exception) {
            // Thiếu quyền ACCESS_NETWORK_STATE hoặc ROM lạ: đi theo mạng mặc định như cũ.
            Log.w(TAG, "Không gắn được socket vào mạng nội bộ: ${e.message}")
        }
    }

    private fun sameSubnet(a: Inet4Address, b: InetAddress, prefix: Int): Boolean {
        val x = a.address; val y = b.address
        if (y.size != 4 || prefix !in 0..32) return false
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        fun toInt(bs: ByteArray) = bs.fold(0) { acc, v -> (acc shl 8) or (v.toInt() and 0xFF) }
        return (toInt(x) and mask) == (toInt(y) and mask)
    }

    private fun acquireWifiLock() {
        val wm = appContext?.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        try {
            // Wi-Fi tiết kiệm năng lượng "ngủ" giữa các gói -> trễ thêm hàng trăm ms.
            // Chỉ giữ khóa khi socket mở (in LAN nhả socket ngay sau khi in xong).
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            else
                @Suppress("DEPRECATION") WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wm.createWifiLock(mode, "printer_label:lan").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Không giữ được WifiLock: ${e.message}")
        }
    }

    private fun releaseWifiLock() {
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        wifiLock = null
    }

    /**
     * Máy in nhận TCP rồi tự đóng ngay (đã đo: đóng sau ~1–2s khi chưa có dữ liệu, hoặc đang có
     * phiên khác) làm gói đầu gửi hỏng ("Broken pipe"). Đóng cứng socket hỏng, mở lại socket
     * MỚI tới cùng máy.
     *
     * "Gói đầu gửi hỏng" KHÔNG có nghĩa máy in chưa nhận byte nào: lỗi TCP báo trễ (byte đã vào
     * máy in, lần ghi sau mới thấy đứt), và trước gói đầu socket này còn đã gửi phần xả / lệnh hỏi
     * giấy. Máy in có thể đang kẹt giữa lệnh ảnh `GS v 0` -> phải XẢ trước khi gửi lại, nếu không
     * nó nuốt `ESC @` + đầu lệnh ảnh mới làm dữ liệu ảnh cũ và phần ảnh còn lại in ra chữ rác ở đầu
     * bill (lỗi khi nhiều máy cùng in / máy in vừa khởi động lại). Đánh dấu "in dở" để
     * [openSocket] -> [flushIfDirty] xả ngay trên socket mới.
     */
    fun reopen(): Boolean {
        val info = connectInfo
        abort(socket)
        socket = null
        output = null
        input = null
        PrintDirtyStore.mark(info)
        writeStalled = false
        closedByOwner = false
        return openSocket(info)
    }

    /** Lấy cờ "socket vừa mở, chưa gửi lệnh ESC/POS nào" (trả true đúng MỘT lần cho mỗi socket). */
    fun takeFreshSocket(): Boolean {
        val fresh = freshSocket
        freshSocket = false
        return fresh
    }

    // ─── Ghi ─────────────────────────────────────────────────────────────────

    /** Lần gửi trước tới [info] đứt giữa chừng -> xả bộ đệm máy in (lỗi xả không chặn việc in). */
    private fun flushIfDirty(info: String) {
        if (!PrintDirtyStore.isDirty(info)) return
        try {
            synchronized(writeLock) { writeFully(PrintDirtyStore.FLUSH_BYTES) }
            Thread.sleep(PrintDirtyStore.SETTLE_MS)
            PrintDirtyStore.clear(info)
            Log.i(TAG, "Đã xả bộ đệm $info sau lần gửi đứt giữa chừng")
        } catch (e: Exception) {
            Log.w(TAG, "Xả bộ đệm $info lỗi: ${e.message}")
        }
    }

    /**
     * Ghi hết [data] theo từng gói nhỏ, mỗi gói có watchdog: kẹt quá
     * WRITE_STALL_TIMEOUT_MS thì đóng socket để `write` ném lỗi thay vì treo vô hạn.
     */
    /**
     * Lần ghi gần nhất bị KẸT (máy in nhận kết nối nhưng không nhận dữ liệu — hết giấy,
     * mở nắp, máy đang lỗi, hoặc mạng quá yếu), khác với lỗi ghi thường.
     */
    @Volatile
    var writeStalled: Boolean = false
        private set

    private fun writeFully(data: ByteArray) {
        writeStalled = false
        val out = output ?: throw IOException("Chưa kết nối")
        var offset = 0
        while (offset < data.size) {
            val n = minOf(WRITE_CHUNK, data.size - offset)
            val s = socket
            val guard = watchdog.schedule({
                Log.w(TAG, "Ghi tới $connectInfo kẹt quá ${WRITE_STALL_TIMEOUT_MS}ms, đóng kết nối")
                lastFailure = Failure.SEND_FAILED
                writeStalled = true
                lastErrorMessage = "Máy in không nhận dữ liệu sau ${WRITE_STALL_TIMEOUT_MS / 1000}s " +
                    "(hết giấy, mở nắp, máy in đang lỗi hoặc mạng quá yếu)"
                abort(s)
            }, WRITE_STALL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            try {
                out.write(data, offset, n)
            } finally {
                guard.cancel(false)
            }
            offset += n
        }
        out.flush()
    }

    override fun sendSync(data: ByteArray): Int {
        if (!isConnect) return -1
        synchronized(writeLock) {
            return try {
                writeFully(data)
                data.size
            } catch (e: Exception) {
                fail(Failure.SEND_FAILED, e)
                -1
            }
        }
    }

    override fun sendData(data: ByteArray) {
        if (!isConnect) {
            Log.w(TAG, "sendData khi chưa kết nối $connectInfo, bỏ ${data.size} byte")
            return
        }
        pending.incrementAndGet()
        queue.put(data)
        ensureWriter()
    }

    override fun sendData(list: MutableList<ByteArray>) {
        list.forEach { sendData(it) }
    }

    private fun ensureWriter() {
        if (writer?.isAlive == true) return
        synchronized(this) {
            if (writer?.isAlive == true) return
            writer = Thread({
                while (alive) {
                    val data = try { queue.poll(1, TimeUnit.SECONDS) } catch (_: InterruptedException) { break }
                        ?: continue
                    synchronized(writeLock) {
                        try {
                            writeFully(data)
                        } catch (e: Exception) {
                            fail(Failure.SEND_FAILED, e)
                        }
                    }
                    if (pending.decrementAndGet() <= 0) notifyIdle()
                }
            }, "lan-writer-$connectInfo").apply { isDaemon = true; start() }
        }
    }

    private fun notifyIdle() {
        synchronized(idleLock) { idleLock.notifyAll() }
        sendCallback?.let { cb -> runCatching { cb.receive(0) } }
    }

    /**
     * Khác SDK (chỉ gọi callback tối đa 1 lần/2s nên có tem không bao giờ được báo):
     * callback được gọi khi hàng đợi gửi CẠN; đặt callback lúc đã cạn thì gọi ngay.
     */
    override fun setSendCallback(callback: IStatusCallback?) {
        sendCallback = callback
        if (callback != null && pending.get() <= 0) runCatching { callback.receive(0) }
    }

    /** Chờ hàng đợi sendData() gửi hết. Trả false nếu quá hạn. */
    fun awaitIdle(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        synchronized(idleLock) {
            while (pending.get() > 0 && alive) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) return false
                idleLock.wait(left)
            }
        }
        return pending.get() <= 0
    }

    // ─── Đọc (hỏi trạng thái máy in) ─────────────────────────────────────────

    override fun readSync(timeoutMs: Int): ByteArray? {
        val s = socket ?: return null
        val inp = input ?: return null
        synchronized(readLock) {
            return try {
                s.soTimeout = timeoutMs.coerceAtLeast(1)
                val buf = ByteArray(1024)
                val n = inp.read(buf)
                when {
                    n > 0 -> buf.copyOf(n)
                    n < 0 -> { fail(Failure.SEND_FAILED, IOException("Máy in đã đóng kết nối")); null }
                    else -> null
                }
            } catch (_: SocketTimeoutException) {
                null
            } catch (e: Exception) {
                fail(Failure.SEND_FAILED, e); null
            } finally {
                runCatching { s.soTimeout = 0 }
            }
        }
    }

    override fun readData(timeoutMs: Int, callback: IDataCallback) {
        Thread({ runCatching { callback.receive(readSync(timeoutMs)) } }, "lan-read").start()
    }

    override fun readData(callback: IDataCallback) = readData(2000, callback)

    override fun startReadLoop(callback: IDataCallback) {
        Thread({
            while (alive) {
                val data = readSync(1000) ?: continue
                runCatching { callback.receive(data) }
            }
        }, "lan-read-loop").apply { isDaemon = true; start() }
    }

    // ─── Trạng thái / đóng ───────────────────────────────────────────────────

    @Suppress("OVERRIDE_DEPRECATION")
    override fun isConnect(): Boolean {
        val s = socket ?: return false
        return alive && s.isConnected && !s.isClosed
    }

    override fun isConnect(data: ByteArray, callback: IStatusCallback) {
        Thread({
            val ok = sendSync(data) > 0
            runCatching { callback.receive(if (ok) POSConnect.CONNECT_SUCCESS else POSConnect.CONNECT_FAIL) }
        }, "lan-is-connect").start()
    }

    /** Lỗi khi đang dùng: đóng CỨNG (RST) để máy in nhả kênh in ngay cho thiết bị khác. */
    private fun fail(reason: Failure, e: Exception) {
        if (!alive) return
        if (lastFailure == null || lastFailure == Failure.OTHER) lastFailure = reason
        if (lastErrorMessage == null) lastErrorMessage = e.message ?: e.javaClass.simpleName
        Log.w(TAG, "Kết nối $connectInfo lỗi (${lastFailure}): $lastErrorMessage")
        if (reason == Failure.SEND_FAILED) PrintDirtyStore.mark(connectInfo)
        abort(socket)
        val info = connectInfo
        val msg = lastErrorMessage ?: ""
        connectListener?.let { l ->
            mainHandler.post { runCatching { l.onStatus(POSConnect.CONNECT_INTERRUPT, info, msg) } }
        }
    }

    private fun abort(s: Socket?) {
        alive = false
        queue.clear()
        pending.set(0)
        synchronized(idleLock) { idleLock.notifyAll() }
        runCatching { s?.setSoLinger(true, 0) }
        runCatching { s?.close() }
        releaseWifiLock()
    }

    /**
     * Đóng BÌNH THƯỜNG (nhả socket sau khi in): close() mặc định để kernel gửi nốt dữ liệu
     * còn trong buffer rồi FIN — không dùng RST, nếu không máy in có thể mất đuôi bill.
     */
    override fun close() {
        closedByOwner = true
        alive = false
        writer?.interrupt()
        queue.clear()
        pending.set(0)
        synchronized(idleLock) { idleLock.notifyAll() }
        runCatching { output?.flush() }
        runCatching { socket?.close() }
        socket = null
        output = null
        input = null
        releaseWifiLock()
    }

    override fun closeSync() = close()

    override fun getConnectInfo(): String = connectInfo

    override fun setConnectInfo(info: String) {
        connectInfo = info
    }

    override fun getConnectType(): Int = POSConnect.DEVICE_TYPE_ETHERNET
}
