#!/bin/bash
# Launch CS2 through the running, logged in Steam client.
# Backend comes from CS2MAC_BACKEND (vulkan | dxvk | wined3d | d3dmetal); see scripts/backend.sh.
# Extra arguments are passed to cs2.exe (e.g. +map de_dust2).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$CS2_DIR/game/bin/win64" || { echo "CS2 not installed at $CS2_DIR"; exit 1; }
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"
api=()
case "$CS2MAC_BACKEND" in
  vulkan) api=(-vulkan) ;;
  dxvk|wined3d|d3dmetal) api=() ;;
  *) echo "unknown CS2MAC_BACKEND=$CS2MAC_BACKEND"; exit 1 ;;
esac
# Default is borderless fullscreen: a window the size of the main display in points. Exclusive
# fullscreen (CS2MAC_FULLSCREEN=1) presents black with D3DMetal; CS2MAC_WINDOWED=1 gives a normal window.
if [ -z "${CS2MAC_WIDTH:-}" ] && [ "${CS2MAC_WINDOWED:-0}" != 1 ]; then
    screen="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame; f.size.width+"x"+f.size.height')"
    CS2MAC_WIDTH="${screen%x*}"; CS2MAC_HEIGHT="${screen#*x}"
fi
res=(-w "${CS2MAC_WIDTH:-1280}" -h "${CS2MAC_HEIGHT:-720}")
mode=(-windowed -noborder)
[ "${CS2MAC_WINDOWED:-0}" = 1 ] && mode=(-windowed)
[ "${CS2MAC_FULLSCREEN:-0}" = 1 ] && mode=(-fullscreen)
# Cap fps at the main display's refresh rate: uncapped frames on a 60 Hz panel without vsync are shown
# unevenly by the compositor and read as stutter. CS2MAC_FPS_MAX=0 uncaps.
hz="$(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Main Display: Yes/{print last} {if ($0 ~ /@ [0-9.]+Hz/) {sub(/.*@ /,""); sub(/\..*/,""); last=$0}}' | head -1)"
fps=(+fps_max "${CS2MAC_FPS_MAX:-${hz:-0}}")
args=("${api[@]}" -nojoy -novid -condebug "${res[@]}" "${mode[@]}" "${fps[@]}" "$@")
# Launching cs2.exe directly puts it in insecure mode (no VAC servers). By default hand the launch to
# the running Steam client instead; CS2MAC_DIRECT=1 keeps the direct launch (bench uses it for logs).
[ "${CS2MAC_DIRECT:-0}" = 1 ] && exec "$WINE" cs2.exe -steam "${args[@]}"
exec "$WINE" "$STEAM_DIR/steam.exe" -applaunch 730 "${args[@]}"
