#!/bin/sh

YI_HACK_PREFIX="/tmp/sd/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

BASE64="no"
RES="-r high"
WATERMARK="no"
OUTPUT_FILE="none"
MODEL=$(cat /tmp/sd/yi-hack/model_suffix)

for I in 1 2 3 4
do
    CONF="$(echo $QUERY_STRING | cut -d'&' -f$I | cut -d'=' -f1)"
    VAL="$(echo $QUERY_STRING | cut -d'&' -f$I | cut -d'=' -f2)"

    if [ "$CONF" == "res" ] ; then
        if [ "$VAL" == "low" ] || [ "$VAL" == "high" ] ; then
            RES="-r $VAL"
        fi
    elif [ "$CONF" == "watermark" ] ; then
        if [ "$VAL" == "yes" ] || [ "$VAL" == "no" ] ; then
            WATERMARK=$VAL
        fi
    elif [ "$CONF" == "base64" ] ; then
        if [ "$VAL" == "yes" ] || [ "$VAL" == "no" ] ; then
            BASE64=$VAL
        fi
    elif [ "$CONF" == "file" ] ; then
        OUTPUT_FILE=$VAL
    fi
done

REDIRECT=""
if $(validateBaseName $OUTPUT_FILE); then
    if [ "$OUTPUT_FILE" != "none" ] ; then
        OUTPUT_DIR=$(cd "$(dirname "/tmp/sd/record/$OUTPUT_FILE")"; pwd)
        OUTPUT_DIR=$(echo "$OUTPUT_DIR" | cut -c1-14)
        if [ "$OUTPUT_DIR" == "/tmp/sd/record" ]; then
            REDIRECT="yes"
        fi
    fi
fi

if [ "$WATERMARK" == "yes" ] ; then
    WATERMARK="-w"
elif [ "$WATERMARK" == "no" ] ; then
    WATERMARK=""
fi

# Several clients (Home Assistant, Frigate, UniFi, browsers) polling at the
# same time used to start one imggrabber each: decoding H.264 several times in
# parallel exhausts the RAM of the camera. Now only one imggrabber runs at a
# time and a fresh picture (younger than SNAPSHOT_CACHE seconds) is shared.
CACHE_AGE=$(grep -w ^SNAPSHOT_CACHE $YI_HACK_PREFIX/etc/system.conf | cut -d= -f2)
case "$CACHE_AGE" in ''|*[!0-9]*) CACHE_AGE=2 ;; esac
RES_NAME=${RES#-r }
CACHE=/tmp/snapshot_${RES_NAME}${WATERMARK:+_wm}.jpg
LOCK=/tmp/snapshot.lock
FALLBACK=$YI_HACK_PREFIX/etc/fallback.jpg

cache_younger_than()
{
    [ -s $CACHE ] && [ -f $CACHE.ts ] || return 1
    read -r TS < $CACHE.ts
    case "$TS" in ''|*[!0-9]*) return 1 ;; esac
    NOW=$(date +%s)
    [ $((NOW - TS)) -le $1 ]
}

cache_fresh()
{
    cache_younger_than $CACHE_AGE
}

get_snapshot()
{
    if [ -f /tmp/snapshot.disabled ]; then
        SNAP=$FALLBACK
        return
    fi
    if cache_fresh; then
        SNAP=$CACHE
        return
    fi
    # Remove a lock left by a killed request
    if [ -d $LOCK ] && [ -n "$(find $LOCK -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        rmdir $LOCK 2>/dev/null
    fi
    if mkdir $LOCK 2>/dev/null; then
        imggrabber -m $MODEL $RES $WATERMARK > $CACHE.tmp 2>/dev/null
        if [ -s $CACHE.tmp ]; then
            mv -f $CACHE.tmp $CACHE
            date +%s > $CACHE.ts
        else
            rm -f $CACHE.tmp
        fi
        rmdir $LOCK
    else
        # Another request is grabbing: wait for it (max ~6 s)
        N=0
        while [ -d $LOCK ] && [ $N -lt 30 ]; do
            sleep 0.2
            N=$((N+1))
        done
    fi
    # Never hand out an old picture as if it were live: if the grabber keeps
    # failing, clients get the fallback image instead of a frozen frame
    if [ -s $CACHE ] && cache_younger_than 30; then
        SNAP=$CACHE
    else
        SNAP=$FALLBACK
    fi
}

get_snapshot

if [ "$REDIRECT" == "yes" ] ; then
    if [ "$BASE64" == "no" ] ; then
        cat $SNAP > /tmp/sd/record/$OUTPUT_FILE
    elif [ "$BASE64" == "yes" ] ; then
        base64 $SNAP > /tmp/sd/record/$OUTPUT_FILE
    fi
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "false"
    printf "}"
else
    if [ "$BASE64" == "no" ] ; then
        printf "Content-type: image/jpeg\r\n"
        printf "Cache-Control: no-store\r\n\r\n"
        cat $SNAP
    elif [ "$BASE64" == "yes" ] ; then
        printf "Content-type: image/jpeg;base64\r\n"
        printf "Cache-Control: no-store\r\n\r\n"
        base64 $SNAP
    fi
fi
