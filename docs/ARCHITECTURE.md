# How the shim works

CS2 is a 64-bit Windows binary that talks to Direct3D 11 (or, with `-vulkan`, to Vulkan). Nothing
in it knows about Metal. Three layers are stacked to get it onto an Apple GPU:

```
cs2.exe (x86_64 PE)  -->  Wine 11.17 (Win32 -> Darwin, runs under Rosetta 2)
      |
      +-- -vulkan:  winevulkan.dll -> MoltenVK (Vulkan -> Metal)                 [backend: vulkan]
      +-- d3d11:    DXVK 1.10 d3d11.dll -> winevulkan -> MoltenVK                [backend: dxvk]
      +-- d3d11:    Apple D3DMetal d3d11.dll + dxgi.dll -> gptk.dll -> winemac   [backend: d3dmetal]
```

The first two are off-the-shelf pieces glued together; the third is the custom part. D3DMetal is
Apple's own D3D11 to Metal translator from the Game Porting Toolkit (GPTK). Apple only ships it
inside a fork of Wine 7 (later 9), whose internal ABI is nothing like Wine 11's. The shim makes the
GPTK binaries load and run on stock Wine 11.

## Three attempts

1. **Vulkan (MoltenVK).** CS2's native Vulkan renderer. Worked after two fixes: MoltenVK 1.4.3
   (VK_KHR_present_wait2, which CS2 polls; older versions make the game quit after 20 seconds
   waiting for a present event that never comes), and a one-line MoltenVK patch to tolerate
   descriptor sets that are bound but null (`patches/moltenvk-null-descriptor-sets.patch`, a
   null `this` inside `bindDescriptorSet` crashed the game a minute into a map).
2. **DXVK.** D3D11 through DXVK-macOS 1.10.3 and then MoltenVK. Highest peaks, but stalls of
   several hundred milliseconds when the pipeline cache is cold; 5th-percentile frame rate is the
   worst of the three on the first runs; close to D3DMetal once its caches are warm.
3. **D3DMetal.** D3D11 directly to Metal via Apple's translator, wired into Wine 11 by this shim.
   Best median and, more importantly, best 5th percentile: the game feels smooth.

## The D3DMetal shim, piece by piece

D3DMetal on the PE side is `dxgi.dll` and `d3d11.dll`; the Unix side is `libd3dshared.dylib` plus
`D3DMetal.framework`. The PE DLLs are Wine "unixlib" modules: they call into the Unix side through
`__wine_unix_call`, which Wine 7 exported from `ntdll.dll` with a different calling contract than
Wine 11 uses. Four things had to change.

### 1. `shim/gptk.c` and `shim/patch_imports.py`: the import trampoline

`patch_imports.py` rewrites the import table of Apple's `dxgi.dll` and `d3d11.dll` so that every
import of `ntdll.dll` points to `gptk.dll` instead. `gptk.dll` (built with mingw, 3 KB) forwards
everything back to the real `ntdll.dll` except `__wine_unix_call`, which it implements itself:
it resolves Wine 11's internal `__wine_unix_call_dispatcher` and calls it with the handle and
code the GPTK DLL passed. This is enough for the PE side to reach `libd3dshared`.

### 2. `patches/wine-macos-single-gsbase.patch`: one thread-state base

x86_64 Wine keeps the Windows TEB in the `gs` segment base. Wine 11 flips `gs` between the
Windows TEB and the macOS pthread TSD on every transition into and out of Unix code
(`__thread_set_tsd_base` in `signal_x86_64.c`). D3DMetal was built for a Wine that did not flip:
its Unix code, running on threads it spawned itself, reads thread locals through the TEB and
faults. The patch keeps a single base for the process lifetime (the TSD pointer lives at
TEB+0x320, where Wine already mirrors it) and removes the flips in the syscall dispatcher, the
Unix-call dispatcher and the signal handlers. The vulkan and dxvk backends run unpatched code
paths through it without change.

### 3. `patches/wine-macos-gptk-d3dmetal.patch`: the `macdrv_functions` table

`libd3dshared` does not create its own window. On load it does
`dlsym(RTLD_DEFAULT, "macdrv_functions")` and expects an array of 24 function pointers exported
by Wine's Mac display driver (`winemac.so`): init, get the per-window data (a struct whose field
at +0x18 is the Cocoa client view), release it, get the NSWindow, create and release a Metal
device, create a Metal view inside the client view, get its CAMetalLayer, release the view, and
run a block on the main thread. Wine 11 never had this table. `dlls/winemac.drv/gptk.c` provides
it on top of Wine 11's own Metal-view code (`macdrv_view_create_metal_view`, the same path
winevulkan uses), creating a client surface for the window if none exists yet and marking that
view as owned by the shim.

The "marking" is the fix for the black window. Wine 11's GDI surface flush
(`macdrv_surface_flush` in `surface.c`) hides the client view every time the window's software
surface is flushed, on the assumption that Vulkan will show it again on the next present. D3DMetal
presents through its own CAMetalLayer and never calls back into the driver, so the view stayed
hidden while the layer had a perfectly good frame in it. The flush now skips views the shim owns.

### 4. `scripts/backend.sh d3dmetal`: wiring

The patched PE DLLs go into Wine's `x86_64-windows` and the prefix's `system32`; the Unix side is
symlinked in place of `dxgi.so` and `d3d11.so` in `x86_64-unix`, together with
`D3DMetal.framework`. Registry overrides force `d3d11`/`dxgi` to "builtin" so Wine picks these up.
`RetinaMode` must be off: `libd3dshared` sizes its drawable from the view frame in points, so on a
2x display it would render at quarter resolution and get stretched.

## Why not just use the GPTK's own Wine?

It is a Wine 9 fork with no wow64, an old MoltenVK, and no source for the parts that matter.
Running the modern Wine and borrowing only the translator gives current Win32 fixes, esync/msync,
a MoltenVK that can be patched, and one codebase for all three backends so they can be compared.
