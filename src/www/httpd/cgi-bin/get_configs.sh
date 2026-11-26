#!/bin/sh

get_conf_type()
{
    CONF="$(echo $QUERY_STRING | cut -d'=' -f1)"
    VAL="$(echo $QUERY_STRING | cut -d'=' -f2)"

    if [ "$CONF" == "conf" ] ; then
        echo $VAL
    fi
}

YI_HACK_PREFIX="/tmp/sd/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

printf "Content-type: application/json\r\n\r\n"

CONF_TYPE="$(get_conf_type)"
CONF_FILE=""

if [ "$CONF_TYPE" == "mqtt" ] ; then
    CONF_FILE="$YI_HACK_PREFIX/etc/mqttv4.conf"
else
    CONF_FILE="$YI_HACK_PREFIX/etc/$CONF_TYPE.conf"
fi

printf "{\n"

PROXY_LIST="0"
PROXYCHAINS_SERVERS=
if [ "$CONF_TYPE" == "proxychains" ] ; then
    while IFS= read -r LINE ; do
        if [ "$PROXY_LIST" == "1" ] ; then
            PROXYCHAINS_SERVERS=${PROXYCHAINS_SERVERS}${LINE}";"
        fi
        if [ "$LINE" == "[ProxyList]" ] ; then
            PROXY_LIST="1"
        fi
    done < "$CONF_FILE"
    PROXYCHAINS_SERVERS=${PROXYCHAINS_SERVERS%?}
    echo -e \"PROXYCHAINS_SERVERS\":\"$PROXYCHAINS_SERVERS\",
else
    # Secrets never leave the camera: a set password is sent as "********"
    # (set_configs.sh keeps the stored value when it gets it back), hashes are not sent at all
    sed '/^#/d; /^$/d; /^[A-Z_]*_HASH=/d; s/^\([A-Z_]*PASSWORD\)=..*$/\1=********/; s/\\/\\\\/g; s/\"/\\"/g; s/\([^=]*\)=\(.*\)/"\1":"\2",/' "$CONF_FILE"
    if [ "$CONF_TYPE" == "system" ] && [ -n "$(grep '^SSH_PASSWORD_HASH=..' "$CONF_FILE")" ]; then
        printf "\"%s\":\"%s\",\n" "SSH_PASSWORD" "********"
    fi
fi

if [ "$CONF_TYPE" == "system" ] ; then
    printf "\"%s\":\"%s\",\n"  "HOSTNAME" "$(cat $YI_HACK_PREFIX/etc/hostname | sed -r 's/\\/\\\\/g;s/"/\\"/g;')"
fi

if [ "$CONF_TYPE" == "camera" ] ; then
    HOMEVER=$(cat /home/homever)
    printf "\"%s\":\"%s\",\n"  "HOMEVER" "$HOMEVER"
fi

# Empty values to "close" the json
printf "\"%s\":\"%s\"\n"  "NULL" "NULL"

printf "}"
