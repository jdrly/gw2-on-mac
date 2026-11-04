/* version.dll proxy: GW2 imports six functions of VERSION.dll statically, so a version.dll in
 * the game folder (with version=native,builtin for Gw2-64.exe) loads with the game, before
 * its font table, and away from Direct3D. Every export calls the system's version.dll,
 * loaded on first use (not in DllMain). The interface scale work is in ui_scale.c. */
#include <windows.h>
#include "ui_scale.h"

static HMODULE self, real;

static FARPROC real_proc(const char *name)
{
  HMODULE m = real;
  if (!m) {
    WCHAR path[MAX_PATH];
    UINT n = GetSystemDirectoryW(path, MAX_PATH);
    if (!n || n + 13 > MAX_PATH) return NULL;
    lstrcpyW(path + n, L"\\version.dll");
    m = LoadLibraryW(path);
    if (m == self) {  /* the loader handed us back: never call ourselves */
      FreeLibrary(m);
      m = NULL;
    }
    if (!m) { ui_log("version.dll proxy: cannot load the system version.dll (%lu)", GetLastError()); return NULL; }
    if (InterlockedCompareExchangePointer((void **)&real, m, NULL) != NULL) FreeLibrary(m);
    else {
      char p[MAX_PATH];
      GetModuleFileNameA(m, p, MAX_PATH);
      ui_log("version.dll proxy: forwarding to %s", p);
    }
    m = real;
  }
  return GetProcAddress(m, name);
}

#define FORWARD(ret, fail, name, params, args)                          \
  ret WINAPI proxy_##name params                                        \
  {                                                                     \
    static ret (WINAPI *fn) params;                                     \
    if (!fn) fn = (ret (WINAPI *) params)(void *)real_proc(#name);      \
    if (!fn) { SetLastError(ERROR_PROC_NOT_FOUND); return fail; }       \
    return fn args;                                                     \
  }

FORWARD(BOOL, FALSE, GetFileVersionInfoA, (LPCSTR f, DWORD h, DWORD l, LPVOID d), (f, h, l, d))
FORWARD(BOOL, FALSE, GetFileVersionInfoExA, (DWORD fl, LPCSTR f, DWORD h, DWORD l, LPVOID d), (fl, f, h, l, d))
FORWARD(BOOL, FALSE, GetFileVersionInfoExW, (DWORD fl, LPCWSTR f, DWORD h, DWORD l, LPVOID d), (fl, f, h, l, d))
FORWARD(DWORD, 0, GetFileVersionInfoSizeA, (LPCSTR f, LPDWORD h), (f, h))
FORWARD(DWORD, 0, GetFileVersionInfoSizeExA, (DWORD fl, LPCSTR f, LPDWORD h), (fl, f, h))
FORWARD(DWORD, 0, GetFileVersionInfoSizeExW, (DWORD fl, LPCWSTR f, LPDWORD h), (fl, f, h))
FORWARD(DWORD, 0, GetFileVersionInfoSizeW, (LPCWSTR f, LPDWORD h), (f, h))
FORWARD(BOOL, FALSE, GetFileVersionInfoW, (LPCWSTR f, DWORD h, DWORD l, LPVOID d), (f, h, l, d))
FORWARD(DWORD, 0, VerFindFileA, (DWORD fl, LPCSTR f, LPCSTR w, LPCSTR a, LPSTR c, PUINT cl, LPSTR d, PUINT dl),
        (fl, f, w, a, c, cl, d, dl))
FORWARD(DWORD, 0, VerFindFileW, (DWORD fl, LPCWSTR f, LPCWSTR w, LPCWSTR a, LPWSTR c, PUINT cl, LPWSTR d, PUINT dl),
        (fl, f, w, a, c, cl, d, dl))
FORWARD(DWORD, 0, VerInstallFileA, (DWORD fl, LPCSTR s, LPCSTR d, LPCSTR sd, LPCSTR dd, LPCSTR cd, LPSTR t, PUINT tl),
        (fl, s, d, sd, dd, cd, t, tl))
FORWARD(DWORD, 0, VerInstallFileW, (DWORD fl, LPCWSTR s, LPCWSTR d, LPCWSTR sd, LPCWSTR dd, LPCWSTR cd, LPWSTR t, PUINT tl),
        (fl, s, d, sd, dd, cd, t, tl))
FORWARD(BOOL, FALSE, VerQueryValueA, (LPCVOID b, LPCSTR s, LPVOID *p, PUINT l), (b, s, p, l))
FORWARD(BOOL, FALSE, VerQueryValueW, (LPCVOID b, LPCWSTR s, LPVOID *p, PUINT l), (b, s, p, l))

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) {
    self = inst;
    DisableThreadLibraryCalls(inst);
    ui_scale_start(inst);
  }
  return TRUE;
}
