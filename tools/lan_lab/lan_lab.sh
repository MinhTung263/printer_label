#!/bin/bash
# Môi trường mạng yếu để test in LAN trên macOS (dùng dnctl/pfctl có sẵn, không cần cài gì).
# Chạy bằng user thường; script tự gọi sudo ở các bước cần quyền root.
#
#   ./lan_lab.sh relay                 chuyển tiếp điện thoại -> Mac:9100 -> máy in thật
#   ./lan_lab.sh fake ok|slow|drop|busy|reset [tham số fake_printer.py]
#   ./lan_lab.sh on s1|s2|s2x|s3|custom|dead [phone|sim]   bật mạng yếu (mặc định: s2 phone)
#   ./lan_lab.sh syn 0.5               thêm rớt gói SYN 50% (0 = bỏ)
#   ./lan_lab.sh flap [giây_có_mạng] [giây_mất_mạng]   mạng chập chờn (Ctrl+C để dừng)
#   ./lan_lab.sh spike                 trễ đột biến 50–1500ms (Ctrl+C để dừng)
#   ./lan_lab.sh check                 đo bắt tay TCP + ping
#   ./lan_lab.sh status | off
#
# Đích làm yếu:
#   phone : traffic tới/từ cổng 9100 CỦA MAC (điện thoại thật đi qua `relay` hoặc `fake`)
#   sim   : traffic từ Mac tới máy in (iOS Simulator / Android Emulator chạy trên Mac)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PRINTER="${PRINTER:-192.168.1.53}"
PORT="${PORT:-9100}"
ANCHOR="com.apple/lanlab"          # nằm dưới dummynet-anchor "com.apple/*" có sẵn trong /etc/pf.conf
STATE="${TMPDIR:-/tmp}/lan_lab.state"
TOKEN="${TMPDIR:-/tmp}/lan_lab.token"
MAC_IP="$(ipconfig getifaddr en0 2>/dev/null || echo '?')"

die() { echo "Lỗi: $*" >&2; exit 1; }

# Thông số MỘT CHIỀU cho mỗi pipe (pipe 1 = vào máy in, pipe 2 = từ máy in ra).
# RTT tăng thêm = 2 x delay; tỷ lệ mất gói khứ hồi ≈ 2 x plr.
profile_params() {
  case "$1" in
    s1)   echo "delay 40 plr 0.01" ;;                  # quán đông vừa: RTT +80ms, mất ~2%
    s2)   echo "delay 150 plr 0.05 bw 2Mbit/s" ;;      # quán rất đông: RTT +300ms, mất ~10%
    s2x)  echo "delay 300 plr 0.10 bw 1Mbit/s" ;;      # cực đông: RTT +600ms, mất ~20%
    s3)   echo "delay 500 plr 0.15 bw 512Kbit/s" ;;    # quá tải: RTT +1000ms, mất ~30%
    # Tự chọn: DELAY=ms (một chiều), PLR=0..1 (mỗi chiều), BW=VD 256Kbit/s (bỏ trống = không giới hạn)
    custom) echo "delay ${DELAY:-400} plr ${PLR:-0.1}${BW:+ bw $BW}" ;;
    dead) echo "plr 1" ;;                              # mất mạng hẳn
    *) return 1 ;;
  esac
}

save_state() { printf '%s %s %s\n' "$1" "$2" "$3" > "$STATE"; }      # mức đích syn
load_state() { [ -f "$STATE" ] && cat "$STATE" || echo "- - 0"; }

load_rules() {  # $1 = phone|sim, $2 = tỷ lệ rớt SYN
  local target="$1" syn="$2" rules=""
  if [ "$target" = phone ]; then
    [ "$syn" != 0 ] && rules+="dummynet in  quick proto tcp from any to any port $PORT flags S/SA pipe 3"$'\n'
    rules+="dummynet in  quick proto tcp from any to any port $PORT pipe 1"$'\n'
    rules+="dummynet out quick proto tcp from any port $PORT to any pipe 2"$'\n'
  else
    [ "$syn" != 0 ] && rules+="dummynet out quick proto tcp from any to $PRINTER port $PORT flags S/SA pipe 3"$'\n'
    rules+="dummynet out quick proto tcp from any to $PRINTER port $PORT pipe 1"$'\n'
    rules+="dummynet in  quick proto tcp from $PRINTER port $PORT to any pipe 2"$'\n'
  fi
  # pfctl luôn in cảnh báo "Use of -f option..." dù ta chỉ nạp vào anchor riêng (không đụng
  # rule hệ thống) -> lọc bỏ cảnh báo đó, vẫn hiện lỗi thật nếu có.
  local out
  if ! out="$(printf '%s' "$rules" | sudo pfctl -q -a "$ANCHOR" -f - 2>&1)"; then
    echo "$out" >&2; die "nạp rule pf thất bại"
  fi
  printf '%s\n' "$out" | grep -v -E "Use of -f option|present in the main ruleset|See /etc/pf.conf|^$" >&2 || true
}

config_pipes() {  # $1 = thông số dnctl
  # shellcheck disable=SC2086
  sudo dnctl pipe 1 config $1
  # shellcheck disable=SC2086
  sudo dnctl pipe 2 config $1
}

enable_pf() {
  [ -s "$TOKEN" ] && return 0
  # -E bật pf theo kiểu "đếm tham chiếu" và trả về token; -X token để nhả, không tắt pf
  # của dịch vụ khác đang dùng.
  sudo pfctl -E 2>&1 | sed -n 's/.*Token : \([0-9]*\).*/\1/p' > "$TOKEN"
}

cmd_on() {
  local profile="${1:-s2}" target="${2:-phone}" params syn
  params="$(profile_params "$profile")" || die "mức '$profile' không có (s1|s2|s2x|s3|custom|dead)"
  [ "$target" = phone ] || [ "$target" = sim ] || die "đích phải là phone hoặc sim"
  syn="$(load_state | awk '{print $3}')"
  config_pipes "$params"
  [ "$syn" != 0 ] && sudo dnctl pipe 3 config $params plr "$syn"
  load_rules "$target" "$syn"
  enable_pf
  save_state "$profile" "$target" "$syn"
  echo "Đã bật mạng yếu: mức=$profile ($params), đích=$target, rớt SYN=$syn"
  if [ "$target" = phone ]; then
    echo "-> Trong app nhập IP máy in = $MAC_IP (IP của Mac), và chạy 'relay' hoặc 'fake' ở terminal khác."
  else
    echo "-> Simulator/Emulator in thẳng tới $PRINTER."
  fi
}

cmd_syn() {
  local rate="${1:-0.5}" profile target
  read -r profile target _ < <(load_state)
  [ "$profile" != - ] || die "chạy 'on' trước"
  save_state "$profile" "$target" "$rate"
  cmd_on "$profile" "$target"
}

cmd_off() {
  sudo pfctl -q -a "$ANCHOR" -F all 2>/dev/null || true
  sudo dnctl -q flush 2>/dev/null || true
  if [ -s "$TOKEN" ]; then sudo pfctl -q -X "$(cat "$TOKEN")" 2>/dev/null || true; fi
  rm -f "$STATE" "$TOKEN"
  echo "Đã tắt mạng yếu, mạng trở lại bình thường."
}

# Đổi thông số pipe liên tục; Ctrl+C trả về mức đang bật.
restore_on_exit() {
  local profile
  read -r profile _ < <(load_state)
  trap - INT TERM
  config_pipes "$(profile_params "$profile")"
  echo; echo "Đã dừng, trả về mức $profile."
  exit 0
}

require_on() {
  local profile
  read -r profile _ < <(load_state)
  [ "$profile" != - ] || die "chạy './lan_lab.sh on s1' (hoặc s2) trước"
  echo "$profile"
}

cmd_flap() {
  local up="${1:-20}" down="${2:-3}" profile
  profile="$(require_on)"
  sudo -v
  trap restore_on_exit INT TERM
  echo "Chập chờn: có mạng ${up}s (mức $profile) / mất hẳn ${down}s. Ctrl+C để dừng."
  while true; do
    sleep "$up"
    config_pipes "plr 1"; echo "$(date +%T) MẤT MẠNG ${down}s"
    sleep "$down"
    config_pipes "$(profile_params "$profile")"; echo "$(date +%T) có mạng lại"
  done
}

cmd_spike() {
  local profile base
  profile="$(require_on)"
  base="$(profile_params "$profile" | sed -E 's/delay [0-9]+ ?//')"
  sudo -v
  trap restore_on_exit INT TERM
  echo "Trễ đột biến mỗi 2s (một chiều 50–1500ms, giống Wi-Fi nghẽn bufferbloat). Ctrl+C để dừng."
  local delays=(50 50 100 150 300 600 1000 1500)
  while true; do
    local d="${delays[RANDOM % ${#delays[@]}]}"
    config_pipes "delay $d $base"
    echo "$(date +%T) trễ một chiều ${d}ms (RTT ~$((d * 2))ms)"
    sleep 2
  done
}

cmd_check() {
  local host target
  read -r _ target _ < <(load_state)
  if [ "$target" = phone ]; then host="$MAC_IP"; else host="$PRINTER"; fi
  echo "Bắt tay TCP tới $host:$PORT (10 lần, chỉ mở rồi đóng, không gửi byte nào):"
  python3 - "$host" "$PORT" <<'EOF'
import socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])
res = []
for _ in range(10):
    t = time.time()
    try:
        s = socket.create_connection((host, port), 5); s.close()
        res.append(f"{(time.time() - t) * 1000:.0f}ms")
    except OSError as e:
        res.append(f"LỖI({e.__class__.__name__})")
    time.sleep(0.3)
print("  " + " ".join(res))
EOF
  echo "Ping $PRINTER (ICMP KHÔNG bị làm yếu — chỉ để so với mạng nền):"
  ping -c 20 -i 0.2 "$PRINTER" | tail -2 | sed 's/^/  /'
  if [ "$target" = phone ]; then
    echo "Lưu ý: kết nối từ Mac tới chính IP của Mac có thể không đi qua pf. Muốn chắc chắn,"
    echo "      đo từ điện thoại bằng app PingTools (TCP ping tới $MAC_IP cổng $PORT)."
  fi
}

cmd_status() {
  local profile target syn
  read -r profile target syn < <(load_state)
  echo "Mac: $MAC_IP   Máy in: $PRINTER:$PORT"
  if [ "$profile" = - ]; then echo "Mạng yếu: TẮT"; return; fi
  echo "Mạng yếu: BẬT — mức=$profile, đích=$target, rớt SYN=$syn"
  sudo pfctl -a "$ANCHOR" -s dummynet 2>/dev/null | sed 's/^/  rule: /'
  sudo dnctl list 2>/dev/null | grep -E "^0000[1-3]|drop" | sed 's/^/  /'
}

case "${1:-}" in
  on)     shift; cmd_on "$@" ;;
  off)    cmd_off ;;
  syn)    shift; cmd_syn "$@" ;;
  flap)   shift; cmd_flap "$@" ;;
  spike)  cmd_spike ;;
  check)  cmd_check ;;
  status) cmd_status ;;
  relay)  exec python3 "$DIR/lan_relay.py" --listen "$PORT" --target "$PRINTER:$PORT" ;;
  fake)   shift; exec python3 "$DIR/fake_printer.py" --port "$PORT" --out "${TMPDIR:-/tmp}/lan_lab_dumps" --mode "${1:-ok}" "${@:2}" ;;
  *)      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
