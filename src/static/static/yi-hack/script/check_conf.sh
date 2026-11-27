#!/bin/sh

SYSTEM_CONF_FILE="/tmp/sd/yi-hack/etc/system.conf"
CAMERA_CONF_FILE="/tmp/sd/yi-hack/etc/camera.conf"
MQTTV4_CONF_FILE="/tmp/sd/yi-hack/etc/mqttv4.conf"

PARMS1="
HTTPD=yes
TELNETD=no
SSHD=yes
FTPD=no
BUSYBOX_FTPD=no
MDNSD=yes
DISABLE_CLOUD=no
REC_WITHOUT_CLOUD=yes
MQTT=no
RTSP=yes
RTSP_ALT=standard
RTSP_STREAM=both
RTSP_AUDIO=aac
RTSP_STI=yes
RTSP_USE_SLOT=no
SPEAKER_AUDIO=yes
SNAPSHOT=yes
SNAPSHOT_VIDEO=no
SNAPSHOT_LOW=no
TIMELAPSE=no
TIMELAPSE_FTP=no
TIMELAPSE_FTP_SAME_NAME=no
TIMELAPSE_DT=60
TIMELAPSE_VDT=
ONVIF=yes
ONVIF_WSDD=yes
ONVIF_PROFILE=both
ONVIF_NETIF=wlan0
ONVIF_WM_SNAPSHOT=yes
ONVIF_AUDIO_BC=NONE
ONVIF_ENABLE_MEDIA2=no
ONVIF_ENABLE_IMAGING=no
ONVIF_EMPTY_IF_UNKNOWN=no
ONVIF_FAULT_IF_UNKNOWN=no
ONVIF_FAULT_IF_SET=no
ONVIF_SYNOLOGY_NVR=no
TIME_OSD=no
NTPD=yes
NTP_SERVER=pool.ntp.org
PROXYCHAINSNG=no
SWAP_FILE=yes
SWAP_SWAPPINESS=15
KERNEL_TUNING=yes
WIFI_POWERSAVE=no
RTSP_PORT=554
HTTPD_PORT=80
USERNAME=
PASSWORD=
TIMEZONE=
EVENTS_TIME=autodetect
FREE_SPACE=10
FTP_UPLOAD=no
FTP_HOST=
FTP_DIR=
FTP_DIR_TREE=no
FTP_USERNAME=
FTP_PASSWORD=
FTP_FILE_DELETE_AFTER_UPLOAD=yes
SSH_PASSWORD=
SSH_PASSWORD_HASH=
CRONTAB=
DEBUG_LOG=no
SYSLOG_SERVER=
STATIC_IP=
STATIC_MASK=
STATIC_GW=
STATIC_DNS1=
STATIC_DNS2=
CUSTOM_WATERMARK=no
WATCHDOG=yes
WD_SERVICES=yes
WD_NET_CHECK=yes
WD_PING_HOST=
WD_NET_REBOOT_MIN=15
WD_LOG=yes
REBOOT_SCHEDULE=no
REBOOT_HOUR=4
AUTO_UPDATE=yes
AUTO_UPDATE_HOUR=3
AUTO_UPDATE_REPO=tzureig/YI-Hack-v2
AUTO_UPDATE_CHANNEL=stable
SNAPSHOT_CACHE=2"

PARMS2="
SWITCH_ON=yes
SAVE_VIDEO_ON_MOTION=yes
MOTION_DETECTION=no
SENSITIVITY=low
AI_HUMAN_DETECTION=yes
AI_VEHICLE_DETECTION=no
AI_ANIMAL_DETECTION=no
FACE_DETECTION=no
MOTION_TRACKING=no
SOUND_DETECTION=no
SOUND_SENSITIVITY=80
LED=no
ROTATE=no
IR=yes
CRUISE=no
FORCE_NIGHT=no
FORCE_NIGHT_PERSIST=no"

PARMS3="
MQTT_IP=0.0.0.0
MQTT_PORT=1883
MQTT_TLS=0
MQTT_CLIENT_ID=yi-cam
MQTT_USER=
MQTT_PASSWORD=
MQTT_PREFIX=yicam
TOPIC_BIRTH_WILL=status
TOPIC_MOTION=motion_detection
TOPIC_MOTION_IMAGE=motion_detection_image
MOTION_IMAGE_DELAY=0.5
TOPIC_MOTION_FILES=motion_files
TOPIC_SOUND_DETECTION=sound_detection
BIRTH_MSG=online
WILL_MSG=offline
MOTION_START_MSG=motion_start
MOTION_STOP_MSG=motion_stop
AI_HUMAN_DETECTION_MSG=human
AI_VEHICLE_DETECTION_MSG=vehicle
AI_ANIMAL_DETECTION_MSG=animal
BABY_CRYING_MSG=crying
SOUND_DETECTION_MSG=sound_detected
MQTT_KEEPALIVE=120
MQTT_QOS=1
MQTT_RETAIN_BIRTH_WILL=1
MQTT_RETAIN_MOTION=0
MQTT_RETAIN_MOTION_IMAGE=0
MQTT_RETAIN_MOTION_FILES=0
MQTT_RETAIN_SOUND_DETECTION=0"

if [ ! -f $SYSTEM_CONF_FILE ]; then
    touch $SYSTEM_CONF_FILE
fi
for i in $PARMS1
do
    if [ ! -z "$i" ]; then
        PAR=$(echo "$i" | cut -d= -f1)
        MATCH=$(cat $SYSTEM_CONF_FILE | grep ^$PAR=)
        if [ -z "$MATCH" ]; then
            echo "$i" >> $SYSTEM_CONF_FILE
        fi
    fi
done

if [ ! -f $CAMERA_CONF_FILE ]; then
    touch $CAMERA_CONF_FILE
fi
for i in $PARMS2
do
    if [ ! -z "$i" ]; then
        PAR=$(echo "$i" | cut -d= -f1)
        MATCH=$(cat $CAMERA_CONF_FILE | grep ^$PAR=)
        if [ -z "$MATCH" ]; then
            echo "$i" >> $CAMERA_CONF_FILE
        fi
    fi
done

if [ ! -f $MQTTV4_CONF_FILE ]; then
    touch $MQTTV4_CONF_FILE
fi
for i in $PARMS3
do
    if [ ! -z "$i" ]; then
        PAR=$(echo "$i" | cut -d= -f1)
        MATCH=$(cat $MQTTV4_CONF_FILE | grep ^$PAR=)
        if [ -z "$MATCH" ]; then
            echo "$i" >> $MQTTV4_CONF_FILE
        fi
    fi
done

# Markers of earlier versions had a different prefix: rename them so that the
# one-time changes below are not applied a second time.
sed -i "s/^TIZ_REC_PERSON=/YIV2_REC_PERSON=/; s/^TIZ_V102=/YIV2_V102=/" $SYSTEM_CONF_FILE
# Releases moved to tzureig/YI-Hack-v2 (the old name only works via redirect)
sed -i "s|^AUTO_UPDATE_REPO=tzureig/YI-Hack-Tiz$|AUTO_UPDATE_REPO=tzureig/YI-Hack-v2|" $SYSTEM_CONF_FILE

# YI-Hack-v2: record to the SD card when a person is detected. Applied once
# to existing installations (marker YIV2_REC_PERSON), later changes in the web
# interface are kept.
if ! grep -q "^YIV2_REC_PERSON=done" $SYSTEM_CONF_FILE; then
    sed -i "s/^REC_WITHOUT_CLOUD=.*/REC_WITHOUT_CLOUD=yes/" $SYSTEM_CONF_FILE
    if grep -q "^FREE_SPACE=0$" $SYSTEM_CONF_FILE; then
        # delete the oldest recordings when less than 10 % of the SD is free
        sed -i "s/^FREE_SPACE=0$/FREE_SPACE=10/" $SYSTEM_CONF_FILE
    fi
    sed -i "s/^SWITCH_ON=.*/SWITCH_ON=yes/; s/^SAVE_VIDEO_ON_MOTION=.*/SAVE_VIDEO_ON_MOTION=yes/; s/^MOTION_DETECTION=.*/MOTION_DETECTION=no/; s/^AI_HUMAN_DETECTION=.*/AI_HUMAN_DETECTION=yes/" $CAMERA_CONF_FILE
    echo "YIV2_REC_PERSON=done" >> $SYSTEM_CONF_FILE
fi

# YI-Hack-v2 1.0.2: both streams for Home Assistant / Frigate (detection on
# the substream) and unique MQTT names, so that several cameras do not kick
# each other off the broker or merge into one Home Assistant device.
# MQTT names are changed only while MQTT is not in use.
if ! grep -q "^YIV2_V102=done" $SYSTEM_CONF_FILE; then
    sed -i "s/^RTSP_STREAM=.*/RTSP_STREAM=both/; s/^ONVIF_PROFILE=.*/ONVIF_PROFILE=both/" $SYSTEM_CONF_FILE
    # last 6 hex digits of the MAC (busybox here has no tr)
    MAC6=$(cat /sys/class/net/wlan0/address /sys/class/net/eth0/address 2>/dev/null | head -n1 | sed 's/[^0-9a-fA-F]//g' | awk '{print tolower(substr($0, length($0) - 5))}')
    if [ -n "$MAC6" ] && ! grep -q "^MQTT=yes" $SYSTEM_CONF_FILE; then
        sed -i "s/^MQTT_CLIENT_ID=yi-cam$/MQTT_CLIENT_ID=yi-cam-$MAC6/; s/^MQTT_PREFIX=yicam$/MQTT_PREFIX=yicam\/$MAC6/" $MQTTV4_CONF_FILE
        if [ -f /tmp/sd/yi-hack/etc/mqtt_advertise.conf ]; then
            sed -i "s/^HOMEASSISTANT_IDENTIFIERS=yi-cam$/HOMEASSISTANT_IDENTIFIERS=yi-cam-$MAC6/" /tmp/sd/yi-hack/etc/mqtt_advertise.conf
        fi
    fi
    echo "YIV2_V102=done" >> $SYSTEM_CONF_FILE
fi
