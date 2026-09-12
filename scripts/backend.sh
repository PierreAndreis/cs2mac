#!/usr/bin/env bash
# Switch the D3D11 backend inside the Wine prefix and the bundled Wine 11 install.
#   backend.sh wined3d   - stock Wine 11 d3d11/dxgi (wined3d -> OpenGL)
#   backend.sh dxvk      - DXVK-macOS 1.10.3 d3d11/d3d10core in system32 (Vulkan -> MoltenVK)
#   backend.sh d3dmetal  - GPTK D3DMetal d3d11/dxgi via the gptk shim (Metal)
#   backend.sh status
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/env.sh"
SYS32="$WINEPREFIX/drive_c/windows/system32"
WLIB="$WINE_ROOT/lib/wine"
mode="${1:-status}"

set_override() { # name value|-
    if [ "$2" = "-" ]; then "$WINE" reg delete 'HKCU\Software\Wine\DllOverrides' /v "$1" /f >/dev/null 2>&1 || true
    else "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v "$1" /t REG_SZ /d "$2" /f >/dev/null; fi
}

restore_builtins() {
    for d in d3d11 dxgi d3d10 d3d12 nvapi64; do
        [ -f "$WLIB/x86_64-windows/$d.dll.wine11" ] && mv -f "$WLIB/x86_64-windows/$d.dll.wine11" "$WLIB/x86_64-windows/$d.dll"
        [ -f "$WLIB/x86_64-unix/$d.so.wine11" ] && mv -f "$WLIB/x86_64-unix/$d.so.wine11" "$WLIB/x86_64-unix/$d.so"
        [ -L "$WLIB/x86_64-unix/$d.so" ] && rm -f "$WLIB/x86_64-unix/$d.so" && [ -f "$WLIB/x86_64-unix/$d.so.wine11" ] && mv "$WLIB/x86_64-unix/$d.so.wine11" "$WLIB/x86_64-unix/$d.so"
    done
    rm -f "$WLIB/x86_64-windows/gptk.dll" "$WLIB/x86_64-unix/gptk.so" "$WLIB/x86_64-unix/D3DMetal.framework"
    rm -f "$SYS32"/{d3d11,dxgi,d3d10,d3d12,d3d10core,gptk,nvapi64}.dll
    # put the stock fake dlls back so the prefix looks normal
    for d in d3d11 dxgi d3d10 d3d12 d3d10core; do
        [ -f "$WLIB/x86_64-windows/$d.dll" ] && cp "$WLIB/x86_64-windows/$d.dll" "$SYS32/$d.dll"
    done
    set_override d3d11 -; set_override dxgi -; set_override d3d10core -
}

case "$mode" in
  wined3d)
    restore_builtins ;;
  dxvk)
    restore_builtins
    cp "$HERE/../vendor/dxvk-macos/x64/d3d11.dll" "$HERE/../vendor/dxvk-macos/x64/d3d10core.dll" "$SYS32/"
    set_override d3d11 native; set_override d3d10core native ;;
  d3dmetal)
    restore_builtins
    B="$HERE/../build/d3dmetal"
    [ -f "$B/gptk.dll" ] || { echo "run scripts/build-d3dmetal-shim.sh first" >&2; exit 1; }
    for d in d3d11 dxgi; do
        mv "$WLIB/x86_64-windows/$d.dll" "$WLIB/x86_64-windows/$d.dll.wine11"
        cp "$B/x86_64-windows/$d.dll" "$WLIB/x86_64-windows/$d.dll"
        [ -f "$WLIB/x86_64-unix/$d.so" ] && mv "$WLIB/x86_64-unix/$d.so" "$WLIB/x86_64-unix/$d.so.wine11"
        ln -sf "$GPTK_LIB/external/libd3dshared.dylib" "$WLIB/x86_64-unix/$d.so"
        cp "$B/x86_64-windows/$d.dll" "$SYS32/$d.dll"
    done
    cp "$B/gptk.dll" "$WLIB/x86_64-windows/gptk.dll"
    cp "$B/gptk.dll" "$SYS32/gptk.dll"
    ln -sfn "$GPTK_LIB/external/D3DMetal.framework" "$WLIB/x86_64-unix/D3DMetal.framework"
    set_override d3d11 builtin; set_override dxgi builtin; set_override d3d10core - ;;
  status) ;;
  *) echo "usage: backend.sh wined3d|dxvk|d3dmetal|status" >&2; exit 2 ;;
esac

echo "Wine lib d3d11.dll: $(stat -f %z "$WLIB/x86_64-windows/d3d11.dll") bytes $( [ -f "$WLIB/x86_64-windows/d3d11.dll.wine11" ] && echo '(D3DMetal)' || echo '(stock)')"
echo "system32 d3d11.dll: $(stat -f %z "$SYS32/d3d11.dll" 2>/dev/null || echo missing) bytes"
echo "unix d3d11.so -> $(readlink "$WLIB/x86_64-unix/d3d11.so" || echo builtin)"
"$WINE" reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null | tr -d '\r' | grep -E "d3d|dxgi" || echo "no overrides"
