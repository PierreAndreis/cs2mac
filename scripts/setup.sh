#!/usr/bin/env bash
# One-shot setup for cs2mac. Idempotent: every step checks for its output first.
#
#   setup.sh            run every step
#   setup.sh <step>...  run only the named steps (deps wine dxvk moltenvk ntdll winemac gptk gamemode tools prefix steam webhelper steamcfg)
#
# Nothing proprietary is redistributed: Wine, DXVK and MoltenVK are fetched from
# their upstream releases, Steam from Valve, and D3DMetal comes from Apple's
# Game Porting Toolkit which you install yourself (brew cask, needs an Apple ID).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh"
DL="$ROOT/downloads"; V="$ROOT/vendor"; LOGS="$ROOT/build/logs"
mkdir -p "$DL" "$V" "$LOGS" "$ROOT/build"

WINE_TARBALL_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.17/wine-devel-11.17-osx64.tar.xz"
WINE_SRC_URL="https://dl.winehq.org/wine/source/11.x/wine-11.17.tar.xz"
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz"
MOLTENVK_REPO="https://github.com/KhronosGroup/MoltenVK.git"
MOLTENVK_COMMIT="4aaf714aa1b3e78e26ecfcefa9c75e9a576c500b"   # 1.4.3 development head, 2026-09-04
STEAM_URL="https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe"

log() { printf '\n[setup] %s\n' "$*"; }
fetch() { [ -f "$2" ] || curl -fL --retry 3 -o "$2" "$1"; }
x86() { arch -x86_64 "$@"; }
sign() { codesign -fs - "$1" >/dev/null 2>&1 || true; }

step_deps() {
    log "checking host dependencies"
    [ "$(uname -m)" = arm64 ] || { echo "cs2mac targets Apple Silicon"; exit 1; }
    xcode-select -p >/dev/null 2>&1 || { echo "run: xcode-select --install"; exit 1; }
    x86 /usr/bin/true 2>/dev/null || { echo "run: softwareupdate --install-rosetta --agree-to-license"; exit 1; }
    command -v brew >/dev/null || { echo "install Homebrew first"; exit 1; }
    brew list bison mingw-w64 cmake >/dev/null 2>&1 || brew install bison mingw-w64 cmake
}

step_wine() {
    log "Wine 11.17 (Gcenx build)"
    [ -x "$WINE" ] && return
    fetch "$WINE_TARBALL_URL" "$DL/wine-devel-11.17-osx64.tar.xz"
    mkdir -p "$V/wine-11.17" && tar -xJf "$DL/wine-devel-11.17-osx64.tar.xz" -C "$V/wine-11.17"
    [ -x "$WINE" ] || { echo "unexpected Wine layout under $V/wine-11.17"; exit 1; }
}

step_dxvk() {
    log "DXVK-macOS 1.10.3 (async)"
    [ -f "$V/dxvk-macos/x64/d3d11.dll" ] && return
    fetch "$DXVK_URL" "$DL/dxvk-macos.tar.gz"
    mkdir -p "$V/dxvk-macos" && tar -xzf "$DL/dxvk-macos.tar.gz" -C "$V/dxvk-macos" --strip-components=1
}

step_moltenvk() {
    log "MoltenVK 1.4.3 from source (universal) with the null-descriptor-set patch"
    local lib="$WINE_ROOT/lib/libMoltenVK.dylib"
    [ -f "$lib.wine11" ] && return
    [ -d "$V/MoltenVK/.git" ] || git clone "$MOLTENVK_REPO" "$V/MoltenVK"
    git -C "$V/MoltenVK" checkout -q "$MOLTENVK_COMMIT"
    git -C "$V/MoltenVK" apply --check "$ROOT/patches/moltenvk-null-descriptor-sets.patch" 2>/dev/null &&
        git -C "$V/MoltenVK" apply "$ROOT/patches/moltenvk-null-descriptor-sets.patch"
    (cd "$V/MoltenVK" && ./fetchDependencies --macos > "$LOGS/moltenvk-deps.log" 2>&1 && make macos > "$LOGS/moltenvk-make.log" 2>&1)
    cp "$lib" "$lib.wine11"
    cp "$V/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$lib"
    sign "$lib"
}

step_winesrc() {
    log "Wine 11.17 source (pristine copy in vendor/wine-src, patched build tree in vendor/wine-build)"
    [ -f "$V/wine-src/VERSION" ] || {
        fetch "$WINE_SRC_URL" "$DL/wine-11.17.tar.xz"
        mkdir -p "$V/wine-src" && tar -xJf "$DL/wine-11.17.tar.xz" -C "$V/wine-src" --strip-components=1
    }
    [ -f "$V/wine-build/config.status" ] && return
    rm -rf "$V/wine-build" && cp -R "$V/wine-src" "$V/wine-build"
    (cd "$V/wine-build" &&
        patch -p1 < "$ROOT/patches/wine-macos-single-gsbase.patch" &&
        patch -p1 < "$ROOT/patches/wine-macos-gptk-d3dmetal.patch" &&
        patch -p1 < "$ROOT/patches/wine-fast-udp-sockets.patch" &&
        PATH="/opt/homebrew/opt/bison/bin:$PATH" CC="clang -arch x86_64" \
        LDFLAGS="-L/opt/homebrew/opt/openssl@1.1/lib" CPPFLAGS="-I/opt/homebrew/opt/openssl@1.1/include" \
        x86 ./configure --enable-archs=x86_64,i386 --without-x --disable-tests --without-freetype \
            --without-gstreamer --without-sdl --without-gphoto --without-sane --without-usb --without-krb5 \
            --without-cups --without-dbus --without-gnutls --without-pcap --without-inotify --without-opencl \
            --without-oss --without-netapi > "$LOGS/wine-configure.log" 2>&1)
}

build_unix_lib() { # <make target dir> <so name>
    (cd "$V/wine-build" && PATH="/opt/homebrew/opt/bison/bin:$PATH" x86 make -j"$(sysctl -n hw.ncpu)" "dlls/$1/all" > "$LOGS/wine-make-$1.log" 2>&1)
    local dst="$WINE_ROOT/lib/wine/x86_64-unix/$2"
    mkdir -p "$ROOT/build/ntdll-orig/x86_64-unix"
    [ -f "$ROOT/build/ntdll-orig/x86_64-unix/$2" ] || cp "$dst" "$ROOT/build/ntdll-orig/x86_64-unix/$2"
    cp "$V/wine-build/dlls/$1/$2" "$dst" && sign "$dst"
}

step_ntdll() {
    log "ntdll.so with the single-gsbase (needed by D3DMetal) and fast UDP socket patches"
    step_winesrc
    # Older build trees predate the fast UDP socket patch; apply it once.
    grep -q sock_fast_path "$V/wine-build/dlls/ntdll/unix/socket.c" ||
        (cd "$V/wine-build" && patch -p1 < "$ROOT/patches/wine-fast-udp-sockets.patch")
    build_unix_lib ntdll ntdll.so
}

step_winemac() {
    log "winemac.so with the GPTK macdrv_functions table"
    step_winesrc
    build_unix_lib winemac.drv winemac.so
    nm -gU "$WINE_ROOT/lib/wine/x86_64-unix/winemac.so" | grep -q macdrv_functions
}

step_gptk() {
    log "Apple Game Porting Toolkit (D3DMetal) and the gptk.dll shim"
    if [ ! -d "$GPTK_LIB" ]; then
        echo "GPTK not installed. Run: brew install --cask gcenx/wine/game-porting-toolkit"
        echo "(needs Apple's 'Game Porting Toolkit' download from developer.apple.com in ~/Downloads)"
        echo "The vulkan and dxvk backends work without it; skipping."
        return
    fi
    bash "$ROOT/scripts/build-d3dmetal-shim.sh" > "$LOGS/build-d3dmetal-shim.log" 2>&1
}

step_gamemode() {
    log "vendor/CS2.app: Wine loader in a bundle with the games category (macOS Game Mode)"
    local app="$V/CS2.app" u="$WINE_ROOT/lib/wine/x86_64-unix"
    [ -x "$app/Contents/MacOS/wine" ] && return
    step_winesrc
    (cd "$V/wine-build" && PATH="/opt/homebrew/opt/bison/bin:$PATH" x86 make loader/wine > "$LOGS/wine-make-loader.log" 2>&1)
    mkdir -p "$app/Contents/MacOS"
    cp "$ROOT/patches/CS2.app-Info.plist" "$app/Contents/Info.plist"
    cp "$V/wine-build/loader/wine" "$app/Contents/MacOS/wine"
    # the loader looks for ntdll.so next to itself
    ln -sf "$u/ntdll.so" "$app/Contents/MacOS/ntdll.so"
    sign "$app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
    # programs Wine starts through bin/wine (winedbg, services) get the same identity
    [ -L "$WINE_ROOT/bin/wine" ] || mv "$WINE_ROOT/bin/wine" "$WINE_ROOT/bin/wine.gcenx"
    ln -sfn "$app/Contents/MacOS/wine" "$WINE_ROOT/bin/wine"
}

step_webhelper() {
    log "Steam: steamwebhelper wrapper (CEF with GPU off in one process, fixes black Steam windows)"
    local cef="$STEAM_DIR/bin/cef/cef.win64" w="$ROOT/tools/webhelper"
    [ -f "$cef/steamwebhelper_real.exe" ] || mv "$cef/steamwebhelper.exe" "$cef/steamwebhelper_real.exe"
    [ "$w/steamwebhelper.exe" -nt "$w/steamwebhelper.c" ] ||
        x86_64-w64-mingw32-gcc -O2 -municode -o "$w/steamwebhelper.exe" "$w/steamwebhelper.c"
    cmp -s "$w/steamwebhelper.exe" "$cef/steamwebhelper.exe" || cp "$w/steamwebhelper.exe" "$cef/steamwebhelper.exe"
}

step_steamcfg() {
    log "Steam: disable the in-game overlay for CS2 (its orphaned helper crashes under Wine)"
    for f in "$STEAM_DIR"/userdata/*/config/localconfig.vdf; do
        [ -f "$f" ] && python3 "$ROOT/scripts/steam-no-overlay.py" "$f"
    done
}

step_tools() {
    log "screenshot/OCR helpers used by the benchmark (Swift, Vision framework)"
    for t in winshot winlist fpsread wininput; do
        [ "$ROOT/scripts/$t" -nt "$ROOT/scripts/$t.swift" ] || swiftc -O -o "$ROOT/scripts/$t" "$ROOT/scripts/$t.swift"
    done
}

step_prefix() {
    log "Wine prefix at $WINEPREFIX"
    [ -f "$WINEPREFIX/system.reg" ] || WINEDEBUG=-all "$WINE" wineboot -u > "$LOGS/wineboot.log" 2>&1
    # Retina off: with it on, CS2's mouse coordinates don't match its window and menus can't be clicked.
    "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d n /f >/dev/null
    "$WINE" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null
    "$WINE" reg add 'HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null
    # Crashing helpers (the Steam overlay after CS2 exits) must not open Wine Debugger windows.
    "$WINE" reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null
    "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v AllowSetGamma /t REG_DWORD /d 0 /f >/dev/null
    "$WINE" reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >/dev/null
    "$WINESERVER" -w
}

step_steam() {
    log "Steam"
    [ -f "$STEAM_DIR/steam.exe" ] && return
    fetch "$STEAM_URL" "$DL/SteamSetup.exe"
    WINEDEBUG=-all "$WINE" "$DL/SteamSetup.exe" /S > "$LOGS/steam-install.log" 2>&1 || true
    "$WINESERVER" -w
    [ -f "$STEAM_DIR/steam.exe" ] || { echo "Steam installer did not produce steam.exe, see $LOGS/steam-install.log"; exit 1; }
}

steps=("$@"); [ ${#steps[@]} -gt 0 ] || steps=(deps wine dxvk moltenvk ntdll winemac gptk gamemode tools prefix steam webhelper steamcfg)
for s in "${steps[@]}"; do "step_$s"; done
log "done. Next: ./cs2mac steam (log in, install Counter-Strike 2), then ./cs2mac play"
