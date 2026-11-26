#!/bin/sh

# Show the last lines of a log: ?name=wd|wifi|boot|dmesg|syslog

printf "Content-type: text/plain; charset=utf-8\r\n"
printf "Cache-Control: no-cache\r\n\r\n"

NAME=$(echo "$QUERY_STRING" | sed -n 's/^.*name=\([a-z]*\).*$/\1/p')
TAIL=/tmp/sd/yi-hack/usr/bin/tail
[ -x $TAIL ] || TAIL=tail

show()
{
    if [ -s "$1" ]; then
        $TAIL -n 200 "$1"
    else
        echo "Log is empty or not available ($1)."
    fi
}

case "$NAME" in
    wd)
        show /tmp/wd.log
        ;;
    update)
        show /tmp/sd/yi-hack/etc/auto_update.log
        ;;
    wifi)
        show /tmp/sd/hack_wififailsafe.log
        ;;
    boot)
        if [ -s /tmp/sd/hack_debug.log ]; then
            show /tmp/sd/hack_debug.log
        else
            echo "Enable \"Debug log\" in Configuration (Expert) and reboot to get the boot log."
        fi
        ;;
    dmesg)
        dmesg 2>/dev/null | $TAIL -n 200
        ;;
    processes)
        # Hide passwords given on command lines (rtsp server, mqtt, ...)
        ps | sed -E 's/(-w|-P|--password|password=) *[^ ]+/\1 ********/g'
        echo ""
        free
        echo ""
        df -h 2>/dev/null
        ;;
    *)
        echo "Unknown log"
        ;;
esac
