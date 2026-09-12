#!/bin/bash
# Install a CS2 workshop item into the Wine prefix's Steam so the game can mount it.
#
#   workshop.sh <workshop id>...     (Steam must be stopped: ./cs2mac stop)
#
# Subscribing from the Steam client inside Wine is clumsy, so the item is fetched with steamcmd
# (vendor/steamcmd, anonymous login unless STEAMCMD_LOGIN="user pass" is set), copied into
# <prefix>/Steam/steamapps/workshop/content/730/<id>/ and registered in appworkshop_730.acf.
# The registration matters: CS2 only mounts the map vpk nested inside an addon for items Steam
# knows about ("map_workshop <id> <map>" fails with "Failed to mount world vpk" otherwise).
#
# Useful items:  3240880604  FPS benchmark flythrough (map de_dust2)      ./cs2mac play d3dmetal 1280x720 +map_workshop 3240880604 de_dust2
#                3070244462  Aim Botz shooting range (map aim_botz)       ./cs2mac play d3dmetal 1280x720 +map_workshop 3070244462 aim_botz
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh"
mkdir -p "$ROOT/build/logs"
[ $# -gt 0 ] || { sed -n '2,14p' "$0"; exit 2; }
pgrep -f "steam.exe" >/dev/null && { echo "stop Steam first (./cs2mac stop), it rewrites the workshop manifest on exit" >&2; exit 1; }

CMD="$ROOT/vendor/steamcmd/steamcmd.sh"
if [ ! -x "$CMD" ]; then
    mkdir -p "$ROOT/vendor/steamcmd" && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz | tar -xz -C "$ROOT/vendor/steamcmd"
fi
SRC="$HOME/Library/Application Support/Steam/steamapps/workshop"
DST="$STEAM_DIR/steamapps/workshop"
args=()
for id in "$@"; do [ -d "$SRC/content/730/$id" ] || args+=(+workshop_download_item 730 "$id"); done
if [ ${#args[@]} -gt 0 ]; then
    echo "[workshop] downloading with steamcmd: $*"
    "$CMD" +@sSteamCmdForcePlatformType windows +login ${STEAMCMD_LOGIN:-anonymous} "${args[@]}" +quit > "$ROOT/build/logs/steamcmd-workshop.log" 2>&1 ||
        { echo "steamcmd failed, see build/logs/steamcmd-workshop.log (set STEAMCMD_LOGIN='user pass' if anonymous is refused)" >&2; exit 1; }
fi
mkdir -p "$DST/content/730"
for id in "$@"; do
    [ -d "$SRC/content/730/$id" ] || { echo "steamcmd did not produce $id" >&2; exit 1; }
    rm -rf "$DST/content/730/$id" && cp -R "$SRC/content/730/$id" "$DST/content/730/$id"
    echo "[workshop] $id: $(grep '"title"' "$DST/content/730/$id/publish_data.txt" 2>/dev/null | cut -d'"' -f4)"
done
python3 - "$SRC/appworkshop_730.acf" "$DST/appworkshop_730.acf" "$@" <<'PY'
import re
import sys

src, dst, ids = sys.argv[1], sys.argv[2], sys.argv[3:]
acf = open(src).read()
out = open(dst).read() if __import__("os").path.exists(dst) else acf.replace('"SizeOnDisk"\t\t"%s"' % re.search(r'"SizeOnDisk"\t\t"(\d+)"', acf).group(1), '"SizeOnDisk"\t\t"0"')


def block(section, text, wid):
    sec = text[text.index('"%s"' % section):]
    m = re.search(r'\n\t\t"%s"\n\t\t\{.*?\n\t\t\}' % wid, sec, re.S)
    return m.group(0) if m else None


for section in ("WorkshopItemsInstalled", "WorkshopItemDetails"):
    for wid in ids:
        entry = block(section, acf, wid)
        if entry is None:
            sys.exit("%s missing from %s" % (wid, src))
        if section == "WorkshopItemDetails":
            entry = entry.replace('\t\t\t"timetouched"', '\t\t\t"subscribedby"\t\t"0"\n\t\t\t"timetouched"', 1) if '"subscribedby"' not in entry else entry
        old = block(section, out, wid)
        head = out.index('"%s"' % section)
        if old:
            out = out[:head] + out[head:].replace(old, entry, 1)
        else:
            close = out.index("\n\t}", head)
            out = out[:close] + entry + out[close:]
open(dst, "w").write(out)
print("[workshop] registered", *ids, "in", dst)
PY
