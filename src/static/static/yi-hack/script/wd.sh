#!/bin/sh

CONF_FILE="etc/system.conf"
CAMERA_CONF_FILE="etc/camera.conf"

YI_HACK_PREFIX="/tmp/sd/yi-hack"
MODEL_SUFFIX=$(cat /tmp/sd/yi-hack/model_suffix)

START_STOP_SCRIPT=$YI_HACK_PREFIX/script/service.sh

# The watchdog log lives in RAM (no SD wear) and is shown in the web UI
LOG_FILE="/dev/null"
LOG_LINES=0
LOGWIFI_FILE="/tmp/sd/hack_wififailsafe.log"
# Reason of the last reboot forced by the watchdog (kept on SD across reboots)
LAST_REBOOT_FILE="$YI_HACK_PREFIX/etc/wd_last_reboot"
NET_REBOOT_COUNT_FILE="$YI_HACK_PREFIX/etc/wd_net_reboots"

COUNTER=0
COUNTER_LIMIT=10
INTERVAL=10
WIFI_FAILSAFE_COUNTER=0
CPU_SAMPLED=no

get_camera_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CAMERA_CONF_FILE | cut -d "=" -f2-
}

get_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2-
}

# Write a watchdog message to LOG_FILE and, when remote syslog is on, to syslog
log()
{
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
    if [ "$LOG_FILE" != "/dev/null" ]; then
        LOG_LINES=$((LOG_LINES+1))
        # Keep the RAM log small: 300 lines at most
        if [ $LOG_LINES -ge 300 ]; then
            $YI_HACK_PREFIX/usr/bin/tail -n 150 $LOG_FILE > $LOG_FILE.tmp && mv $LOG_FILE.tmp $LOG_FILE
            LOG_LINES=150
        fi
    fi
    if [ "$SYSLOG" == "yes" ]; then
        logger -t wd.sh "$1"
    fi
}

# Reboot the camera, remembering why (shown in the status page)
wd_reboot()
{
    log "REBOOT: $1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" > $LAST_REBOOT_FILE
    if [ "$SYSLOG" == "yes" ]; then
        logger -t wd.sh "Rebooting: $1"
    fi
    sync
    sleep 1
    reboot
    exit 0
}

restart_rtsp()
{
    $START_STOP_SCRIPT rtsp start
}

# The checks below run every 10 s, so they only use shell builtins and read
# /proc and /sys: a healthy loop starts no new process apart from sleep and
# the nc of the RTSP probe.
# Command substitution forks in ash even for functions, so results are
# returned in variables.

# read_conf FILE KEY -> CONF_VAL
read_conf()
{
    CONF_VAL=""
    while IFS='=' read -r K V || [ -n "$K" ]; do
        if [ "$K" == "$2" ]; then
            CONF_VAL=$V
            return 0
        fi
    done < $1
    return 1
}

# PID_<NAME> for the processes the watchdog looks after ("" = not running)
scan_processes()
{
    PID_RRTSPSERVER=""
    PID_H264GRABBER=""
    PID_RTSP_SERVER_YI=""
    PID_GO2RTC=""
    PID_RMM=""
    PID_MQTTV4=""
    PID_HTTPD=""
    PID_DROPBEAR=""
    PID_WSDD=""
    PID_MDNSD=""
    PID_CROND=""
    for P in /proc/[0-9]*; do
        { read -r C < $P/comm; } 2>/dev/null || continue
        case "$C" in
            rRTSPServer) PID_RRTSPSERVER=${P#/proc/} ;;
            h264grabber) PID_H264GRABBER=${P#/proc/} ;;
            rtsp_server_yi) PID_RTSP_SERVER_YI=${P#/proc/} ;;
            go2rtc) PID_GO2RTC=${P#/proc/} ;;
            rmm) PID_RMM=${P#/proc/} ;;
            mqttv4) PID_MQTTV4=${P#/proc/} ;;
            httpd) PID_HTTPD=${P#/proc/} ;;
            dropbear) PID_DROPBEAR=${P#/proc/} ;;
            wsd_simple_serv*) PID_WSDD=${P#/proc/} ;;
            mdnsd) PID_MDNSD=${P#/proc/} ;;
            crond) PID_CROND=${P#/proc/} ;;
        esac
    done
}

# LISTEN and SOCKET: listening and established TCP sockets on the RTSP port
count_rtsp_sockets()
{
    LISTEN=0
    SOCKET=0
    for F in /proc/net/tcp /proc/net/tcp6; do
        [ -r $F ] || continue
        while read -r SL LOCAL REMOTE STATE REST; do
            case "$LOCAL" in
                *:$RTSP_PORT_HEX)
                    case "$STATE" in
                        0A) LISTEN=$((LISTEN+1)) ;;
                        01) SOCKET=$((SOCKET+1)) ;;
                    esac
                    ;;
            esac
        done < $F
    done
}

# TICKS: CPU time (utime + stime) used so far by process $1, "" if it is gone
proc_ticks()
{
    TICKS=""
    { read -r X X X X X X X X X X X X X U S X < /proc/$1/stat; } 2>/dev/null && TICKS=$((U + S))
}

check_rtsp()
{
    read_conf $YI_HACK_PREFIX/$CAMERA_CONF_FILE SWITCH_ON
    if [[ "$CONF_VAL" == "yes" ]] ; then
        #  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking RTSP process..." >> $LOG_FILE
        count_rtsp_sockets
        # CPU: "" if rRTSPServer is not running, otherwise the CPU ticks it
        # used in 1 s (measured only when a client is connected, as before
        # with top -d 1)
        CPU=""
        if [ -n "$PID_RRTSPSERVER" ]; then
            CPU="-"
            if [ $SOCKET -gt 0 ]; then
                proc_ticks $PID_RRTSPSERVER
                T1=$TICKS
                sleep 1
                CPU_SAMPLED=yes
                proc_ticks $PID_RRTSPSERVER
                if [ -n "$T1" ] && [ -n "$TICKS" ]; then
                    CPU=$((TICKS - T1))
                else
                    CPU=""
                fi
            fi
        fi

        # One restart at most per loop: the first failing check restarts the server
        if [ $LISTEN -eq 0 ]; then
            log "Restarting rtsp process"
            killall -q rRTSPServer
            sleep 1
            restart_rtsp
            COUNTER=0
        elif [ "$CPU" == "" ]; then
            log "No running processes, restarting..."
            killall -q rRTSPServer
            sleep 1
            restart_rtsp
            COUNTER=0
        elif [ -z "$(printf "OPTIONS rtsp://127.0.0.1:$RTSP_PORT_NUMBER/ RTSP/1.0\r\nCSeq: 1\r\n\r\n" | $YI_HACK_PREFIX/usr/bin/nc -w 5 127.0.0.1 $RTSP_PORT_NUMBER 2>/dev/null)" ]; then
            log "RTSP not answering, restarting..."
            killall -q rRTSPServer
            sleep 1
            restart_rtsp
            COUNTER=0
        elif [ $SOCKET -gt 0 ]; then
            if [ "$CPU" == "0" ]; then
                COUNTER=$((COUNTER+1))
                log "Detected possible locked process ($COUNTER)"
                if [ $COUNTER -ge $COUNTER_LIMIT ]; then
                    log "Restarting rtsp process"
                    killall -q rRTSPServer
                    sleep 1
                    restart_rtsp
                    COUNTER=0
                fi
            else
                COUNTER=0
            fi
        fi
    else
        echo "Camera is swiched off no rtsp restart needed" >> $LOG_FILE
    fi
}

check_rtsp_alt()
{
    read_conf $YI_HACK_PREFIX/$CAMERA_CONF_FILE SWITCH_ON
    if [[ "$CONF_VAL" == "yes" ]] ; then
        #  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking RTSP process..." >> $LOG_FILE
        count_rtsp_sockets
        CPU1=$PID_H264GRABBER
        CPU2=$PID_RTSP_SERVER_YI

        if [ $LISTEN -eq 0 ]; then
            log "Restarting rtsp process"
            killall -q rtsp_server_yi
            killall -q h264grabber
            sleep 1
            restart_rtsp
        elif [ "$CPU1" == "" ] || [ "$CPU2" == "" ]; then
            log "No running processes, restarting..."
            killall -q rtsp_server_yi
            killall -q h264grabber
            sleep 1
            restart_rtsp
            COUNTER=0
        fi
    else
        echo "Camera is switched off, rtsp restart not needed" >> $LOG_FILE
    fi
}

check_rtsp_go2rtc()
{
    read_conf $YI_HACK_PREFIX/$CAMERA_CONF_FILE SWITCH_ON
    if [[ "$CONF_VAL" == "yes" ]] ; then
        #  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking RTSP process..." >> $LOG_FILE
        count_rtsp_sockets
        CPU1=$PID_H264GRABBER
        CPU2=$PID_GO2RTC

        if [ $LISTEN -eq 0 ]; then
            log "Restarting rtsp process"
            killall -q go2rtc
            killall -q h264grabber
            sleep 1
            restart_rtsp
        elif [ "$CPU1" == "" ] || [ "$CPU2" == "" ]; then
            log "No running processes, restarting..."
            killall -q go2rtc
            killall -q h264grabber
            sleep 1
            restart_rtsp
            COUNTER=0
        fi
    else
        echo "Camera is switched off, rtsp restart not needed" >> $LOG_FILE
    fi
}

check_rmm()
{
    #  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking rmm process..." >> $LOG_FILE

    # Method 1: process name from /proc (see scan_processes)
    if [ -n "$PID_RMM" ]; then
        # Reset failure counter on successful detection
        if [ -f /tmp/rmm_fail_count ]; then
            rm -f /tmp/rmm_fail_count 2>/dev/null
        fi
        return 0
    fi

    # Method 2: Extended ps as fallback (original method)
    PS_WW=`ps ww | grep rmm | grep -v grep | grep -c ^`
    if [ $PS_WW -gt 0 ]; then
        # Reset failure counter on successful detection  
        rm -f /tmp/rmm_fail_count 2>/dev/null
        return 0
    fi

    # Failure handling with counter to prevent immediate reboots
    log "rmm detection failed"

    # Read current failure count
    if [ -f /tmp/rmm_fail_count ]; then
        FAIL_COUNT=$(cat /tmp/rmm_fail_count)
    else
        FAIL_COUNT=0
    fi

    # Increment failure count
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo $FAIL_COUNT > /tmp/rmm_fail_count

    log "rmm failure count: $FAIL_COUNT/5"

    # Only reboot after 5 consecutive failures (~50 seconds with 10s interval)
    if [ $FAIL_COUNT -ge 5 ]; then
        wd_reboot "rmm (camera main process) not running"
    fi
}

check_mqtt()
{
    #  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking mqttv4 process..." >> $LOG_FILE

    if [ -z "$PID_MQTTV4" ]; then
        log "check_mqtt failed, restart it!"
        $START_STOP_SCRIPT mqtt start
    fi
}

check_wifi()
{
    # Check WiFi connection using multiple methods for compatibility
    # Some camera models (e.g., r37gb) have broken wpa_cli that causes segfaults

    WIFI_CONNECTED=0

    # Cameras on Ethernet: nothing to do while eth0 is up and has a route
    if eth_connected; then
        WIFI_FAILSAFE_COUNTER=0
        return 0
    fi
    # No Wi-Fi interface at all: nothing to check
    if [ ! -d /sys/class/net/wlan0 ]; then
        return 0
    fi

    # Method 0: carrier up and a route on wlan0 (an address is configured)
    # means connected for methods 1-3 too; read without starting processes
    CARRIER=""
    { read -r CARRIER < /sys/class/net/wlan0/carrier; } 2>/dev/null
    if [ "$CARRIER" == "1" ]; then
        while read -r IFACE REST; do
            if [ "$IFACE" == "wlan0" ]; then
                WIFI_CONNECTED=1
                break
            fi
        done < /proc/net/route
    fi

    # Method 1: Try wpa_cli if available and working (preferred method)
    # Wrap in timeout to avoid hanging - wpa_cli may block on some models
    if [ $WIFI_CONNECTED -eq 0 ] && [ -x /home/base/tools/wpa_cli ]; then
        # Run wpa_cli with auto-kill after 2 seconds if it hangs
        (sleep 2 && killall -9 wpa_cli 2>/dev/null) &
        KILLER_PID=$!

        WPA_OUTPUT=$(/home/base/tools/wpa_cli -i wlan0 status 2>/dev/null)
        WPA_EXIT=$?

        # Kill the timeout killer if wpa_cli finished
        kill $KILLER_PID 2>/dev/null
        wait $KILLER_PID 2>/dev/null

        # Check if wpa_cli succeeded and returned valid output
        if [ $WPA_EXIT -eq 0 ] && echo "$WPA_OUTPUT" | grep -q "wpa_state=COMPLETED"; then
            WIFI_CONNECTED=1
        fi
    fi

    # Method 2: Fallback - check if interface has IP address (reliable on all models)
    if [ $WIFI_CONNECTED -eq 0 ]; then
        if ifconfig wlan0 2>/dev/null | grep -q "inet addr:"; then
            WIFI_CONNECTED=1
            # Method 3: the address stays after the link drops, so also require carrier
            if [ "$(cat /sys/class/net/wlan0/carrier 2>/dev/null)" == "0" ]; then
                WIFI_CONNECTED=0
            fi
        fi
    fi

    # Handle WiFi disconnection
    if [ $WIFI_CONNECTED -eq 0 ]; then
        # Rotate log file to prevent it from growing too large
        if [ -e "$LOGWIFI_FILE" ]; then
            $YI_HACK_PREFIX/usr/bin/tail -n 145 "$LOGWIFI_FILE" > "$LOGWIFI_FILE.tmp" && mv "$LOGWIFI_FILE.tmp" "$LOGWIFI_FILE"
        fi

        log "Wi-Fi connection lost (attempt $((WIFI_FAILSAFE_COUNTER + 1))/6)"
        echo -e "$(date): WiFi connection lost (failsafe attempt $((WIFI_FAILSAFE_COUNTER + 1))/6)" >> "$LOGWIFI_FILE"

        WIFI_FAILSAFE_COUNTER=$((WIFI_FAILSAFE_COUNTER + 1))

        if [ "$WIFI_FAILSAFE_COUNTER" -ge 6 ]; then
            echo -e "$(date): WiFi connection could not be restored after 6 attempts. Rebooting..." >> "$LOGWIFI_FILE"
            wd_reboot "Wi-Fi connection lost and not restored after 6 attempts"
        else
            echo -e "$(date): Attempting WiFi reconnect..." >> "$LOGWIFI_FILE"

            # Try to reconnect
            sleep 2
            ifconfig wlan0 down
            sleep 1
            ifconfig wlan0 up
            sleep 1

            # Try wpa_cli reconfigure if available and working
            if [ -x /home/base/tools/wpa_cli ]; then
                (sleep 2 && killall -9 wpa_cli 2>/dev/null) &
                KILLER_PID=$!
                /home/base/tools/wpa_cli -i wlan0 reconfigure 2>/dev/null
                kill $KILLER_PID 2>/dev/null
                wait $KILLER_PID 2>/dev/null
            fi

            # Run wifidhcp.sh
            $YI_HACK_PREFIX/script/wifidhcp.sh
        fi
    else
        # WiFi is connected - reset failure counter
        if [ $WIFI_FAILSAFE_COUNTER -gt 0 ]; then
            echo -e "$(date): WiFi connection restored" >> "$LOGWIFI_FILE"
            WIFI_FAILSAFE_COUNTER=0
        fi
    fi
}


# eth0 up with a route on it
eth_connected()
{
    E_CARRIER=""
    { read -r E_CARRIER < /sys/class/net/eth0/carrier; } 2>/dev/null
    [ "$E_CARRIER" == "1" ] || return 1
    while read -r IFACE REST; do
        [ "$IFACE" == "eth0" ] && return 0
    done < /proc/net/route
    return 1
}

# GW_IP: default gateway from /proc/net/route ("" if none)
get_gateway()
{
    GW_IP=""
    while read -r IFACE DEST GW REST; do
        if [ "$DEST" == "00000000" ] && [ "$GW" != "00000000" ] && [ ${#GW} -eq 8 ]; then
            # Little endian hex -> dotted quad
            GW_IP="$((0x${GW:6:2})).$((0x${GW:4:2})).$((0x${GW:2:2})).$((0x${GW:0:2}))"
            return 0
        fi
    done < /proc/net/route
    return 1
}

# Restart the services that keep the camera reachable if they crashed
check_services()
{
    if [ "$CONF_HTTPD" == "yes" ] && [ -z "$PID_HTTPD" ]; then
        log "httpd (web interface) not running, restarting"
        $START_STOP_SCRIPT httpd start
    fi
    if [ "$CONF_SSHD" == "yes" ] && [ -z "$PID_DROPBEAR" ]; then
        log "dropbear (ssh) not running, restarting"
        $START_STOP_SCRIPT sshd start
    fi
    if [ "$CONF_ONVIF" == "yes" ] && [ "$CONF_ONVIF_WSDD" == "yes" ] && [ -z "$PID_WSDD" ]; then
        log "wsd_simple_server (onvif discovery) not running, restarting"
        $START_STOP_SCRIPT wsdd start
    fi
    if [ "$CONF_MDNSD" == "yes" ] && [ -z "$PID_MDNSD" ] && [ -d /tmp/mdns.d ]; then
        log "mdnsd not running, restarting"
        $YI_HACK_PREFIX/sbin/mdnsd /tmp/mdns.d
    fi
    if [ -z "$PID_CROND" ]; then
        log "crond not running, restarting"
        $YI_HACK_PREFIX/usr/sbin/crond -c /var/spool/cron/crontabs/
    fi
}

# UPTIME_S: seconds since boot
get_uptime()
{
    read -r UPTIME_S REST < /proc/uptime
    UPTIME_S=${UPTIME_S%%.*}
}

# Ping the gateway (or WD_PING_HOST). The link can look fine while the
# camera is unreachable (lost DHCP lease, router restarted, stuck driver):
# renew the lease after ~90 s and reboot after WD_NET_REBOOT_MIN minutes.
check_network()
{
    PING_TARGET="$CONF_PING_HOST"
    if [ -z "$PING_TARGET" ]; then
        get_gateway
        PING_TARGET="$GW_IP"
    fi
    get_uptime
    if [ -z "$PING_TARGET" ]; then
        # No route at all: count as a failure only if we were online before
        PING_OK=no
    elif $YI_HACK_PREFIX/bin/busybox ping -c 1 -W 3 "$PING_TARGET" >/dev/null 2>&1 || \
         $YI_HACK_PREFIX/bin/busybox ping -c 1 -W 3 "$PING_TARGET" >/dev/null 2>&1; then
        PING_OK=yes
    else
        PING_OK=no
    fi

    if [ "$PING_OK" == "yes" ]; then
        if [ $NET_FAIL -gt 0 ]; then
            log "Network reachable again ($PING_TARGET)"
        fi
        NET_FAIL=0
        NET_EVER_OK=yes
        NET_FAIL_SINCE=0
        # Online for 10 minutes: forget previous network reboots
        if [ $NET_OK_SINCE -eq 0 ]; then
            NET_OK_SINCE=$UPTIME_S
        elif [ -f $NET_REBOOT_COUNT_FILE ] && [ $((UPTIME_S - NET_OK_SINCE)) -ge 600 ]; then
            rm -f $NET_REBOOT_COUNT_FILE
        fi
        return 0
    fi

    NET_OK_SINCE=0
    # Some routers never answer to ping: only act if the target answered once
    [ "$NET_EVER_OK" == "yes" ] || return 0

    NET_FAIL=$((NET_FAIL+1))
    [ $NET_FAIL_SINCE -eq 0 ] && NET_FAIL_SINCE=$UPTIME_S
    log "Network check failed ($NET_FAIL), target ${PING_TARGET:-none}"

    if [ $NET_FAIL -eq 3 ] || [ $((NET_FAIL % 10)) -eq 0 ]; then
        log "Renewing network configuration"
        if eth_connected; then
            $YI_HACK_PREFIX/script/ethdhcp.sh >/dev/null 2>&1
        else
            $YI_HACK_PREFIX/script/wifidhcp.sh >/dev/null 2>&1
        fi
    fi

    if [ "$CONF_NET_REBOOT_MIN" -gt 0 ] 2>/dev/null; then
        # Back off after consecutive network reboots (router off for hours)
        NRC=0
        [ -f $NET_REBOOT_COUNT_FILE ] && read -r NRC < $NET_REBOOT_COUNT_FILE
        case "$NRC" in ''|*[!0-9]*) NRC=0 ;; esac
        [ $NRC -gt 7 ] && NRC=7
        LIMIT=$((CONF_NET_REBOOT_MIN * 60 * (NRC + 1)))
        if [ $((UPTIME_S - NET_FAIL_SINCE)) -ge $LIMIT ]; then
            echo $((NRC + 1)) > $NET_REBOOT_COUNT_FILE
            wd_reboot "network unreachable ($PING_TARGET) for $((LIMIT / 60)) minutes"
        fi
    fi
}

if [[ $(get_config WATCHDOG) == "no" ]] ; then
    exit
fi

# Single instance
OLD_PID=""
[ -f /var/run/wd.pid ] && read -r OLD_PID < /var/run/wd.pid
if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && grep -q wd.sh "/proc/$OLD_PID/cmdline" 2>/dev/null; then
    exit
fi
echo $$ > /var/run/wd.pid

CONF_RTSP=$(get_config RTSP)
CONF_HTTPD=$(get_config HTTPD)
CONF_SSHD=$(get_config SSHD)
CONF_ONVIF=$(get_config ONVIF)
CONF_ONVIF_WSDD=$(get_config ONVIF_WSDD)
CONF_MDNSD=$(get_config MDNSD)
CONF_SERVICES=$(get_config WD_SERVICES)
CONF_NET_CHECK=$(get_config WD_NET_CHECK)
CONF_PING_HOST=$(get_config WD_PING_HOST)
case "$CONF_PING_HOST" in *[!A-Za-z0-9.:_-]*) CONF_PING_HOST="" ;; esac
CONF_NET_REBOOT_MIN=$(get_config WD_NET_REBOOT_MIN)
case "$CONF_NET_REBOOT_MIN" in ''|*[!0-9]*) CONF_NET_REBOOT_MIN=15 ;; esac
if [ "$(get_config WD_LOG)" != "no" ]; then
    LOG_FILE="/tmp/wd.log"
fi
NET_FAIL=0
NET_FAIL_SINCE=0
NET_OK_SINCE=0
NET_EVER_OK=no
LOOP=0

case $(get_config RTSP_PORT) in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$(get_config RTSP_PORT) ;;
esac

if [ ! -z $RTSP_PORT ]; then
    RTSP_PORT_NUMBER=$RTSP_PORT
fi
# Local port as in /proc/net/tcp (4 hex digits, upper case)
RTSP_PORT_HEX=$(printf "%04X" $RTSP_PORT_NUMBER)

RTSP_ALT=$(get_config RTSP_ALT)

# Remote syslog is on when system.sh started syslogd (SYSLOG_SERVER set)
SYSLOG=no
if [ ! -z "$(get_config SYSLOG_SERVER)" ] && [ -S /dev/log ]; then
    SYSLOG=yes
fi

log "Starting watchdog (rtsp=$CONF_RTSP services=$CONF_SERVICES network=$CONF_NET_CHECK reboot_after=${CONF_NET_REBOOT_MIN}min)"

while true
do
    LOOP=$((LOOP+1))
    scan_processes
    CPU_SAMPLED=no
    # RTSP is skipped while it was stopped on purpose (service.sh rtsp stop)
    if [ "$CONF_RTSP" == "yes" ] && [ ! -f /tmp/rtsp.stopped ]; then
        if [[ "$RTSP_ALT" == "standard" ]] ; then
            check_rtsp
        elif [[ "$RTSP_ALT" == "alternative" ]] ; then
            check_rtsp_alt
        else
            check_rtsp_go2rtc
        fi
    fi
    check_rmm
    check_mqtt
    check_wifi
    # Every ~30 s: network reachability; every ~60 s: services
    if [ "$CONF_NET_CHECK" != "no" ] && [ $((LOOP % 3)) -eq 0 ]; then
        check_network
    fi
    if [ "$CONF_SERVICES" != "no" ] && [ $((LOOP % 6)) -eq 0 ]; then
        check_services
    fi

    [ -d /sys/class/net/eth0 ] && echo 1500 > /sys/class/net/eth0/mtu
    [ -d /sys/class/net/wlan0 ] && echo 1500 > /sys/class/net/wlan0/mtu

    if [ $COUNTER -eq 0 ]; then
        sleep $INTERVAL
    elif [ "$CPU_SAMPLED" != "yes" ]; then
        # Checking a possibly locked rRTSPServer: loop again soon, but not
        # without a pause. top used to take this time; the CPU sample takes
        # it while a client is connected, this covers the loops without one.
        sleep 1
    fi
done
