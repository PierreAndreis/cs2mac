/* Minimal D3D11 device probe: prints adapter name, feature level and driver. */
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

int main(void)
{
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    IDXGIDevice *dxdev = NULL;
    IDXGIAdapter *adapter = NULL;
    D3D_FEATURE_LEVEL fl = 0;
    DXGI_ADAPTER_DESC desc;
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                           D3D11_SDK_VERSION, &dev, &fl, &ctx);
    printf("D3D11CreateDevice: hr=0x%08lx feature_level=0x%x\n", (unsigned long)hr, fl);
    if (FAILED(hr)) return 1;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxdev)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxdev, &adapter)) &&
        SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc)))
    {
        printf("adapter: %ls vendor=0x%04x device=0x%04x vram=%lu MB\n", desc.Description,
               desc.VendorId, desc.DeviceId, (unsigned long)(desc.DedicatedVideoMemory >> 20));
    }
    {
        HMODULE m = GetModuleHandleA("d3d11.dll");
        char path[MAX_PATH] = "?";
        if (m) GetModuleFileNameA(m, path, sizeof(path));
        printf("d3d11.dll loaded from: %s\n", path);
        m = GetModuleHandleA("dxgi.dll");
        if (m) GetModuleFileNameA(m, path, sizeof(path));
        printf("dxgi.dll loaded from: %s\n", path);
    }
    return 0;
}
