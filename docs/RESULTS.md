# Results

All runs: Apple M2 Max (12 CPU / 38 GPU cores, 96 GB), macOS 26.0, Wine 11.17 under Rosetta 2,
CS2 build of 2026-09-12, 1280x720 windowed, `fps_max 0`, video settings as CS2 auto-detected
(gpu_level 3). Map: "CS2 FPS BENCHMARK" workshop map (de_dust2 with bots), standing at spawn for
120 seconds after a 20 second warm-up, the `cl_showfps 2` overlay OCR'd every 5 seconds.

"fps" is the overlay's 60-frame window. p5 is the 5th percentile of those samples, so a low p5
means visible stutter during the run. "worst frame" is the overlay's own worst frame time since
map load, which includes shader compilation stalls.

## Final comparison (same binaries, same session)

| backend  | median fps | mean | p5 | worst frame | map load |
|----------|-----------:|-----:|---:|------------:|---------:|
| d3dmetal | 112.6 | 108.6 | 82.0 | 559 ms | 29 s |
| dxvk     | 108.0 | 105.5 | 78.9 | 20.0 s (first map stall) | 30 s |
| vulkan   | 75.8 | 71.3 | 26.8 | 13.5 s (first map stall) | 22 s |

dxvk's and vulkan's "worst frame" numbers are one-off stalls right after map load while MoltenVK
compiles pipelines (the overlay keeps the maximum since load). d3dmetal's worst frame during the
same window was 0.56 s. The p5 column is the better steady-state stutter measure.

The vulkan run in this session had a long stall about 15 seconds after the warm-up (a pipeline
compile in MoltenVK; the overlay briefly read 27 fps) and never fully recovered; the earlier run
below, on the same binaries, did not. Treat vulkan as "75 to 90 median, 27 to 45 p5".

## Earlier runs (before the single-gsbase ntdll patch, Retina mode on)

| backend  | median fps | mean | p5 | worst frame | map load |
|----------|-----------:|-----:|---:|------------:|---------:|
| vulkan   | 91.3 | 91.6 | 45.5 | 282 ms | 21 s |
| dxvk     | 106.1 | 94.2 | 6.8 | (not captured) | 25 s |

The ntdll patch changes nothing on the vulkan and dxvk paths by design; Retina off halves the
drawable and helps all three a little. These are kept to show the spread between runs.

## Attempt history

| # | attempt | outcome |
|---|---------|---------|
| A1 | `-vulkan`, stock Wine 11.17 (MoltenVK 1.4.0) | renders, quits after ~20 s: `QueuePresentAndWait` never sees a present event (no `VK_KHR_present_wait2`) |
| A2 | `-vulkan`, MoltenVK 1.4.3 from source | runs 90 s, then access violation in `bindDescriptorSet` (null descriptor set) |
| A3 | `-vulkan`, MoltenVK 1.4.3 + null-descriptor patch | stable, benchmarked (vulkan rows above) |
| B  | DXVK-macOS 1.10.3 async over the A3 MoltenVK | stable; close to d3dmetal once warm, longer load stalls |
| C1 | D3DMetal PE DLLs loaded into Wine 11 via `gptk.dll` trampoline | `__wine_unix_call` reaches `libd3dshared`, then `Assertion failed: (drv)` (no `macdrv_functions`) |
| C2 | C1 + `macdrv_functions` in `winemac.so` | device created, game runs, window is black |
| C3 | C2 + single-gsbase ntdll patch | D3DMetal worker threads stop faulting; still black |
| C4 | C3 + exempt shim-owned client views from the GDI flush hide, Retina off | renders, benchmarked (d3dmetal row above) |

## Reading the raw data

Each run writes three files to `build/bench/`:

- `<backend>-<res>-<timestamp>.csv`: one row per 5 s sample (`t,now,f60,f240,f1000,min_ms,max_ms`);
  blanks are OCR misses.
- `.txt`: the summary printed at the end (what the tables above quote).
- `-<t>.png`: every fourth frame capture, to eyeball what the OCR saw.

Re-run with `./cs2mac bench all 120 1280x720`. Runs are not identical: bot behaviour and shader
cache state differ, expect roughly 5 fps of noise on the median and much more on p5.
