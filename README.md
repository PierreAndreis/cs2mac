# cs2mac

Run Counter-Strike 2 (the Windows build) on Apple Silicon Macs through a small, custom
translation shim: Wine 11 for the Win32 layer, Metal for the GPU, and a launcher that picks and
tunes the graphics backend and benchmarks it.

Educational project. Valve does not ship CS2 for macOS; this is a study of how far modern
translation layers (MoltenVK, DXVK, Apple's D3DMetal) get on an M-series GPU, what breaks, and
what tuning matters. Nothing proprietary is redistributed: the scripts download Wine, MoltenVK,
DXVK and Steam from upstream, and D3DMetal comes from Apple's Game Porting Toolkit which you
install yourself.

## What works

Three backends, all playable, all benchmarked on the same map (details in `docs/RESULTS.md`):

| backend  | path                                              | 1280x720 median fps | 5th percentile |
|----------|---------------------------------------------------|--------------------:|---------------:|
| d3dmetal | D3D11 -> Apple D3DMetal -> Metal (custom shim)    | 113 | 82 |
| dxvk     | D3D11 -> DXVK 1.10 -> Vulkan -> MoltenVK -> Metal | 108 | 79 |
| vulkan   | CS2 `-vulkan` -> MoltenVK -> Metal                | 76 to 91 | 27 to 46 |

Apple M2 Max, macOS 26, everything under Rosetta 2. `d3dmetal` is the default: highest median and,
what you actually feel, the best worst-case frame times.

The custom part is getting Apple's D3DMetal (built for Apple's Wine 7/9 fork) to run inside stock
Wine 11: an import trampoline DLL, a two-file patch to Wine's ntdll (single thread-state base), and a
new `macdrv_functions` export in Wine's Mac display driver plus a one-line fix for the black window
D3DMetal otherwise gets. `docs/ARCHITECTURE.md` walks through it.

## Requirements

- Apple Silicon Mac (tested: M2 Max, 38-core GPU), macOS 26 (Tahoe) or newer
- ~45 GB free disk (CS2 is ~35 GB, the Wine prefix and toolchain ~5 GB)
- Xcode command line tools (`xcode-select --install`), Rosetta 2 (`softwareupdate --install-rosetta --agree-to-license`)
- Homebrew
- A Steam account that owns CS2 (it is free to play)
- For the `d3dmetal` backend: `brew install --cask gcenx/wine/game-porting-toolkit` (needs Apple's
  Game Porting Toolkit download from developer.apple.com, free Apple ID)

## Quick start

```sh
git clone https://github.com/PierreAndreis/cs2mac && cd cs2mac
./cs2mac setup        # downloads Wine, MoltenVK, DXVK, Steam; builds the patched bits; creates the prefix
./cs2mac steam        # opens Steam; log in, install Counter-Strike 2
./cs2mac play         # launches CS2 on the d3dmetal backend, 1280x720 windowed
./cs2mac bench all    # benchmarks the three backends back to back
```

`./cs2mac play dxvk 1920x1080` picks another backend and resolution. `docs/USAGE.md` has every
subcommand, `docs/TUNING.md` the knobs and what they did.

## Layout

```
cs2mac              launcher (setup | steam | play | bench | backend | status | stop)
scripts/            setup.sh, backend.sh (switch D3D11 implementation), run-cs2.sh, bench.sh,
                    env.sh (paths and tunables), Swift helpers for window capture and FPS OCR
shim/               gptk.c + gptk.def (the trampoline DLL), patch_imports.py, d3d11probe.c
patches/            wine-macos-single-gsbase.patch, wine-macos-gptk-d3dmetal.patch,
                    moltenvk-null-descriptor-sets.patch
docs/               ARCHITECTURE.md, USAGE.md, TUNING.md, RESULTS.md
vendor/ downloads/ build/   created by setup, gitignored
```

## Legal

Wine is LGPL, MoltenVK and DXVK are Apache 2 / zlib; their sources are fetched, not vendored. The
Game Porting Toolkit is covered by Apple's license and is never copied into this repository.
Counter-Strike 2 and Steam are Valve's. Use your own account and follow Valve's terms.
