#!/bin/bash
# Launch CS2 directly (Steam must already be running and logged in).
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
res=(-w "${CS2MAC_WIDTH:-1280}" -h "${CS2MAC_HEIGHT:-720}")
mode=(-windowed); [ "${CS2MAC_FULLSCREEN:-0}" = 1 ] && mode=(-fullscreen)
exec "$WINE" cs2.exe -steam "${api[@]}" -nojoy -novid -condebug "${res[@]}" "${mode[@]}" "$@"
