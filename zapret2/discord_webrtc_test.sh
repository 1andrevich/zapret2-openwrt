#!/bin/sh
# =================================================================
#  Тестер WebRTC и голосового трафика Discord для OpenWrt / Linux
#  Работает в стандартном BusyBox /bin/sh без Python и зависимостей
# =================================================================

TMP_FILE="/tmp/webrtc_test_$$"
cleanup() {
    rm -f "$TMP_FILE"* 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "================================================================="
echo "      OPENWRT: ТЕСТ WEBRTC И ГОЛОСОВОГО ТРАФИКА DISCORD (UDP)    "
echo "================================================================="

# Проверка наличия активных VPN интерфейсов
VPN_FOUND=""
for iface in $(ls /sys/class/net 2>/dev/null); do
    case "$iface" in
        tun*|wg*|amn*|ppp*|tap*)
            state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null)
            if [ "$state" = "up" ] || [ "$state" = "unknown" ]; then
                VPN_FOUND="${VPN_FOUND}${iface} "
            fi
            ;;
    esac
done

if [ -n "$VPN_FOUND" ]; then
    echo "[ВНИМАНИЕ] Обнаружены активные VPN-интерфейсы: $VPN_FOUND"
    echo "           Тест показывает доступность через туннель, а не прямого WAN."
else
    echo "[СТАТУС]   VPN-интерфейсов не обнаружено. Тест идет напрямую через WAN."
fi
echo ""

# Функция замера времени через /proc/uptime (в миллисекундах)
get_time_ms() {
    if [ -f /proc/uptime ]; then
        read -r up _ < /proc/uptime
        awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0
    else
        date +%s000 2>/dev/null || echo 0
    fi
}

printf "%-44s %-16s %-17s %s\n" "Сервис / Регион" "Статус" "Время" "Код / Инфо"
echo "-----------------------------------------------------------------"

resolve_ip() {
    local host="$1"
    case "$host" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*) echo "$host"; return 0 ;;
    esac
    if command -v resolveip >/dev/null 2>&1; then
        resolveip -4 "$host" 2>/dev/null | head -n 1
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" 2>/dev/null | grep -E "Address: [0-9]" | head -n 1 | awk '{print $NF}'
    elif command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$host" 2>/dev/null | head -n 1 | awk '{print $1}'
    fi
}

udp_probe() {
    local mode="$1" host="$2" port="$3" timeout_ms="${4:-2000}"
    local ip; ip=$(resolve_ip "$host")
    if [ -z "$ip" ]; then
        echo "FAIL|0|DNS"
        return 1
    fi

    if command -v socat >/dev/null 2>&1; then
        local T_START=$(if [ -f /proc/uptime ]; then read -r up _ < /proc/uptime; awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0; else date +%s000 2>/dev/null || echo 0; fi)
        local SEC=$(awk "BEGIN {print $timeout_ms / 1000}" 2>/dev/null || echo 2)
        local REQ_FILE="$TMP_FILE.req"
        local RESP_FILE="$TMP_FILE.resp"
        rm -f "$RESP_FILE" "$REQ_FILE" 2>/dev/null
        if [ "$mode" = "discord" ]; then
            printf '\x00\x01\x00\x46\x00\x00\x30\x39\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$REQ_FILE"
        else
            printf '\x00\x01\x00\x00\x21\x12\xa4\x42\x12\x34\x56\x78\x9a\xbc\xde\xf0\x12\x34\x56\x78' > "$REQ_FILE"
        fi
        socat -t "$SEC" -T "$SEC" - UDP:"$ip":"$port" < "$REQ_FILE" > "$RESP_FILE" 2>/dev/null &
        local SOCAT_PID=$!
        while kill -0 "$SOCAT_PID" 2>/dev/null; do
            if [ -s "$RESP_FILE" ]; then
                usleep 20000 2>/dev/null
                kill "$SOCAT_PID" 2>/dev/null
                break
            fi
            usleep 10000 2>/dev/null || sleep 0.01 2>/dev/null
        done
        wait "$SOCAT_PID" 2>/dev/null
        local SIZE=$(wc -c < "$RESP_FILE" 2>/dev/null || echo 0)
        local T_END=$(if [ -f /proc/uptime ]; then read -r up _ < /proc/uptime; awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0; else date +%s000 2>/dev/null || echo 0; fi)
        local DT=$((T_END - T_START))
        [ "$DT" -le 0 ] && DT=1
        if [ "$mode" = "discord" ]; then
            if [ "$SIZE" -ge 70 ]; then
                local EXT_IP=$(tail -c +9 "$RESP_FILE" 2>/dev/null | tr -d '\0' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
                echo "OK|${DT}|${EXT_IP}"
            else
                echo "FAIL|${DT}"
            fi
        else
            if [ "$SIZE" -ge 20 ]; then
                echo "OK|${DT}|"
            else
                echo "FAIL|${DT}"
            fi
        fi
        rm -f "$REQ_FILE" "$RESP_FILE" 2>/dev/null
        return 0
    fi

    if command -v luajit >/dev/null 2>&1; then
        luajit - "$mode" "$ip" "$port" "$timeout_ms" << 'EOF'
local ffi = require("ffi")
local mode, ip, port, timeout = arg[1], arg[2], tonumber(arg[3]), tonumber(arg[4] or 2000)
ffi.cdef[[
    struct pollfd { int fd; short events; short revents; };
    int poll(struct pollfd *fds, unsigned long nfds, int timeout);
    struct in_addr { unsigned int s_addr; };
    struct sockaddr_in {
        short sin_family;
        unsigned short sin_port;
        struct in_addr sin_addr;
        char sin_zero[8];
    };
    int socket(int domain, int type, int protocol);
    long sendto(int sockfd, const void *buf, unsigned long len, int flags, const struct sockaddr_in *dest_addr, unsigned int addrlen);
    long recvfrom(int sockfd, void *buf, unsigned long len, int flags, void *src_addr, unsigned int *addrlen);
    int close(int fd);
    unsigned short htons(unsigned short hostshort);
    int inet_pton(int af, const char *src, void *dst);
    struct timeval { long long tv_sec; long long tv_usec; };
    int gettimeofday(struct timeval *tv, void *tz);
]]
local is_mips = (jit.arch == "mips" or jit.arch == "mipsel")
local fd = ffi.C.socket(2, is_mips and 1 or 2, 0)
if fd < 0 then print("FAIL|0|socket"); os.exit(1) end
local sin = ffi.new("struct sockaddr_in")
sin.sin_family = 2
sin.sin_port = ffi.C.htons(port)
if ffi.C.inet_pton(2, ip, sin.sin_addr) <= 0 then ffi.C.close(fd); print("FAIL|0|ip"); os.exit(1) end

local req, req_len
if mode == "discord" then
    req_len = 74
    req = ffi.new("uint8_t[74]")
    req[0] = 0; req[1] = 1; req[2] = 0; req[3] = 70; req[6] = 48; req[7] = 57
else
    req_len = 20
    req = ffi.new("uint8_t[20]", {
        0x00, 0x01, 0x00, 0x00,
        0x21, 0x12, 0xa4, 0x42,
        0x12, 0x34, 0x56, 0x78,
        0x9a, 0xbc, 0xde, 0xf0,
        0x12, 0x34, 0x56, 0x78
    })
end

local tv0 = ffi.new("struct timeval")
local tv1 = ffi.new("struct timeval")
ffi.C.gettimeofday(tv0, nil)

ffi.C.sendto(fd, req, req_len, 0, sin, ffi.sizeof(sin))
local pfd = ffi.new("struct pollfd[1]")
pfd[0].fd = fd; pfd[0].events = 1
local pr = ffi.C.poll(pfd, 1, timeout)
ffi.C.gettimeofday(tv1, nil)
local dt = math.max(1, math.floor(tonumber((tv1.tv_sec - tv0.tv_sec) * 1000 + (tv1.tv_usec - tv0.tv_usec) / 1000)))

if pr > 0 then
    local buf = ffi.new("uint8_t[512]")
    local n = tonumber(ffi.C.recvfrom(fd, buf, 512, 0, nil, nil))
    local min_len = (mode == "discord") and 70 or 20
    if n and n >= min_len then
        local ext = ""
        if mode == "discord" and n >= 70 then
            ext = ffi.string(buf + 8, math.max(0, n - 8)):match("([0-9]+%.[0-9]+%.[0-9]+%.[0-9]+)") or ""
        end
        ffi.C.close(fd)
        print("OK|" .. dt .. "|" .. ext)
        os.exit(0)
    end
end
ffi.C.close(fd)
print("FAIL|" .. dt)
EOF
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$mode" "$ip" "$port" "$timeout_ms" << 'EOF'
import sys, socket, time
mode, ip, port, timeout = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]) / 1000.0
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(timeout)
req = b'\x00\x01\x00\x46\x00\x00\x30\x39' + b'\x00'*66 if mode == "discord" else b'\x00\x01\x00\x00!\x12\xa4B\x124Vx\x9a\xbc\xde\xf0\x124Vx'
t0 = time.time()
try:
    s.sendto(req, (ip, port))
    data, _ = s.recvfrom(512)
    dt = max(1, int((time.time() - t0) * 1000))
    ext = ""
    if mode == "discord" and len(data) >= 70:
        ext = data[8:].split(b'\x00')[0].decode('ascii', errors='ignore').strip()
    print(f"OK|{dt}|{ext}")
except:
    dt = max(1, int((time.time() - t0) * 1000))
    print(f"FAIL|{dt}")
finally:
    s.close()
EOF
    else
        local T_START=$(if [ -f /proc/uptime ]; then read -r up _ < /proc/uptime; awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0; else date +%s000 2>/dev/null || echo 0; fi)
        if [ "$mode" = "discord" ]; then
            { printf '\x00\x01\x00\x46\x00\x00\x30\x39'; head -c 66 /dev/zero 2>/dev/null; } | nc -u -w 2 "$ip" "$port" > "$TMP_FILE" 2>/dev/null
            local SIZE=$(wc -c < "$TMP_FILE" 2>/dev/null || echo 0)
            local T_END=$(if [ -f /proc/uptime ]; then read -r up _ < /proc/uptime; awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0; else date +%s000 2>/dev/null || echo 0; fi)
            local DT=$((T_END - T_START))
            if [ "$SIZE" -ge 70 ]; then
                local EXT_IP=$(tail -c +9 "$TMP_FILE" 2>/dev/null | tr -d '\0' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
                echo "OK|${DT}|${EXT_IP}"
            else
                echo "FAIL|${DT}"
            fi
        else
            printf '\x00\x01\x00\x00\x21\x12\xa4\x42\x12\x34\x56\x78\x9a\xbc\xde\xf0\x12\x34\x56\x78' | nc -u -w 2 "$ip" "$port" > "$TMP_FILE" 2>/dev/null
            local SIZE=$(wc -c < "$TMP_FILE" 2>/dev/null || echo 0)
            local T_END=$(if [ -f /proc/uptime ]; then read -r up _ < /proc/uptime; awk "BEGIN {print int($up * 1000)}" 2>/dev/null || echo 0; else date +%s000 2>/dev/null || echo 0; fi)
            local DT=$((T_END - T_START))
            if [ "$SIZE" -ge 20 ]; then
                echo "OK|${DT}|"
            else
                echo "FAIL|${DT}"
            fi
        fi
        rm -f "$TMP_FILE" 2>/dev/null
    fi
}

# 1. Проверка WebRTC STUN (Binding Request RFC 5389, UDP)
check_stun() {
    NAME="$1"
    HOST="$2"
    PORT="$3"

    RES=$(udp_probe "stun" "$HOST" "$PORT" 2000)
    STATUS_CODE=$(echo "$RES" | cut -d'|' -f1)
    DT=$(echo "$RES" | cut -d'|' -f2)

    if [ "$STATUS_CODE" = "OK" ]; then
        STATUS="[  OK  ]"
        DETAILS="STUN OK (Ответ получен)"
        TIME_MS="${DT} ms"
    else
        STATUS="[ FAIL ]"
        DETAILS="Таймаут (UDP отброшен)"
        TIME_MS="--"
    fi
    printf "%-32s %-10s %-12s %s\n" "$NAME" "$STATUS" "$TIME_MS" "$DETAILS"
}

# 2. Проверка сигнальных шлюзов Discord Media (TCP WSS порт 2083)
check_tcp_signal() {
    NAME="$1"
    HOST="$2"
    PORT="$3"

    T_START=$(get_time_ms)
    if nc -z -w 2 "$HOST" "$PORT" 2>/dev/null; then
        T_END=$(get_time_ms)
        DT=$((T_END - T_START))
        STATUS="[  OK  ]"
        DETAILS="TCP 2083 (Шлюз WSS готов)"
        TIME_MS="${DT} ms"
    elif curl -s -k --connect-timeout 2 -m 3 "https://${HOST}:${PORT}" >/dev/null 2>&1; then
        T_END=$(get_time_ms)
        DT=$((T_END - T_START))
        STATUS="[  OK  ]"
        DETAILS="TCP 2083 (Шлюз WSS готов)"
        TIME_MS="${DT} ms"
    else
        STATUS="[ FAIL ]"
        DETAILS="Таймаут TCP подключения"
        TIME_MS="--"
    fi
    printf "%-32s %-10s %-12s %s\n" "$NAME" "$STATUS" "$TIME_MS" "$DETAILS"
}

# 3. Проверка голосовых кластеров Discord (Сырой UDP IP Discovery 74 байта)
check_discord_voice_udp() {
    NAME="$1"
    IP="$2"
    PORT="$3"

    RES=$(udp_probe "discord" "$IP" "$PORT" 2000)
    STATUS_CODE=$(echo "$RES" | cut -d'|' -f1)
    DT=$(echo "$RES" | cut -d'|' -f2)
    EXT_IP=$(echo "$RES" | cut -d'|' -f3)

    if [ "$STATUS_CODE" = "OK" ]; then
        STATUS="[  OK  ]"
        if [ -n "$EXT_IP" ]; then
            DETAILS="IP Discovery OK (IP: $EXT_IP)"
        else
            DETAILS="IP Discovery OK (Ответ получен)"
        fi
        TIME_MS="${DT} ms"
    else
        STATUS="[ FAIL ]"
        DETAILS="Таймаут (UDP отброшен)"
        TIME_MS="--"
    fi
    printf "%-32s %-10s %-12s %s\n" "$NAME" "$STATUS" "$TIME_MS" "$DETAILS"
}

# Тесты STUN
check_stun "WebRTC STUN (Google)" "stun.l.google.com" 19302
check_stun "WebRTC STUN (Cloudflare)" "stun.cloudflare.com" 3478

# Тесты сигнальных шлюзов WSS
check_tcp_signal "Discord Media WSS (Edge 1)" "162.159.138.234" 2083
check_tcp_signal "Discord Media WSS (Edge 2)" "162.159.128.233" 2083

# Тесты реальных голосовых кластеров Discord Voice UDP
check_discord_voice_udp "Discord Voice (Stockholm)" "104.29.136.169" 19316
check_discord_voice_udp "Discord Voice (Frankfurt)" "104.29.138.136" 19335
check_discord_voice_udp "Discord Voice (Warsaw)"    "104.29.140.10"  19310
check_discord_voice_udp "Discord Voice (Helsinki)"  "104.29.144.15"  19320

echo "-----------------------------------------------------------------"

if [ -f /proc/net/nf_conntrack ]; then
    DISCORD_FLOWS=$(awk '
    $1 ~ /^ipv[46]$/ && $3 == "udp" {
        src = ""; dst = ""; dport = ""; pkts_out = 0; pkts_in = 0;
        dir = 1;
        for (i = 4; i <= NF; i++) {
            if ($i ~ /^src=/ && src == "") { split($i, a, "="); src = a[2]; }
            if ($i ~ /^dst=/ && dst == "") { split($i, a, "="); dst = a[2]; }
            if ($i ~ /^dport=/ && dport == "") { split($i, a, "="); dport = a[2]; }
            if ($i ~ /^packets=/) {
                split($i, a, "=");
                if (dir == 1) { pkts_out = a[2]; dir = 2; }
                else { pkts_in = a[2]; }
            }
        }
        dp = dport + 0;
        if ((dp >= 19294 && dp <= 19344) || (dp >= 50000 && dp <= 65535)) {
            printf "  • LAN: %s -> Сервер: %s:%s | Исх: %d пкт, Вх: %d пкт\n", src, dst, dport, pkts_out, pkts_in;
        }
    }' /proc/net/nf_conntrack 2>/dev/null)
    if [ -n "$DISCORD_FLOWS" ]; then
        echo "--- АКТИВНЫЕ ГОЛОСОВЫЕ UDP СЕССИИ В CONNTRACK РОУТЕРА ---"
        echo "$DISCORD_FLOWS"
        echo "-----------------------------------------------------------------"
    fi
fi

echo "Тестирование завершено: $(date)"
