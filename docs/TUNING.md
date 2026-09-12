# Tuning

What was tried, what mattered, and what did not. Numbers are in `docs/RESULTS.md`.

## Things that matter

| knob | where | effect |
|------|-------|--------|
| backend `d3dmetal` | `./cs2mac play d3dmetal` | best median, best p5 and shortest load stalls, see RESULTS |
| `RetinaMode = n` | prefix registry, set by setup | required for d3dmetal (drawable size in points); also halves work for the others on a 2x display |
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
- **Retina on with d3dmetal**: quarter-resolution drawable, blurry and not faster.
- **wined3d** (stock Wine, OpenGL): loads the menu, single-digit fps in a map. Kept as the
  fallback backend because it needs nothing extra.

## Where the time goes

At 1280x720 on an M2 Max all backends are far from the GPU limit. The remaining cost is
Rosetta (CS2 is x86_64 and so is Wine's PE side) and the D3D11 to Metal translation. The
d3dmetal backend wins because it translates D3D11 to Metal in one step; dxvk and vulkan go through
Vulkan first and MoltenVK then re-translates. Running Wine's Unix side native arm64 (Wine's
`--enable-archs` with an arm64 host build) would remove Rosetta from the Unix half but not from
the game itself; it is the next thing worth trying.
