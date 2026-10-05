#!/usr/bin/env python3
"""Bộ chuyển tiếp TCP: điện thoại -> Mac:9100 -> máy in thật.

Dùng cùng `lan_lab.sh on <mức> phone`: đoạn Wi-Fi điện thoại <-> Mac bị làm yếu, còn
đoạn Mac -> máy in giữ nguyên nên giấy vẫn ra thật. Trong app nhập IP của Mac thay cho
IP máy in.

  python3 lan_relay.py --target 192.168.1.22:9100

Mỗi kết nối in ra: thời gian, số byte hai chiều, tốc độ gửi (KB/s) và phía nào đóng
(FIN = đóng bình thường, RST = bị reset). Tốc độ gửi dùng để đo ảnh hưởng của bộ đệm
gửi 512 byte trong SDK Android khi mạng trễ cao.
"""
import argparse, errno, socket, struct, threading, time

ap = argparse.ArgumentParser()
ap.add_argument("--listen", type=int, default=9100, help="cổng nghe trên Mac")
ap.add_argument("--target", required=True, help="IP:cổng máy in thật, VD 192.168.1.22:9100")
ap.add_argument("--connect-timeout", type=float, default=10, help="giây chờ kết nối tới máy in")
args = ap.parse_args()
host, _, port = args.target.partition(":")
target = (host, int(port or 9100))


def reset(sock: socket.socket):
    """Đóng bằng RST (SO_LINGER 0) — giữ đúng hành vi máy in reset kết nối."""
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        sock.close()
    except OSError:
        pass


def pump(src, dst, stats, key):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
            stats[key] += len(data)
        # Nửa đóng: báo bên kia "hết dữ liệu" nhưng vẫn cho chiều ngược lại chạy tiếp.
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        stats[key + "_end"] = "FIN"
    except ConnectionResetError:
        stats[key + "_end"] = "RST"
        reset(dst)  # truyền RST sang phía còn lại
    except OSError as e:
        # EBADF: socket bị chính luồng kia đóng khi truyền RST — không phải lỗi mới.
        reason = "đóng theo phía kia" if e.errno == errno.EBADF else f"lỗi: {e.strerror or e}"
        stats.setdefault(key + "_end", reason)


def handle(client: socket.socket, addr):
    tag = f"{addr[0]}:{addr[1]}"
    t0 = time.time()
    try:
        upstream = socket.create_connection(target, timeout=args.connect_timeout)
        upstream.settimeout(None)
    except OSError as e:
        print(f"[{tag}] KHÔNG kết nối được máy in {args.target}: {e} -> reset phía điện thoại", flush=True)
        reset(client)
        return
    print(f"[{tag}] mở kết nối, máy in nhận sau {(time.time() - t0) * 1000:.0f}ms", flush=True)

    stats = {"up": 0, "down": 0}
    t_up = threading.Thread(target=pump, args=(client, upstream, stats, "up"), daemon=True)
    t_down = threading.Thread(target=pump, args=(upstream, client, stats, "down"), daemon=True)
    t_up.start(); t_down.start()
    t_up.join()
    # Điện thoại đã gửi xong/đóng: chờ máy in đóng tối đa 5s rồi dọn, tránh treo luồng.
    t_down.join(timeout=5)
    for s in (client, upstream):
        try:
            s.close()
        except OSError:
            pass
    dt = time.time() - t0
    speed = stats["up"] / 1024 / dt if dt > 0 else 0
    print(
        f"[{tag}] xong sau {dt:.1f}s: chuyển {stats['up']} byte ({speed:.1f} KB/s), "
        f"nhận {stats['down']} byte, điện thoại đóng={stats.get('up_end', '?')}, "
        f"máy in đóng={stats.get('down_end', '?')}",
        flush=True,
    )


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", args.listen))
srv.listen(8)
print(f"Chuyển tiếp 0.0.0.0:{args.listen} -> {args.target}. Ctrl+C để dừng.", flush=True)
try:
    while True:
        c, a = srv.accept()
        threading.Thread(target=handle, args=(c, a), daemon=True).start()
except KeyboardInterrupt:
    print("\nĐã dừng bộ chuyển tiếp.")
