#!/bin/bash

# Download a source archive reliably
#
#   fetch.sh OUTFILE SHA256|- URL [URL ...]
#
# Tries every URL (3 attempts each) until the file is a valid archive and, if
# given, matches the SHA-256. Some servers answer a missing file with an HTML
# page and HTTP 200 (zlib.net does this for old versions): a plain "wget || wget"
# then "succeeds" with garbage and the build fails later in tar.

OUT=$1
SHA=$2
shift 2

if [ -z "$OUT" ] || [ -z "$SHA" ] || [ $# -eq 0 ]; then
    echo "usage: $0 OUTFILE SHA256|- URL [URL ...]" >&2
    exit 1
fi

valid()
{
    local F=$1
    [ -s "$F" ] || return 1
    case "$OUT" in
        *.tar.gz|*.tgz) gzip -t "$F" 2>/dev/null || return 1 ;;
        *.tar.bz2)      bzip2 -t "$F" 2>/dev/null || return 1 ;;
        *.tar.xz)       xz -t "$F" 2>/dev/null || return 1 ;;
        *.zip)          unzip -tq "$F" >/dev/null 2>&1 || return 1 ;;
    esac
    if [ "$SHA" != "-" ]; then
        [ "$(sha256sum "$F" | cut -d' ' -f1)" == "$SHA" ] || { echo "fetch.sh: wrong SHA-256 for $F" >&2; return 1; }
    fi
    return 0
}

if valid "$OUT"; then
    exit 0
fi

for URL in "$@"; do
    for TRY in 1 2 3; do
        rm -f "$OUT.part"
        echo "fetch.sh: $URL (attempt $TRY)"
        if wget -q -T 60 -O "$OUT.part" "$URL" && valid "$OUT.part"; then
            mv -f "$OUT.part" "$OUT"
            exit 0
        fi
        sleep $((TRY * 5))
    done
done

rm -f "$OUT.part"
echo "fetch.sh: could not download a valid $OUT" >&2
exit 1
