# Usage

Everything goes through the `./cs2mac` launcher. Every subcommand is a thin wrapper over a
script in `scripts/`, so you can also call those directly.

## 1. Setup

```sh
./cs2mac setup
```

Runs `scripts/setup.sh`, which is idempotent (re-run it after a failure, it skips what is done):

| step       | what it does                                                                                     |
|------------|--------------------------------------------------------------------------------------------------|
| deps       | checks Apple Silicon, Xcode CLT, Rosetta 2, Homebrew; installs `bison mingw-w64 cmake`           |
| wine       | downloads Gcenx's Wine 11.17 build into `vendor/wine-11.17`                                      |
| dxvk       | downloads DXVK-macOS 1.10.3 (async) into `vendor/dxvk-macos`                                     |
| moltenvk   | clones MoltenVK, applies `patches/moltenvk-null-descriptor-sets.patch`, builds it universal, swaps it into Wine |
| ntdll      | downloads the Wine 11.17 source, applies `patches/wine-macos-single-gsbase.patch`, builds and installs `ntdll.so` |
| winemac    | applies `patches/wine-macos-gptk-d3dmetal.patch`, builds and installs `winemac.so`               |
| gptk       | builds the `gptk.dll` shim and stages Apple's D3DMetal (skipped if the Game Porting Toolkit is not installed) |
| tools      | compiles the Swift helpers used by the benchmark (`winshot`, `winlist`, `fpsread`)               |
| prefix     | creates the Wine prefix in `~/Library/Application Support/cs2mac/prefix` and sets the registry knobs |
| steam      | downloads and silently installs the Windows Steam client into the prefix                         |

Run a single step with `./cs2mac setup <step>`. The Wine build steps take 10 to 20 minutes on an
M2 Max; MoltenVK about 5.

For the `d3dmetal` backend you need Apple's Game Porting Toolkit. It is not redistributable, so
install it yourself before running setup (or run `./cs2mac setup gptk` afterwards):

```sh
brew install --cask gcenx/wine/game-porting-toolkit
```

The cask asks for the "Game Porting Toolkit" download from developer.apple.com in `~/Downloads`.
Only the `D3DMetal.framework` and `libd3dshared.dylib` plus the `d3d11.dll`/`dxgi.dll` PE files
from it are used; the toolkit's own Wine is never run.

## 2. Steam

```sh
./cs2mac steam
```

Starts Steam inside the prefix. Log in, then install Counter-Strike 2 from the library (about
35 GB). Steam's UI is Chromium and runs in software rendering under Wine; if the window stays
black after login, quit it and start it with the credentials on the command line, which skips the
login window entirely:

```sh
./cs2mac steam -login <user> <password>
```

Keep Steam running while you play; CS2 refuses to start without it.

## 3. Play

```sh
./cs2mac play                      # d3dmetal, 1280x720, windowed
./cs2mac play dxvk 1920x1080
./cs2mac play vulkan 1280x720 +map de_dust2
CS2MAC_FULLSCREEN=1 ./cs2mac play
```

The first argument is the backend (`d3dmetal`, `dxvk`, `vulkan`, `wined3d`), the second the
resolution, anything after that goes to `cs2.exe`. Switching backends rewrites a few files in the
Wine install and the prefix (see `scripts/backend.sh status`); it is safe to do while Steam runs,
but not while CS2 runs.

## 4. Benchmark

```sh
./cs2mac bench                     # d3dmetal, 120 s, 1280x720
./cs2mac bench all 120 1280x720    # d3dmetal, dxvk and vulkan back to back
```

The benchmark loads the "CS2 FPS BENCHMARK" workshop map (id 3240880604, see the next section),
stands at spawn with `cl_showfps 2` on, and reads the overlay with the Vision OCR every 5 seconds.
Each run leaves `build/bench/<backend>-<res>-<time>.csv` (samples), `.txt` (summary) and a few PNG
frames. `docs/RESULTS.md` explains how to read them.

### Workshop maps

Subscribing from the Steam client inside Wine is clumsy, so `scripts/workshop.sh` fetches items
with SteamCMD and registers them in the prefix's Steam workshop manifest. The registration is what
makes CS2 mount the map vpk nested inside the addon: a bare copy of the files under
`csgo/maps/workshop/<id>/` gets you `Failed to mount world vpk file`, and an extracted map vpk
fails the signature check unless the game runs with `-insecure` (which tints the screen purple).

```sh
./cs2mac stop                                  # Steam rewrites the manifest on exit, so stop it first
bash scripts/workshop.sh 3240880604 3070244462 # FPS benchmark flythrough + Aim Botz
./cs2mac steam -login <user>
./cs2mac play d3dmetal 1280x720 +map_workshop 3070244462 aim_botz
```

SteamCMD logs in anonymously; if an item refuses that, set `STEAMCMD_LOGIN="user password"` for the
call (the value only reaches the SteamCMD process).

### Frame times while shooting

```sh
bash scripts/shoot-test.sh d3dmetal 1280x720            # needs Aim Botz installed as above
SHOOT_TAG=nosound bash scripts/shoot-test.sh d3dmetal 1280x720 -nosound
```

Joins CT with god mode, gives an AK-47 with infinite ammo and fires eight 4 s bursts while sampling
`cl_showfps 2`, printing per-phase medians and the worst frame time. The summary names the adapter
CS2 reported so a run on the wrong backend is obvious.

## 5. Other

```sh
./cs2mac status        # what is installed, what backend the prefix is on
./cs2mac backend dxvk  # switch without launching
./cs2mac stop          # kill CS2, Steam and the wineserver
```

Logs land in `build/logs/`. To debug the D3DMetal path, run with `WINEDEBUG=+gptk` (the shim's
own channel) or `CS2MAC_GPTK_DEBUG=1` (dumps the Cocoa view and layer tree of the game window).
