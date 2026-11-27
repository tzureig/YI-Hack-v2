#!/bin/sh

# Firmware update from GitHub releases
#
#   auto_update.sh check     only look for a new release (result in etc/auto_update.status)
#   auto_update.sh prepare   download, verify and unpack a new release (no reboot):
#                            the next boot completes the upgrade (used by the web interface)
#   auto_update.sh install   prepare + reboot (used by cron at night)
#
# Releases come from AUTO_UPDATE_REPO (default tzureig/YI-Hack-v2).
# AUTO_UPDATE_CHANNEL=stable uses the latest release, beta also pre-releases
# (for a test camera). Only a newer version is installed.
#
# Every release contains MODEL_TAG.tgz, SHA256SUMS.txt and SHA256SUMS.txt.sig.
# The package is installed only if
#   1. SHA256SUMS.txt is signed with the release key (Ed25519, checked by
#      fwverify with the public key compiled into the firmware) and
#   2. the SHA-256 of the package matches SHA256SUMS.txt and
#   3. the package is for this camera model.
# Busybox wget does not check TLS certificates, so the signature is what
# protects against a manipulated download. The configuration is kept.
#
# Exit code: 0 = done / up to date, 1 = error, 3 = prepared (prepare only)

YI_HACK_PREFIX="/tmp/sd/yi-hack"
CONF_FILE="$YI_HACK_PREFIX/etc/system.conf"
STATUS_FILE="$YI_HACK_PREFIX/etc/auto_update.status"
LOG_FILE="$YI_HACK_PREFIX/etc/auto_update.log"
WORK_DIR="/tmp/sd/.auto_update"
WGET="$YI_HACK_PREFIX/usr/bin/wget"
SHA256SUM="$YI_HACK_PREFIX/usr/bin/sha256sum"
FWVERIFY="$YI_HACK_PREFIX/bin/fwverify"
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
        tail -n 50 $LOG_FILE > $LOG_FILE.tmp && mv $LOG_FILE.tmp $LOG_FILE
    fi
    if [ "$SYSLOG" == "yes" ]; then
        logger -t auto_update "$1"
    fi
    # Message for the caller (web interface)
    LAST_MSG="$1"
}

status()
{
    # state|installed|available|time
    echo "$1|$FW_VERSION|$2|$(date +'%Y-%m-%d %H:%M')" > $STATUS_FILE
}

fail()
{
    log "$1"
    status "error" "$LATEST"
    rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
    echo "$1"
    exit 1
}

cleanup()
{
    rm -rf $WORK_DIR
    rmdir $LOCK 2>/dev/null
}

# version_gt A B: true if A is newer than B ("1.0.10" > "1.0.9",
# "1.1.0" > "1.1.0-beta1", anything > "0.3.7" of the original project)
version_gt()
{
    [ "$1" == "$2" ] && return 1
    echo "$1 $2" | awk '
    function cmp(a, b,   na, nb, pa, pb, i, n, x, y) {
        # split off a pre-release suffix ("-beta1")
        pa = ""; pb = ""
        if (index(a, "-")) { pa = substr(a, index(a, "-") + 1); a = substr(a, 1, index(a, "-") - 1) }
        if (index(b, "-")) { pb = substr(b, index(b, "-") + 1); b = substr(b, 1, index(b, "-") - 1) }
        na = split(a, x, "."); nb = split(b, y, ".")
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            if ((x[i] + 0) > (y[i] + 0)) return 1
            if ((x[i] + 0) < (y[i] + 0)) return -1
        }
        if (pa == pb) return 0
        if (pa == "") return 1      # 1.1.0 > 1.1.0-beta1
        if (pb == "") return -1
        return (pa > pb) ? 1 : -1
    }
    { exit (cmp($1, $2) > 0) ? 0 : 1 }'
}

ACTION="$1"
case "$ACTION" in
    check|prepare|install) ;;
    *) echo "usage: $0 check|prepare|install"; exit 1 ;;
esac

SYSLOG=no
[ ! -z "$(get_config SYSLOG_SERVER)" ] && [ -S /dev/log ] && SYSLOG=yes

REPO=$(get_config AUTO_UPDATE_REPO)
case "$REPO" in
    ''|*[!A-Za-z0-9._/-]*|*/*/*) REPO="tzureig/YI-Hack-v2" ;;
esac
CHANNEL=$(get_config AUTO_UPDATE_CHANNEL)
[ "$CHANNEL" == "beta" ] || CHANNEL=stable

MODEL_SUFFIX=$(cat $YI_HACK_PREFIX/model_suffix)
FW_VERSION=$(cat $YI_HACK_PREFIX/version)

if ! mkdir $LOCK 2>/dev/null; then
    # Remove a lock left by a killed run (older than 30 minutes)
    if [ -n "$(find $LOCK -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
        rmdir $LOCK 2>/dev/null
        mkdir $LOCK 2>/dev/null
    else
        echo "Another update is running"
        exit 1
    fi
fi
trap cleanup EXIT

# stable: /releases/latest skips pre-releases and drafts
# beta:   /releases lists the newest release first, pre-releases included
if [ "$CHANNEL" == "beta" ]; then
    API_URL="https://api.github.com/repos/$REPO/releases?per_page=1"
else
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi

TRIES=0
LATEST=""
while [ -z "$LATEST" ] && [ $TRIES -lt 3 ]; do
    LATEST=$($WGET -q -T 30 -O - "$API_URL" 2>/dev/null | awk -F'"tag_name"' 'NF > 1 { split($2, a, "\""); print a[2]; exit }')
    TRIES=$((TRIES+1))
    [ -z "$LATEST" ] && [ $TRIES -lt 3 ] && sleep 20
done

case "$LATEST" in
    '')
        fail "Check failed: no answer from github ($REPO). Is the repository public?"
        ;;
    *[!A-Za-z0-9._+-]*)
        LATEST=""
        fail "Check failed: invalid release name"
        ;;
esac

if ! version_gt "$LATEST" "$FW_VERSION"; then
    log "Up to date ($FW_VERSION, newest $CHANNEL release $LATEST)"
    status "uptodate" "$LATEST"
    echo "No new firmware available."
    exit 0
fi

log "New firmware available: $LATEST (installed $FW_VERSION, channel $CHANNEL)"
status "available" "$LATEST"

if [ "$ACTION" == "check" ]; then
    exit 0
fi

# Download and verify
FREE_KB=$(df -k /tmp/sd | awk 'NR==2{print $4}')
case "$FREE_KB" in ''|*[!0-9]*) FREE_KB=0 ;; esac
if [ $FREE_KB -lt 40000 ]; then
    fail "Not enough free space on the SD card (${FREE_KB} KB), update skipped"
fi

if [ ! -x $FWVERIFY ]; then
    fail "fwverify missing, update refused"
fi

PKG="${MODEL_SUFFIX}_${LATEST}.tgz"
BASE_URL="https://github.com/$REPO/releases/download/$LATEST"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR || exit 1

for F in SHA256SUMS.txt SHA256SUMS.txt.sig; do
    if ! $WGET -q -T 60 -O $F "$BASE_URL/$F" || [ ! -s $F ]; then
        fail "Download failed: $F (update refused without signed checksums)"
    fi
done
if ! $FWVERIFY SHA256SUMS.txt SHA256SUMS.txt.sig >/dev/null 2>&1; then
    fail "Signature of SHA256SUMS.txt is invalid, update refused"
fi
log "Signature ok"

EXPECTED=$(grep " \*\?$PKG\$" SHA256SUMS.txt | awk '{print $1}' | head -n1)
if [ -z "$EXPECTED" ]; then
    fail "No package for this model ($MODEL_SUFFIX) in release $LATEST"
fi

log "Downloading $PKG"
if ! $WGET -q -T 120 -O $PKG "$BASE_URL/$PKG" || [ ! -s $PKG ]; then
    fail "Download failed: $BASE_URL/$PKG"
fi
ACTUAL=$($SHA256SUM $PKG | awk '{print $1}')
if [ "$EXPECTED" != "$ACTUAL" ]; then
    fail "Checksum mismatch for $PKG, update refused"
fi
log "Checksum ok"

# Same steps as the online upgrade of the web interface: system.sh completes
# the upgrade at the next boot (fw_upgrade_in_progress)
rm -rf /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
mkdir -p /tmp/sd/.fw_upgrade /tmp/sd/.fw_upgrade.conf
cp -rf $YI_HACK_PREFIX/etc/* /tmp/sd/.fw_upgrade.conf/
rm -f /tmp/sd/.fw_upgrade.conf/*.tar.gz
if ! tar zxf $PKG -C /tmp/sd/.fw_upgrade || [ ! -f /tmp/sd/.fw_upgrade/yi-hack/version ]; then
    fail "Package could not be extracted, update refused"
fi
if [ "$(cat /tmp/sd/.fw_upgrade/yi-hack/model_suffix)" != "$MODEL_SUFFIX" ]; then
    fail "Package is for another model, update refused"
fi
mkdir -p /tmp/sd/.fw_upgrade/yi-hack/etc
cp -rf /tmp/sd/.fw_upgrade.conf/* /tmp/sd/.fw_upgrade/yi-hack/etc/
rm -rf /tmp/sd/.fw_upgrade.conf
rm -f /tmp/sd/.fw_upgrade/yi-hack/etc/auto_update.status
touch /tmp/sd/.fw_upgrade/yi-hack/fw_upgrade_in_progress
echo "$(date +'%Y-%m-%d %H:%M:%S') - firmware update to $LATEST" > /tmp/sd/.fw_upgrade/yi-hack/etc/wd_last_reboot
cd /
rm -rf $WORK_DIR
sync

status "installing" "$LATEST"
if [ "$ACTION" == "prepare" ]; then
    log "Prepared $LATEST, installed at the next reboot"
    echo "Download of $LATEST completed and verified, rebooting and upgrading."
    exit 3
fi

log "Installing $LATEST, rebooting"
sync
sleep 1
killall -q mqttv4
reboot
