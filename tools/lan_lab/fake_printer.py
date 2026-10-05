#!/usr/bin/env python3
"""Máy in ESC/POS LAN giả lập để test mạng xấu (không tốn giấy).

  python3 fake_printer.py --mode ok
  python3 fake_printer.py --mode slow  --read-delay 0.05
  python3 fake_printer.py --mode drop  --drop-after 30000
  python3 fake_printer.py --mode busy
  python3 fake_printer.py --mode reset --drop-after 5000
"""
import argparse, os, socket, struct, threading, time

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=9100)
ap.add_argument("--mode", choices=["ok", "slow", "drop", "busy", "reset"], default="ok")
ap.add_argument("--drop-after", type=int, default=30000, help="drop/reset: số byte nhận trước khi cắt")
ap.add_argument("--read-delay", type=float, default=0.05, help="slow: giây nghỉ sau mỗi lần đọc")
ap.add_argument("--out", default="dumps", help="thư mục lưu dữ liệu nhận được")
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)
printing = threading.Lock()  # máy in thật chỉ in cho MỘT kết nối tại một thời điểm


def analyze(data: bytes) -> str:
    """Đếm lệnh GS v 0 / GS V trong luồng ESC/POS, báo dải ảnh cuối có bị thiếu byte không."""
    i, bands, cuts, dle = 0, 0, 0, 0
    while i < len(data):
        if data[i:i + 3] == b"\x1d\x76\x30" and i + 8 <= len(data):
            xl, xh, yl, yh = data[i + 4:i + 8]
            need = (xl + xh * 256) * (yl + yh * 256)
            got = len(data) - (i + 8)
            if got < need:
                return f"bands={bands} cuts={cuts} dle={dle} -> THIẾU {need - got} byte ở dải ảnh {bands + 1} (máy in thật sẽ nuốt dữ liệu job sau)"
            bands += 1
            i += 8 + need
        elif data[i:i + 2] == b"\x1d\x56":
            cuts += 1
            i += 2
        elif data[i:i + 2] == b"\x10\x04":
            dle += 1
            i += 3
        else:
            i += 1
    if cuts == 0:
        return f"bands={bands} cuts=0 dle={dle} -> KHÔNG có lệnh cắt (bill thiếu đuôi)"
    return f"bands={bands} cuts={cuts} dle={dle} -> ĐỦ"


def handle(conn: socket.socket, addr):
    tag = f"{addr[0]}:{addr[1]}"
    got_lock = printing.acquire(blocking=False)
    if args.mode == "busy" and not got_lock:
        # Hành vi đã quan sát ở máy in thật: accept nhưng đóng ngay khi có byte tới
        # (phía gửi nhận "Broken pipe"/"Connection reset").
        conn.recv(1)
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        conn.close()
        print(f"[{tag}] BẬN: đóng kết nối phụ")
        return
    buf = bytearray()
    try:
        while True:
            size = 1024 if args.mode == "slow" else 65536
            if args.mode in ("drop", "reset"):
                size = min(size, args.drop_after - len(buf))  # cắt đúng tại byte drop-after
            chunk = conn.recv(size)
            if not chunk:
                break
            buf += chunk
            # Trả lời DLE EOT n (hỏi trạng thái) bằng byte "bình thường".
            if b"\x10\x04" in chunk:
                conn.sendall(b"\x12")
            if args.mode == "slow":
                time.sleep(args.read_delay)
            if args.mode in ("drop", "reset") and len(buf) >= args.drop_after:
                if args.mode == "reset":  # SO_LINGER 0 -> close() gửi RST
                    conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                print(f"[{tag}] CẮT kết nối sau {len(buf)} byte ({args.mode})")
                break
    except OSError as e:
        print(f"[{tag}] lỗi socket: {e}")
    finally:
        conn.close()
        if got_lock:
            printing.release()
    path = os.path.join(args.out, f"{int(time.time() * 1000)}_{addr[0]}.bin")
    with open(path, "wb") as f:
        f.write(buf)
    print(f"[{tag}] nhận {len(buf)} byte, {analyze(bytes(buf))}, lưu {path}")


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
if args.mode == "slow":
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)  # bộ đệm nhỏ như máy in thật
srv.bind(("0.0.0.0", args.port))
srv.listen(5)
print(f"Máy in giả chế độ '{args.mode}' đang nghe cổng {args.port}")
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
