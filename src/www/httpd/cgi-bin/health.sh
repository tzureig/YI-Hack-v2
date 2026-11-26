#!/bin/sh

# Lightweight health check for monitoring tools (Uptime Kuma, Home Assistant, ...)
# HTTP 200 + "status":"ok" when the camera process and the RTSP server (if enabled) run,
# HTTP 503 + "status":"degraded" otherwise.

CONF=/tmp/sd/yi-hack/etc/system.conf
RTSP_ON=$(grep -w ^RTSP $CONF | cut -d= -f2)
read -r UP REST < /proc/uptime
UP=${UP%%.*}

RMM=no
RTSP=no
for P in /proc/[0-9]*; do
    { read -r C < $P/comm; } 2>/dev/null || continue
    case "$C" in
        rmm) RMM=yes ;;
        rRTSPServer|rtsp_server_yi|go2rtc) RTSP=yes ;;
    esac
done

STATUS=ok
[ "$RMM" == "yes" ] || STATUS=degraded
if [ "$RTSP_ON" == "yes" ] && [ "$RTSP" != "yes" ] && [ ! -f /tmp/rtsp.stopped ]; then
    STATUS=degraded
fi

if [ "$STATUS" == "ok" ]; then
    printf "Status: 200 OK\r\n"
else
    printf "Status: 503 Service Unavailable\r\n"
fi
printf "Content-type: application/json\r\n"
printf "Cache-Control: no-cache\r\n\r\n"
printf '{"status":"%s","uptime":%s,"rmm":"%s","rtsp":"%s"}\n' "$STATUS" "$UP" "$RMM" "$RTSP"
