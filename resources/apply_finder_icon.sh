#!/bin/sh
set -eu

: "${APP_BUNDLE:?APP_BUNDLE is required}"
: "${ICON_MASTER:?ICON_MASTER is required}"
: "${SIPS:=/usr/bin/sips}"
: "${DEREZ:=/usr/bin/DeRez}"
: "${REZ:=/usr/bin/Rez}"
: "${SETFILE:=/usr/bin/SetFile}"

tmp_png="${TMPDIR:-/tmp}/artforge-custom-icon-$$.png"
tmp_rsrc="${TMPDIR:-/tmp}/artforge-custom-icon-$$.rsrc"
cleanup() {
    rm -f "$tmp_png" "$tmp_rsrc"
}
trap cleanup EXIT

cp "$ICON_MASTER" "$tmp_png"
"$SIPS" -i "$tmp_png" >/dev/null
"$DEREZ" -only icns "$tmp_png" > "$tmp_rsrc"

icon_file="${APP_BUNDLE}/Icon$(printf '\r')"
"$REZ" -append "$tmp_rsrc" -o "$icon_file"
"$SETFILE" -a C "$APP_BUNDLE"
"$SETFILE" -a V "$icon_file"
touch "$APP_BUNDLE"
