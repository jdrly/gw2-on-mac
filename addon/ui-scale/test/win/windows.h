/* Just enough of windows.h to build ui_scale.c natively for test.c. The Win32 calls are
 * stubs; IsBadReadPtr/IsBadWritePtr and the ini come from the test. */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <wchar.h>
#include <stdio.h>
#include <strings.h>

#define WINAPI
#define MAX_PATH 260
typedef int BOOL;
typedef uint32_t DWORD;
typedef unsigned int UINT;
typedef int32_t LONG;
typedef wchar_t WCHAR;
typedef void *HANDLE, *HINSTANCE, *HMODULE, *LPVOID;
typedef const void *LPCVOID;
typedef size_t SIZE_T;
typedef DWORD (*LPTHREAD_START_ROUTINE)(LPVOID);
typedef struct { int unused; } CRITICAL_SECTION;
typedef struct { int wYear, wMonth, wDay, wHour, wMinute, wSecond, wMilliseconds; } SYSTEMTIME;
typedef uint32_t ULONG;
typedef struct { int64_t QuadPart; } LARGE_INTEGER;
typedef struct { LONG e_lfanew; } IMAGE_DOS_HEADER;
typedef struct { DWORD VirtualAddress, Size; } IMAGE_DATA_DIRECTORY;
#define IMAGE_DIRECTORY_ENTRY_IMPORT 1
typedef struct {
  struct { int NumberOfSections; DWORD TimeDateStamp; } FileHeader;
  struct { DWORD SizeOfImage; IMAGE_DATA_DIRECTORY DataDirectory[16]; } OptionalHeader;
} IMAGE_NT_HEADERS64;
typedef struct { DWORD OriginalFirstThunk, TimeDateStamp, ForwarderChain, Name, FirstThunk; } IMAGE_IMPORT_DESCRIPTOR;
typedef struct { union { uint64_t AddressOfData, Ordinal, Function; } u1; } IMAGE_THUNK_DATA64;
typedef struct { uint16_t Hint; char Name[1]; } IMAGE_IMPORT_BY_NAME;
#define IMAGE_ORDINAL_FLAG64 0x8000000000000000ull
#define IMAGE_SNAP_BY_ORDINAL64(o) (((o) & IMAGE_ORDINAL_FLAG64) != 0)
typedef struct { char Name[8]; DWORD VirtualAddress; struct { DWORD VirtualSize; } Misc; } IMAGE_SECTION_HEADER;
#define IMAGE_FIRST_SECTION(nt) ((const IMAGE_SECTION_HEADER *)((nt) + 1))
#define INVALID_HANDLE_VALUE ((HANDLE)(intptr_t)-1)
#define FILE_APPEND_DATA 4
#define FILE_SHARE_READ 1
#define OPEN_ALWAYS 4
#define FILE_ATTRIBUTE_NORMAL 0x80

#define SM_CXSCREEN 0
#define SM_CYSCREEN 1

int test_bad_ptr(const void *p, size_t n);
int test_screen(int axis);
const char *test_ini(const char *key);
/* the critical section spin: a clock and a pause the test drives, VirtualProtect's answer, and
 * the spin count InitializeCriticalSectionAndSpinCount got */
BOOL test_qpf(LARGE_INTEGER *f);
BOOL test_qpc(LARGE_INTEGER *c);
void test_yield(void);
BOOL test_protect(void *a, size_t n);
BOOL test_cs_init(void *cs, DWORD spin);

static inline void GetLocalTime(SYSTEMTIME *t) { memset(t, 0, sizeof *t); }
static inline void InitializeCriticalSection(CRITICAL_SECTION *c) { (void)c; }
static inline void EnterCriticalSection(CRITICAL_SECTION *c) { (void)c; }
static inline void LeaveCriticalSection(CRITICAL_SECTION *c) { (void)c; }
static inline HANDLE CreateFileA(const char *p, DWORD a, DWORD s, void *sa, DWORD c, DWORD f, HANDLE t)
{ (void)p; (void)a; (void)s; (void)sa; (void)c; (void)f; (void)t; return (HANDLE)stdout; }
static inline BOOL WriteFile(HANDLE h, const void *b, DWORD n, DWORD *w, void *o)
{ (void)o; *w = (DWORD)fwrite(b, 1, n, (FILE *)h); return 1; }
static inline BOOL IsBadReadPtr(const void *p, size_t n) { return test_bad_ptr(p, n); }
static inline BOOL IsBadWritePtr(void *p, size_t n) { return test_bad_ptr(p, n); }
static inline LONG InterlockedExchange(volatile LONG *p, LONG v) { LONG o = *p; *p = v; return o; }
static inline HMODULE GetModuleHandleW(const WCHAR *n) { (void)n; return NULL; }
static inline DWORD GetModuleFileNameW(HMODULE m, WCHAR *b, DWORD n) { (void)m; (void)n; b[0] = 0; return 0; }
static inline DWORD GetModuleFileNameA(HMODULE m, char *b, DWORD n) { (void)m; (void)n; b[0] = 0; return 0; }
static inline int lstrcmpiW(const WCHAR *a, const WCHAR *b) { return wcscasecmp(a, b); }
static inline int lstrcmpiA(const char *a, const char *b) { return strcasecmp(a, b); }
static inline int GetSystemMetrics(int i) { return test_screen(i); }
static inline void Sleep(DWORD ms) { (void)ms; }
static inline DWORD GetTickCount(void) { return 0; }
static inline HANDLE CreateThread(void *a, size_t s, LPTHREAD_START_ROUTINE f, LPVOID p, DWORD fl, DWORD *id)
{ (void)a; (void)s; (void)f; (void)p; (void)fl; (void)id; return NULL; }
static inline BOOL CloseHandle(HANDLE h) { (void)h; return 1; }
/* the cinema detour's calls, never reached by the test (it tests cine_find and cine_tramp), and
 * the critical section import patch's */
#define MEM_COMMIT 0x1000
#define MEM_RESERVE 0x2000
#define MEM_RELEASE 0x8000
#define PAGE_READWRITE 0x04
#define PAGE_EXECUTE_READ 0x20
#define PAGE_EXECUTE_READWRITE 0x40
static inline void *VirtualAlloc(void *a, size_t n, DWORD t, DWORD p) { (void)a; (void)n; (void)t; (void)p; return NULL; }
static inline BOOL VirtualFree(void *a, size_t n, DWORD t) { (void)a; (void)n; (void)t; return 1; }
static inline BOOL VirtualProtect(void *a, size_t n, DWORD p, DWORD *old) { (void)p; *old = 0; return test_protect(a, n); }
static inline BOOL QueryPerformanceFrequency(LARGE_INTEGER *f) { return test_qpf(f); }
static inline BOOL QueryPerformanceCounter(LARGE_INTEGER *c) { return test_qpc(c); }
static inline void YieldProcessor(void) { test_yield(); }
static inline LONG InterlockedCompareExchange(volatile LONG *p, LONG v, LONG cmp) { LONG o = *p; if (o == cmp) *p = v; return o; }
static inline BOOL InitializeCriticalSectionAndSpinCount(CRITICAL_SECTION *c, DWORD n) { return test_cs_init(c, n); }
static inline HANDLE GetCurrentProcess(void) { return NULL; }
static inline BOOL FlushInstructionCache(HANDLE h, const void *a, size_t n) { (void)h; (void)a; (void)n; return 1; }
static inline DWORD GetLastError(void) { return 0; }
static inline DWORD GetPrivateProfileStringA(const char *sec, const char *key, const char *def, char *out, DWORD n,
                                             const char *file)
{
  (void)sec; (void)file;
  const char *v = test_ini(key);
  snprintf(out, n, "%s", v ? v : def);
  return (DWORD)strlen(out);
}
