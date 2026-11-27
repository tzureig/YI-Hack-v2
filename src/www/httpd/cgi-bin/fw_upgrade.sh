#!/bin/sh

export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/app/localbin:/home/base:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin:/tmp/sd/yi-hack/usr/bin:/tmp/sd/yi-hack/usr/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/qigan/lib:/home/app/locallib:/tmp/sd:/tmp/sd/gdb:/tmp/sd/yi-hack/lib

YI_HACK_PREFIX="/tmp/sd/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

NAME="$(echo $QUERY_STRING | cut -d'=' -f1)"
VAL="$(echo $QUERY_STRING | cut -d'=' -f2)"

if [ "$NAME" != "get" ] ; then
    exit
fi

if [ "$VAL" == "info" ] ; then
    printf "Content-type: application/json\r\n\r\n"

    MODEL_SUFFIX=`cat $YI_HACK_PREFIX/model_suffix`
    FW_VERSION=`cat $YI_HACK_PREFIX/version`
    # Same logic as the nightly update (channel, signed releases, only newer versions)
    $YI_HACK_PREFIX/script/auto_update.sh check > /dev/null 2>&1
    STATE=$(cut -d'|' -f1 $YI_HACK_PREFIX/etc/auto_update.status 2>/dev/null)
    LATEST_FW=$(cut -d'|' -f3 $YI_HACK_PREFIX/etc/auto_update.status 2>/dev/null)
    case "$LATEST_FW" in *[!A-Za-z0-9._+-]*) LATEST_FW="" ;; esac
    if [ "$STATE" == "available" ]; then
        NEWER="true"
    else
        NEWER="false"
    fi
    [ "$STATE" == "error" ] && LATEST_FW="unknown (see auto_update.log)"
    if [ -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
        LOCAL_FW="true"
    else
        LOCAL_FW="false"
    fi

    printf "{\n"
    printf "\"%s\":\"%s\",\n" "error" "false"
    printf "\"%s\":\"%s\",\n" "fw_version"      "$FW_VERSION"
    printf "\"%s\":\"%s\",\n" "latest_fw"       "$LATEST_FW"
    printf "\"%s\":%s,\n" "newer"                 "$NEWER"
    printf "\"%s\":%s\n" "local_fw"             "$LOCAL_FW"
    printf "}"

elif [ "$VAL" == "upgrade" ] ; then

    FREE_SD=$(df | grep -m1 '/tmp/sd' | grep mmc | awk '{print $4}')
    if [ -z "$FREE_SD" ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No SD detected."
        exit
    fi

    if [ $FREE_SD -lt 100000 ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No space left on SD."
        exit
    fi

    MODEL_SUFFIX=`cat $YI_HACK_PREFIX/model_suffix`

    if [ ! -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
        # Online: download, check signature + checksum + model, unpack
        MSG=$($YI_HACK_PREFIX/script/auto_update.sh prepare 2>&1 | tail -n 1)
        if [ ! -f /tmp/sd/.fw_upgrade/yi-hack/fw_upgrade_in_progress ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "%s" "${MSG:-Upgrade failed, see auto_update.log}"
            exit
        fi
    else
        # Package copied to the SD card by hand (MODEL_x.x.x.tgz)
        rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf /tmp/sd/Factory /tmp/sd/newhome
        mkdir -p /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
        mv /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz /tmp/sd/.fw_upgrade/
        cd /tmp/sd/.fw_upgrade
        if ! tar zxf ${MODEL_SUFFIX}_x.x.x.tgz || [ "$(cat yi-hack/model_suffix 2>/dev/null)" != "$MODEL_SUFFIX" ]; then
            cd /tmp/sd
            rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
            printf "Content-type: text/html\r\n\r\n"
            printf "The package on the SD card is broken or for another model, upgrade refused."
            exit
        fi
        rm -f ${MODEL_SUFFIX}_x.x.x.tgz
        # Keep the configuration
        cp -rf $YI_HACK_PREFIX/etc/* /tmp/sd/.fw_upgrade.conf/
        rm -f /tmp/sd/.fw_upgrade.conf/*.tar.gz
        mkdir -p /tmp/sd/.fw_upgrade/yi-hack/etc
        cp -rf /tmp/sd/.fw_upgrade.conf/* /tmp/sd/.fw_upgrade/yi-hack/etc/
        rm -rf /tmp/sd/.fw_upgrade.conf
        rm -f /tmp/sd/.fw_upgrade/yi-hack/etc/auto_update.status
        touch /tmp/sd/.fw_upgrade/yi-hack/fw_upgrade_in_progress
        MSG="Package from the SD card unpacked, rebooting and upgrading."
    fi

    # Report the status to the caller
    printf "Content-type: text/html\r\n\r\n"
    printf "%s" "$MSG"

    sync
    sync
    sync
    sleep 1
    reboot
fi
