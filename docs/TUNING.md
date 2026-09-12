# Tuning

What was tried, what mattered, and what did not. Numbers are in `docs/RESULTS.md`.

## Things that matter

| knob | where | effect |
|------|-------|--------|
| backend `d3dmetal` | `./cs2mac play d3dmetal` | best median, best p5 and shortest load stalls, see RESULTS |
| `RetinaMode = y` | prefix registry, set by setup | full pixel resolution on Retina displays; set `n` to trade sharpness for fps |
| MoltenVK 1.4.3 + null descriptor patch | `vendor/MoltenVK`, installed into Wine | vulkan/dxvk run at all (present_wait2, no crash on map load) |
| `WINEESYNC=1 WINEMSYNC=1` | `scripts/env.sh` | fewer wineserver round trips for synchronisation; msync is the macOS native one and is used when available |
| `-windowed -w 1280 -h 720` | `run-cs2.sh` | fullscreen on Wine's Mac driver changes the display mode and is slower to alt-tab; the window can be resized in the game's settings |
| `fps_max 0` | benchmark only | uncapped so the numbers are comparable; for play, cap at the display's refresh rate to keep frame pacing even |
| `-nojoy -novid` | `run-cs2.sh` | skip the joystick scan (slow under Wine) and the intro |

## D3DMetal environment knobs

`libd3dshared` reads these from the environment (found by string search in the binary, not
documented by Apple). Set them before `./cs2mac play d3dmetal`:

| variable | what it does |
|----------|--------------|
| `D3DM_SHOW_HUD_STATS=1` | Metal performance HUD in the corner of the window |
| `D3DM_ENABLE_METALFX=1` | let D3DMetal use MetalFX upscaling where it can |
| `D3DM_ENABLE_ASYNC_COMMIT=1` | commit command buffers from a worker thread |
| `D3DM_MULTITHREADED_INTERFACE_ENABLE=1` | run the D3D11 immediate context on its own thread |
| `D3DM_WAIT_ON_RESET=1` | synchronous device reset (debugging only) |
| `D3DM_NO_WINDOW=1` | headless (no CAMetalLayer), useful for tracing |

In the runs so far none of these moved the median by more than noise at 1280x720; the game is
CPU/translation bound there, not GPU bound.

## Things that did not help

- **`r_wait_on_present 0`** on the vulkan backend: hides the present-wait error but the game still
  exits; the real fix was the MoltenVK upgrade.
- **DXVK async shader compilation**: the "async" build is already used; the stalls are pipeline
  creation inside MoltenVK, not DXVK's state cache.
- **Retina on with d3dmetal**: sharp since the finished shim (was quarter resolution in early builds).
- **wined3d** (stock Wine, OpenGL): loads the menu, single-digit fps in a map. Kept as the
  fallback backend because it needs nothing extra.

## Where the time goes

At 1280x720 on an M2 Max all backends are far from the GPU limit. The remaining cost is
Rosetta (CS2 is x86_64 and so is Wine's PE side) and the D3D11 to Metal translation. The
d3dmetal backend wins because it translates D3D11 to Metal in one step; dxvk and vulkan go through
Vulkan first and MoltenVK then re-translates. Running Wine's Unix side native arm64 (Wine's
`--enable-archs` with an arm64 host build) would remove Rosetta from the Unix half but not from
the game itself; it is the next thing worth trying.

## Frame drops while shooting (2026-09-12)

Measured with `scripts/shoot-test.sh` (Aim Botz, AK-47 bursts, M2 Max, 1280x720, one run per row).

| run | idle f60 median | shooting f60 median / min | worst frame ms while shooting |
|---|---|---|---|
| d3dmetal | 120 | 118 / 86 | 94 |
| dxvk | 118 | 117 / 112 | 1552 |
| d3dmetal -nosound | 114 | 115 / 105 | 344 |
| d3dmetal D3DM_ENABLE_ASYNC_COMMIT=1 | 120 | 119 / 93 | 99 |
| d3dmetal D3DM_MULTITHREADED_INTERFACE_ENABLE=1 | 113 | 109 / 84 | 71 |
| de_dust2 with bots, d3dmetal | 111 | 113 / 88 | 57 |
| de_dust2 without bots, d3dmetal | 114 | 116 / 61 | 175 |

Findings:

- The big drops (30 to 45 fps for several seconds) only showed on the very first shooting session
  on a fresh shader cache. Later sessions on the same map stayed within about 10% of idle. That
  matches D3DMetal compiling pipelines the first time muzzle flash, tracer and impact effects
  appear; the result is cached on disk, so it gets better after one session.
- None of sound, bots, async commit or the multithreaded interface changed the steady-state
  numbers beyond run-to-run noise. Async commit had the best single run but did not hold up on
  repeats, so it stays off by default.
- DXVK keeps a similar median but has second-long hitches (worst frame 0.8 to 1.5 s), so d3dmetal
  stays the default.
- Background load matters more than any knob: a busy Chrome GPU helper and a dev server pulled
  repeat runs down to 80 to 100 fps with 250+ ms spikes, idle included. Close them before playing
  or benchmarking.

To warm the shader cache before a real match, load Aim Botz once and fire every weapon you plan to
use: `./cs2mac play d3dmetal 1280x720 +map_workshop 3070244462 aim_botz`.

## Retina (2026-09-12)

d3dmetal, `RetinaMode=y`, 2x external display, Dust2 benchmark map, 90 s each. The window is
clamped to the screen in points, so the pixel size is what the GPU renders.

| Rendered pixels | median fps | 5th percentile fps | worst frame ms |
|---|---|---|---|
| 2304x1296 | 86.4 | 59.7 | 234.6 |
| 2304x1296 with FSR | 83.0 | 58.7 | 74.7 |
| 1920x1080 | 109.8 | 80.0 | 54.9 |
| 1280x720 | 116.8 | 113.3 | 1031.6 |

The GPU is the limit above 1080p; at 720p the CPU (Rosetta) is. For competitive play pick 1920x1080.
