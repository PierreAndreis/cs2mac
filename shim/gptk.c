/*
 * gptk.dll: compatibility shim that lets Apple's D3DMetal PE modules
 * (built against Wine 7.7 from the Game Porting Toolkit) load on Wine 11.
 *
 * Wine 7.x exported __wine_unix_call from ntdll. Wine 8+ replaced it with a
 * data export, __wine_unix_call_dispatcher, holding a function pointer with
 * the same signature. D3DMetal's d3d11.dll/dxgi.dll import table is patched
 * to import from this DLL instead of ntdll, and this DLL forwards the call.
 * NtQueryVirtualMemory is re-exported to ntdll via a forwarder in gptk.def.
 */
#include <windows.h>

typedef UINT64 unixlib_handle_t;
typedef NTSTATUS (WINAPI *unix_call_t)(unixlib_handle_t handle, unsigned int code, void *args);

static unix_call_t *dispatcher;

static unix_call_t resolve(void)
{
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    if (!dispatcher && ntdll)
        dispatcher = (unix_call_t *)GetProcAddress(ntdll, "__wine_unix_call_dispatcher");
    return dispatcher ? *dispatcher : NULL;
}

NTSTATUS WINAPI __wine_unix_call(unixlib_handle_t handle, unsigned int code, void *args)
{
    unix_call_t fn = resolve();
    if (!fn) return (NTSTATUS)0xC0000002; /* STATUS_NOT_IMPLEMENTED */
    return fn(handle, code, args);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(inst);
        resolve();
    }
    return TRUE;
}
