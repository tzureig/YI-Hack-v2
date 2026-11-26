#!/bin/sh

# Automatic firmware update
#
#   auto_update.sh check     only look for a new release (result in etc/auto_update.status)
#   auto_update.sh install   look for a new release and install it (reboots the camera)
#
# Releases come from GitHub (AUTO_UPDATE_REPO, default tzureig/YI-Hack-Tiz).
# Every release must contain MODEL_TAG.tgz and SHA256SUMS.txt: the package is
# installed only if its SHA-256 matches. The configuration is kept.

YI_HACK_PREFIX="/tmp/sd/yi-hack"
CONF_FILE="$YI_HACK_PREFIX/etc/system.conf"
STATUS_FILE="$YI_HACK_PREFIX/etc/auto_update.status"
LOG_FILE="$YI_HACK_PREFIX/etc/auto_update.log"
WORK_DIR="/tmp/sd/.auto_update"
WGET="$YI_HACK_PREFIX/usr/bin/wget"
SHA256SUM="$YI_HACK_PREFIX/usr/bin/sha256sum"
LOCK="/tmp/auto_update.lock"

export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/app/localbin:/home/base:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin:/tmp/sd/yi-hack/usr/bin:/tmp/sd/yi-hack/usr/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/qigan/lib:/home/app/locallib:/tmp/sd:/tmp/sd/gdb:/tmp/sd/yi-hack/lib

get_config()
{
    grep -w "^$1" $CONF_FILE | cut -d "=" -f2-
}

log()
{
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
    # Keep the log on the SD card short
    if [ $(grep -c ^ $LOG_FILE) -gt 100 ]; then
        $YI_HACK_PREFIX/usr/bin/tail -n 50 $LOG_FILE > $LOG_FILE.tmp && mv $LOG_FILE.tmp $LOG_FILE
    fi
    if [ "$SYSLOG" == "yes" ]; then
        logger -t auto_update "$1"
    fi
}

status()
{
    # state|installed|available|time
    echo "$1|$FW_VERSION|$2|$(date +'%Y-%m-%d %H:%M')" > $STATUS_FILE
}

cleanup()
{
    rm -rf $WORK_DIR
    rmdir $LOCK 2>/dev/null
}

ACTION="$1"
[ "$ACTION" == "check" ] || [ "$ACTION" == "install" ] || { echo "usage: $0 check|install"; exit 1; }

SYSLOG=no
[ ! -z "$(get_config SYSLOG_SERVER)" ] && [ -S /dev/log ] && SYSLOG=yes

REPO=$(get_config AUTO_UPDATE_REPO)
case "$REPO" in
    ''|*[!A-Za-z0-9._/-]*|*/*/*) REPO="tzureig/YI-Hack-Tiz" ;;
esac

MODEL_SUFFIX=$(cat $YI_HACK_PREFIX/model_suffix)
FW_VERSION=$(cat $YI_HACK_PREFIX/version)

if ! mkdir $LOCK 2>/dev/null; then
    echo "Another update is running"
    exit 1
fi
trap cleanup EXIT

# Wait a bit for the network after a reboot / spread the requests
TRIES=0
LATEST=""
while [ -z "$LATEST" ] && [ $TRIES -lt 3 ]; do
    LATEST=$($WGET -q -T 30 -O - "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
    TRIES=$((TRIES+1))
    [ -z "$LATEST" ] && sleep 20
done

case "$LATEST" in
    '')
        log "Check failed: no answer from github ($REPO)"
        status "error" ""
        exit 1
        ;;
    *[!A-Za-z0-9._+-]*)
        log "Check failed: invalid release name"
        status "error" ""
        exit 1
        ;;
esac

if [ "$LATEST" == "$FW_VERSION" ]; then
    log "Up to date ($FW_VERSION)"
    status "uptodate" "$LATEST"
    exit 0
fi

log "New firmware available: $LATEST (installed $FW_VERSION)"
status "available" "$LATEST"

if [ "$ACTION" == "check" ]; then
    exit 0
fi

# Install
FREE_KB=$(df -k /tmp/sd | awk 'NR==2{print $4}')
case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0 ;; esac
if [ $FREE_KB -lt 40000 ]; then
    log "Not enough free space on the SD card (${FREE_KB} KB), update skipped"
    status "error" "$LATEST"
    exit 1
fi

PKG="${MODEL_SUFFIX}_${LATEST}.tgz"
BASE_URL="https://github.com/$REPO/releases/download/$LATEST"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR || exit 1

log "Downloading $PKG"
if ! $WGET -q -T 60 -O $PKG "$BASE_URL/$PKG" || [ ! -s $PKG ]; then
    log "Download failed: $BASE_URL/$PKG"
    status "error" "$LATEST"
    exit 1
fi
if ! $WGET -q -T 60 -O SHA256SUMS.txt "$BASE_URL/SHA256SUMS.txt" || [ ! -s SHA256SUMS.txt ]; then
    log "Download failed: SHA256SUMS.txt (update refused without checksum)"
    status "error" "$LATEST"
    exit 1
fi

EXPECTED=$(grep " \*\?$PKG\$" SHA256SUMS.txt | awk '{print $1}' | head -n1)
ACTUAL=$($SHA256SUM $PKG | awk '{print $1}')
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    log "Checksum mismatch for $PKG, update refused"
    status "error" "$LATEST"
    exit 1
fi
log "Checksum ok"

# Same steps as the online upgrade of the web interface: system.sh completes
# the upgrade at the next boot (fw_upgrade_in_progress)
rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
mkdir -p /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
cp -rf $YI_HACK_PREFIX/etc/* /tmp/sd/.fw_upgrade.conf/
rm -f /tmp/sd/.fw_upgrade.conf/*.tar.gz
if ! tar zxf $PKG -C /tmp/sd/.fw_upgrade || [ ! -f /tmp/sd/.fw_upgrade/yi-hack/version ]; then
    log "Package could not be extracted, update refused"
    rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
    status "error" "$LATEST"
    exit 1
fi
if [ "$(cat /tmp/sd/.fw_upgrade/yi-hack/model_suffix)" != "$MODEL_SUFFIX" ]; then
    log "Package is for another model, update refused"
    rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
    status "error" "$LATEST"
    exit 1
fi
mkdir -p /tmp/sd/.fw_upgrade/yi-hack/etc
cp -rf /tmp/sd/.fw_upgrade.conf/* /tmp/sd/.fw_upgrade/yi-hack/etc/
rm -rf /tmp/sd/.fw_upgrade.conf
rm -f /tmp/sd/.fw_upgrade/yi-hack/etc/auto_update.status
touch /tmp/sd/.fw_upgrade/yi-hack/fw_upgrade_in_progress

log "Installing $LATEST, rebooting"
status "installing" "$LATEST"
echo "$(date +'%Y-%m-%d %H:%M:%S') - firmware update to $LATEST" > /tmp/sd/.fw_upgrade/yi-hack/etc/wd_last_reboot
cd /
rm -rf $WORK_DIR
sync
sync
sleep 1
killall -q mqttv4
reboot
