#!/usr/bin/env bash
# Shared environment for cs2mac. Source this, don't execute it.
# Everything here is tunable; see docs/TUNING.md for what each knob does.

CS2MAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
CS2MAC_HOME="${CS2MAC_HOME:-$HOME/Library/Application Support/cs2mac}"
export WINEPREFIX="${WINEPREFIX:-$CS2MAC_HOME/prefix}"

# Wine 11.17 (gcenx build, wow64, bundles MoltenVK) unpacked by scripts/setup.sh
export WINE_ROOT="${WINE_ROOT:-$CS2MAC_ROOT/vendor/wine-11.17/Wine Devel.app/Contents/Resources/wine}"
export WINE="${WINE:-$WINE_ROOT/bin/wine}"
export WINESERVER="${WINESERVER:-$WINE_ROOT/bin/wineserver}"

# Apple Game Porting Toolkit (only needed for the d3dmetal backend)
GPTK_APP="/Applications/Game Porting Toolkit.app/Contents/Resources/wine"
export GPTK_LIB="$GPTK_APP/lib"

export WINEDEBUG="${WINEDEBUG:--all}"
export WINEESYNC="${WINEESYNC:-1}"
export WINEMSYNC="${WINEMSYNC:-1}"

# Backend selection: vulkan (CS2 -vulkan -> MoltenVK), dxvk, d3dmetal
export CS2MAC_BACKEND="${CS2MAC_BACKEND:-vulkan}"

STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
CS2_DIR="$STEAM_DIR/steamapps/common/Counter-Strike Global Offensive"
