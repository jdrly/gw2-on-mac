/* ui-scale-probe: watch GW2's interface scale from outside the game, read-only.
 *
 *   scripts/gw2.zsh wine 'C:\…\ui-scale-probe.exe' [seconds]   (default 300)
 *
 * Finds the running Gw2-64.exe, locates the FontContext and the UI layout globals by code
 * pattern (sigs.h), dumps the font size table once, then logs every change of the Interface
 * Size state. It only reads (PROCESS_VM_READ); it writes nothing into the game.
 * Output goes to stdout and ui-scale-probe.log next to the exe. */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdarg.h>
#include "sigs.h"

static FILE *logf;
static void say(const char *fmt, ...)
{
  va_list a;
  SYSTEMTIME t; GetLocalTime(&t);
  char line[1024];
  va_start(a, fmt); vsnprintf(line, sizeof line, fmt, a); va_end(a);
  printf("%02d:%02d:%02d.%03d %s\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, line);
  if (logf) { fprintf(logf, "%02d:%02d:%02d.%03d %s\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, line); fflush(logf); }
  fflush(stdout);
}

static HANDLE proc;
static uint64_t base;
static int rd(uint64_t va, void *out, size_t n)
{
  SIZE_T got = 0;
  return ReadProcessMemory(proc, (LPCVOID)(uintptr_t)va, out, n, &got) && got == n;
}
static uint64_t rd64(uint64_t va) { uint64_t v = 0; rd(va, &v, 8); return v; }
static uint32_t rd32(uint64_t va) { uint32_t v = 0; rd(va, &v, 4); return v; }
static float rdf(uint64_t va) { float v = 0; rd(va, &v, 4); return v; }

static DWORD find_gw2(void)
{
  PROCESSENTRY32W pe = { .dwSize = sizeof pe };
  HANDLE s = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  DWORD pid = 0;
  if (s == INVALID_HANDLE_VALUE) return 0;
  for (BOOL ok = Process32FirstW(s, &pe); ok; ok = Process32NextW(s, &pe))
    if (!lstrcmpiW(pe.szExeFile, L"Gw2-64.exe")) { pid = pe.th32ProcessID; break; }
  CloseHandle(s);
  return pid;
}

static uint64_t find_base(DWORD pid)
{
  MODULEENTRY32W me = { .dwSize = sizeof me };
  HANDLE s = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid);
  uint64_t b = 0;
  if (s == INVALID_HANDLE_VALUE) return 0;
  for (BOOL ok = Module32FirstW(s, &me); ok; ok = Module32NextW(s, &me))
    if (!lstrcmpiW(me.szModule, L"Gw2-64.exe")) { b = (uintptr_t)me.modBaseAddr; break; }
  CloseHandle(s);
  return b;
}

/* height of font entry `e` of step `s` of family `f`, or -1 */
static long entry_height(uint64_t ctx, uint32_t f, uint32_t s, uint32_t e)
{
  uint64_t fams = rd64(ctx + FC_FAMILIES);
  if (f >= rd32(ctx + FC_NFAMILIES)) return -1;
  uint64_t fam = fams + (uint64_t)f * FC_REC_SIZE;
  if (s >= rd32(fam + FC_REC_COUNT)) return -1;
  uint64_t step = rd64(fam + FC_REC_PTR) + (uint64_t)s * FC_REC_SIZE;
  if (e >= rd32(step + FC_REC_COUNT)) return -1;
  return (long)rd32(rd64(step + FC_REC_PTR) + (uint64_t)e * FC_ENTRY_SIZE + FC_ENTRY_HEIGHT);
}

static void dump_table(uint64_t ctx)
{
  uint32_t nf = rd32(ctx + FC_NFAMILIES);
  uint64_t fams = rd64(ctx + FC_FAMILIES);
  say("font table: %u families", nf);
  for (uint32_t f = 0; f < nf && f < 64; f++) {
    uint64_t fam = fams + (uint64_t)f * FC_REC_SIZE;
    uint32_t ns = rd32(fam + FC_REC_COUNT);
    uint64_t steps = rd64(fam + FC_REC_PTR);
    say(" family %u: %u size steps", f, ns);
    for (uint32_t s = 0; s < ns && s < 16; s++) {
      uint64_t step = steps + (uint64_t)s * FC_REC_SIZE;
      uint32_t ne = rd32(step + FC_REC_COUNT);
      uint64_t ents = rd64(step + FC_REC_PTR);
      char line[900]; int o = 0;
      o += snprintf(line + o, sizeof line - o, "  step %u: %u fonts, [+0 +4 +8 +c +10 +14]:", s, ne);
      for (uint32_t e = 0; e < ne && e < 32 && o < (int)sizeof line - 64; e++) {
        uint32_t v[6] = { 0 };
        rd(ents + (uint64_t)e * FC_ENTRY_SIZE, v, sizeof v);
        o += snprintf(line + o, sizeof line - o, " {%x %u %u %u %u %u}", v[0], v[1], v[2], v[3], v[4], v[5]);
      }
      say("%s", line);
    }
  }
}

int main(int argc, char **argv)
{
  int seconds = argc > 1 ? atoi(argv[1]) : 300;
  char path[MAX_PATH];
  DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
  while (n && path[n - 1] != '\\') n--;
  snprintf(path + n, MAX_PATH - n, "ui-scale-probe.log");
  logf = fopen(path, "a");

  DWORD pid = find_gw2();
  if (!pid) { say("Gw2-64.exe is not running"); return 1; }
  proc = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
  if (!proc) { say("OpenProcess(%lu) failed: %lu", pid, GetLastError()); return 1; }
  base = find_base(pid);
  if (!base) { say("no module base for pid %lu", pid); return 1; }

  IMAGE_DOS_HEADER dos; IMAGE_NT_HEADERS64 nt;
  if (!rd(base, &dos, sizeof dos) || !rd(base + dos.e_lfanew, &nt, sizeof nt)) { say("bad PE headers"); return 1; }
  IMAGE_SECTION_HEADER sec[32];
  int nsec = nt.FileHeader.NumberOfSections > 32 ? 32 : nt.FileHeader.NumberOfSections;
  rd(base + dos.e_lfanew + offsetof(IMAGE_NT_HEADERS64, OptionalHeader) + nt.FileHeader.SizeOfOptionalHeader,
     sec, nsec * sizeof *sec);
  uint64_t tva = 0; size_t tlen = 0;
  for (int i = 0; i < nsec; i++)
    if (!memcmp(sec[i].Name, ".text", 6)) { tva = base + sec[i].VirtualAddress; tlen = sec[i].Misc.VirtualSize; }
  uint8_t *text = tlen ? malloc(tlen) : NULL;
  if (!text || !rd(tva, text, tlen)) { say("cannot read .text"); return 1; }
  say("Gw2-64.exe pid %lu base %llx, .text %zu bytes, timestamp %08lx", pid,
      (unsigned long long)base, tlen, nt.FileHeader.TimeDateStamp);

  int c1, c2, c3;
  ptrdiff_t wrap = sig_scan(text, tlen, SIG_FONT_SET_SIZE, &c1);
  ptrdiff_t gsc = sig_scan(text, tlen, SIG_FONT_GET_SCALE, &c2);
  ptrdiff_t lay = sig_scan(text, tlen, SIG_UI_LAYOUT, &c3);
  say("patterns: FontSetSize %d match(es) at +%llx, FontGetScale %d at +%llx, UiLayout %d at +%llx",
      c1, (unsigned long long)(wrap < 0 ? 0 : tva - base + wrap), c2, (unsigned long long)(gsc < 0 ? 0 : tva - base + gsc),
      c3, (unsigned long long)(lay < 0 ? 0 : tva - base + lay));
  if (wrap < 0 || gsc < 0 || lay < 0) { say("a pattern did not match exactly once; stopping"); return 1; }

  ptrdiff_t getter = wrap + 13 + sig_rel32(text + wrap + 9);
  if (getter < 0 || (size_t)getter + 8 > tlen || text[getter] != 0x48 || text[getter + 1] != 0x8d ||
      text[getter + 2] != 0x05 || text[getter + 7] != 0xc3) { say("FontContext getter is not lea rax,[rip+x]; ret"); return 1; }
  uint64_t ctx = tva + getter + 7 + sig_rel32(text + getter + 3);
  uint64_t ui_h = tva + lay + UI_LAYOUT_HEIGHT_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_HEIGHT_INSN + 4);
  uint64_t ui_px = tva + lay + UI_LAYOUT_PIXEL_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_PIXEL_INSN + 4);
  uint64_t ui_w = tva + lay + UI_LAYOUT_WIDTH_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_WIDTH_INSN + 4);
  uint64_t vt = rd64(ctx + FC_VTABLE);
  uint64_t vt0 = rd64(vt);
  say("FontContext at +%llx, vtable +%llx, vtable[0] +%llx (GetScale pattern +%llx: %s)",
      (unsigned long long)(ctx - base), (unsigned long long)(vt - base), (unsigned long long)(vt0 - base),
      (unsigned long long)(tva - base + gsc), vt0 == tva + gsc ? "same" : "DIFFERENT");
  say("UI globals: width +%llx, height +%llx, units per pixel +%llx",
      (unsigned long long)(ui_w - base), (unsigned long long)(ui_h - base), (unsigned long long)(ui_px - base));

  uint32_t last[4] = { ~0u, ~0u, ~0u, ~0u }; float lastf[4] = { -1, -1, -1, -1 };
  int dumped = 0;
  for (DWORD t0 = GetTickCount(); (int)(GetTickCount() - t0) < seconds * 1000; Sleep(200)) {
    DWORD code;
    if (!GetExitCodeProcess(proc, &code) || code != STILL_ACTIVE) { say("Gw2-64.exe exited"); break; }
    uint32_t loaded = rd32(ctx + FC_LOADED), fam = rd32(ctx + FC_FAMILY), nf = rd32(ctx + FC_NFAMILIES);
    int32_t size = (int32_t)rd32(ctx + FC_SIZE);
    float inv = rdf(ctx + FC_INV_SCALE), w = rdf(ui_w), h = rdf(ui_h), px = rdf(ui_px);
    if (loaded && nf && !dumped) { dump_table(ctx); dumped = 1; }
    if (loaded != last[0] || fam != last[1] || (uint32_t)size != last[2] || nf != last[3] ||
        inv != lastf[0] || w != lastf[1] || h != lastf[2] || px != lastf[3]) {
      long hc = size >= 0 ? entry_height(ctx, fam, size, 0) : -1, h0 = entry_height(ctx, 0, 0, 0);
      float expect = size < 0 ? 1.0f + 0.1f * size : (hc > 0 && h0 > 0 ? (float)hc / h0 : 0);
      say("loaded %u family %u size %d (Interface Size %d) 1/scale %.6f -> scale %.6f, "
          "from heights %ld/%ld = %.6f | UI %gx%g, %.6f units/px -> %.6f px/unit",
          loaded, fam, size, size + 1, inv, inv ? 1 / inv : 0, hc, h0, expect, w, h, px, px ? 1 / px : 0);
      last[0] = loaded; last[1] = fam; last[2] = size; last[3] = nf;
      lastf[0] = inv; lastf[1] = w; lastf[2] = h; lastf[3] = px;
    }
  }
  if (dumped) dump_table(ctx);
  say("done");
  return 0;
}
