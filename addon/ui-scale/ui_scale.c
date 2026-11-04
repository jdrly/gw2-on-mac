/* A sharp "Largest" Interface Size for GW2 (docs/research/ui-scale-2026-10-28.md).
 *
 * GW2's interface scale is a ratio of font heights: GetScale() = height(current size step,
 * font 0) / height(Normal, font 0), and the layout divides the screen by it. The font data has
 * three steps (Normal, Large, Larger), and each font of each step names its own pre-rendered
 * glyph files: a size number alone draws no larger glyph. So this remaps: every font of the
 * Larger step borrows the files and sizes of a larger font of the same face found elsewhere in
 * the table (another font, or another step), about new scale / old scale times its cap height.
 * Font 0's donor sets the new layout scale. The small UI sans has no file above Larger's; it
 * borrows the Cronos face (sans=cronos) or keeps its own (sans=keep). One code detour (cinema=1,
 * 2026-11-04) makes the story cinematics' own text use its font's pixel size; nothing else is
 * written: no other code, no file of the game, no pref.
 *
 * Every check passes before anything is written, or nothing is written. The table is watched
 * for reloads (a language change) and patched again. gw2-ui-scale.ini next to the DLL sets the
 * target; gw2-ui-scale.log next to it records every decision. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <math.h>
#include "sigs.h"
#include "ui_scale.h"

#define DEFAULT_SCALE 1.75   /* Larger's target scale (Jan, 2026-10-28); the font-0 strikes give 30/18 = 1.67 */
#define NSTEPS        3      /* size steps in the font data (measured 2026-10-28) */
#define LARGER        2      /* the step this changes */
#define MAX_FAMILIES  64
#define MAX_FONTS     64
#define MAX_HEIGHT    255    /* the data stores sizes as bytes */
#define POLL_MS       100    /* while waiting for the table */
#define IDLE_MS       500    /* once patched (or stopped): watch for reloads and size changes */
#define RETRIES       100    /* transient check failures tolerated (10 s) before giving up */

static char dir[MAX_PATH];
static CRITICAL_SECTION log_lock;
static HANDLE log_file = INVALID_HANDLE_VALUE;

void ui_log(const char *fmt, ...)
{
  char line[1024];
  SYSTEMTIME t;
  GetLocalTime(&t);
  int n = snprintf(line, sizeof line, "%04d-%02d-%02d %02d:%02d:%02d.%03d ", t.wYear, t.wMonth, t.wDay,
                   t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
  va_list a;
  va_start(a, fmt);
  n += vsnprintf(line + n, sizeof line - n - 2, fmt, a);
  va_end(a);
  if (n > (int)sizeof line - 3) n = sizeof line - 3;
  line[n++] = '\r';
  line[n++] = '\n';
  EnterCriticalSection(&log_lock);
  if (log_file == INVALID_HANDLE_VALUE) {
    char path[MAX_PATH + 32];
    snprintf(path, sizeof path, "%sgw2-ui-scale.log", dir);
    log_file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  }
  DWORD w;
  if (log_file != INVALID_HANDLE_VALUE) WriteFile(log_file, line, n, &w, NULL);
  LeaveCriticalSection(&log_lock);
}

/* ---- memory: reads and writes that fail instead of faulting ----
 * IsBadReadPtr/IsBadWritePtr probe locally (an exception handler, no wineserver round trip,
 * unlike ReadProcessMemory), which matters in a poll loop of a CPU-bound game. The table is
 * freed only when the game unloads it, which the loaded flag shows first. */

static int rd(uintptr_t a, void *out, size_t n)
{
  if (!a || IsBadReadPtr((const void *)a, n)) return 0;
  memcpy(out, (const void *)a, n);
  return 1;
}
static uint32_t rd32(uintptr_t a) { uint32_t v = 0; rd(a, &v, 4); return v; }
static uintptr_t rdp(uintptr_t a) { uintptr_t v = 0; rd(a, &v, sizeof v); return v; }
static float rdf(uintptr_t a) { float v = 0; rd(a, &v, 4); return v; }
static int wr32(uintptr_t a, uint32_t v)
{
  if (!a || (a & 3) || IsBadWritePtr((void *)a, 4)) return 0;
  InterlockedExchange((volatile LONG *)a, (LONG)v);  /* aligned, whole: never a torn size */
  return 1;
}

/* ---- what the patterns find ---- */

static uintptr_t image, image_end, ctx, get_scale, ui_w, ui_h, ui_px, getter_va;
static const uint8_t *text_sec;
static size_t text_len;

static int locate(void)
{
  image = (uintptr_t)GetModuleHandleW(NULL);
  const IMAGE_DOS_HEADER *dos = (const IMAGE_DOS_HEADER *)image;
  const IMAGE_NT_HEADERS64 *nt = (const IMAGE_NT_HEADERS64 *)(image + dos->e_lfanew);
  image_end = image + nt->OptionalHeader.SizeOfImage;
  const IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
  const uint8_t *text = NULL;
  size_t tlen = 0;
  for (int i = 0; i < nt->FileHeader.NumberOfSections; i++)
    if (!memcmp(sec[i].Name, ".text", 6)) { text = (const uint8_t *)(image + sec[i].VirtualAddress); tlen = sec[i].Misc.VirtualSize; }
  ui_log("Gw2-64.exe at %p, timestamp %08lx, .text %zu bytes", (void *)image, nt->FileHeader.TimeDateStamp, tlen);
  if (!text) { ui_log("check failed: no .text section"); return 0; }

  int c1, c2, c3;
  ptrdiff_t wrap = sig_scan(text, tlen, SIG_FONT_SET_SIZE, &c1);
  ptrdiff_t gsc = sig_scan(text, tlen, SIG_FONT_GET_SCALE, &c2);
  ptrdiff_t lay = sig_scan(text, tlen, SIG_UI_LAYOUT, &c3);
  ui_log("patterns: FontSetSize %d match(es), FontGetScale %d, UiLayout %d", c1, c2, c3);
  if (wrap < 0 || gsc < 0 || lay < 0) { ui_log("check failed: a pattern did not match exactly once (game update?)"); return 0; }

  ptrdiff_t getter = wrap + 13 + sig_rel32(text + wrap + 9);
  if (getter < 0 || (size_t)getter + 8 > tlen || text[getter] != 0x48 || text[getter + 1] != 0x8d ||
      text[getter + 2] != 0x05 || text[getter + 7] != 0xc3) {
    ui_log("check failed: the FontContext getter is not lea rax,[rip+x]; ret");
    return 0;
  }
  uintptr_t tva = (uintptr_t)text;
  text_sec = text;
  text_len = tlen;
  getter_va = tva + getter;
  ctx = tva + getter + 7 + sig_rel32(text + getter + 3);
  get_scale = tva + gsc;
  ui_h = tva + lay + UI_LAYOUT_HEIGHT_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_HEIGHT_INSN + 4);
  ui_px = tva + lay + UI_LAYOUT_PIXEL_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_PIXEL_INSN + 4);
  ui_w = tva + lay + UI_LAYOUT_WIDTH_INSN + 8 + sig_rel32(text + lay + UI_LAYOUT_WIDTH_INSN + 4);
  if (ctx < image || ctx >= image_end || ui_w < image || ui_w >= image_end) {
    ui_log("check failed: FontContext or UI globals outside the image");
    return 0;
  }
  ui_log("FontContext +%llx, GetScale +%llx, UI width/height/units-per-pixel +%llx/+%llx/+%llx",
         (unsigned long long)(ctx - image), (unsigned long long)(get_scale - image), (unsigned long long)(ui_w - image),
         (unsigned long long)(ui_h - image), (unsigned long long)(ui_px - image));
  return 1;
}

/* ---- the font table ---- */

typedef struct { uintptr_t ents; uint32_t n; } step_t;
typedef struct { uint32_t nsteps; step_t step[NSTEPS]; } family_t;
typedef struct { uintptr_t fams; uint32_t nfam; family_t fam[MAX_FAMILIES]; } table_t;

static uintptr_t entry(const table_t *t, uint32_t f, uint32_t s, uint32_t e)
{
  return t->fam[f].step[s].ents + (uintptr_t)e * FC_ENTRY_SIZE;
}
static uint32_t height(const table_t *t, uint32_t f, uint32_t s, uint32_t e)
{
  return rd32(entry(t, f, s, e) + FC_ENTRY_HEIGHT);
}

/* Reads the table's shape; with `values`, also checks the sizes are the game's own (bytes,
 * growing with the step). 0 and a reason when anything is off. */
static int read_table(table_t *t, int values, char *why, size_t whylen)
{
  memset(t, 0, sizeof *t);
  t->fams = rdp(ctx + FC_FAMILIES);
  t->nfam = rd32(ctx + FC_NFAMILIES);
  if (!t->fams || t->nfam < 1 || t->nfam > MAX_FAMILIES) {
    snprintf(why, whylen, "%u font families at %p", t->nfam, (void *)t->fams);
    return 0;
  }
  for (uint32_t f = 0; f < t->nfam; f++) {
    uintptr_t fam = t->fams + (uintptr_t)f * FC_REC_SIZE;
    uint32_t ns = rd32(fam + FC_REC_COUNT);
    uintptr_t steps = rdp(fam + FC_REC_PTR);
    if (ns != 0 && ns != NSTEPS) { snprintf(why, whylen, "family %u has %u size steps, not 0 or %d", f, ns, NSTEPS); return 0; }
    if (ns && !steps) { snprintf(why, whylen, "family %u: no step array", f); return 0; }
    t->fam[f].nsteps = ns;
    for (uint32_t s = 0; s < ns; s++) {
      uintptr_t step = steps + (uintptr_t)s * FC_REC_SIZE;
      step_t *st = &t->fam[f].step[s];
      st->n = rd32(step + FC_REC_COUNT);
      st->ents = rdp(step + FC_REC_PTR);
      if (!st->ents || st->n < 1 || st->n > MAX_FONTS || st->n != t->fam[f].step[0].n) {
        snprintf(why, whylen, "family %u step %u: %u fonts at %p", f, s, st->n, (void *)st->ents);
        return 0;
      }
      for (uint32_t e = 0; e < st->n; e++) {
        uint32_t v[6];
        if (!rd(entry(t, f, s, e), v, sizeof v)) { snprintf(why, whylen, "family %u step %u font %u unreadable", f, s, e); return 0; }
        if (values && (v[1] > MAX_HEIGHT || v[2] > MAX_HEIGHT || (!v[2] && v[1]) || (!e && !v[2]))) {
          snprintf(why, whylen, "family %u step %u font %u: sizes %u/%u", f, s, e, v[1], v[2]);
          return 0;
        }
      }
    }
  }
  if (t->fam[0].nsteps != NSTEPS) { snprintf(why, whylen, "family 0 has %u size steps", t->fam[0].nsteps); return 0; }
  if (values && !(height(t, 0, 0, 0) <= height(t, 0, 1, 0) && height(t, 0, 1, 0) <= height(t, 0, LARGER, 0))) {
    snprintf(why, whylen, "family 0 heights %u/%u/%u do not grow with the step", height(t, 0, 0, 0),
             height(t, 0, 1, 0), height(t, 0, LARGER, 0));
    return 0;
  }
  return 1;
}

/* The family GetScale uses: the current one, or family 0 when it has no steps. */
static uint32_t effective_family(const table_t *t)
{
  uint32_t f = rd32(ctx + FC_FAMILY);
  return f < t->nfam && t->fam[f].nsteps ? f : 0;
}

/* What FontContext::GetScale returns for the current state (0x140a64d30 in the 2026-10-27 build). */
static double game_scale(const table_t *t, int32_t size)
{
  if (size < 0) return 1.0 + 0.1 * size;
  uint32_t f = effective_family(t), s = size > LARGER ? LARGER : (uint32_t)size;
  if (f == 0 && s == 0) return 1.0;
  return (double)height(t, f, s, 0) / height(t, 0, 0, 0);
}

/* The arrays a reload replaces. */
static uint64_t table_sig(const table_t *t)
{
  uint64_t h = t->fams ^ ((uint64_t)t->nfam << 48);
  for (uint32_t f = 0; f < t->nfam; f++)
    if (t->fam[f].nsteps) h = h * 1000003u ^ t->fam[f].step[LARGER].ents;
  return h;
}

/* ---- the change ---- */

static struct { int enabled, sans_keep, cinema; uint32_t keep; double scale; } cfg;  /* keep: bit per font index */

static void read_config(void)
{
  char path[MAX_PATH + 32], v[64], *end;
  snprintf(path, sizeof path, "%sgw2-ui-scale.ini", dir);
  GetPrivateProfileStringA("ui-scale", "enabled", "1", v, sizeof v, path);
  cfg.enabled = atoi(v) != 0;
  GetPrivateProfileStringA("ui-scale", "scale", "", v, sizeof v, path);
  cfg.scale = strtod(v, &end);
  if (end == v || !(cfg.scale > 0)) {
    if (*v) ui_log("config: scale=%s is not a number; using %.2f", v, DEFAULT_SCALE);
    cfg.scale = DEFAULT_SCALE;
  }
  GetPrivateProfileStringA("ui-scale", "factor", "", v, sizeof v, path);
  if (*v) ui_log("config: factor= is no longer used (sizes alone draw no larger glyph); ignored");
  GetPrivateProfileStringA("ui-scale", "sans", "cronos", v, sizeof v, path);
  cfg.sans_keep = !lstrcmpiA(v, "keep");
  if (!cfg.sans_keep && lstrcmpiA(v, "cronos")) ui_log("config: sans=%s is not cronos or keep; using cronos", v);
  GetPrivateProfileStringA("ui-scale", "keep", "", v, sizeof v, path);
  cfg.keep = 0;
  for (char *p = v; *p;) {
    long i = strtol(p, &end, 10);
    if (end == p) { p++; continue; }
    if (i >= 1 && i < 32) cfg.keep |= 1u << i;
    else ui_log("config: keep=%ld is not a font index 1-31; ignored", i);
    p = end;
  }
  char keep[64];
  snprintf(keep, sizeof keep, "%s", *v ? v : "(none)");
  GetPrivateProfileStringA("ui-scale", "cinema", "1", v, sizeof v, path);
  cfg.cinema = atoi(v) != 0;
  ui_log("config %s: enabled=%d scale=%.3f sans=%s keep=%s cinema=%d", path, cfg.enabled, cfg.scale,
         cfg.sans_keep ? "keep" : "cronos", keep, cfg.cinema);
}

/* The Latin font table this remap knows (family 0, from the AFNT file 154945 and its glyph
 * files, decoded 2026-10-28): per font index, its face and, per step, its sizes (+0x04/+0x08)
 * and the cap height of its glyphs ('H', in pixels). The live table must match the sizes
 * exactly, or nothing is written. */
enum { CRONOS, CRONOS_ITALIC, SANS, SANS_ITALIC };
static const char *face_name[] = { "Cronos", "Cronos italic", "UI sans", "UI sans italic" };
static const struct { uint8_t face, s4[NSTEPS], s8[NSTEPS], cap[NSTEPS]; } known[] = {
  { CRONOS,        { 20, 22, 24 }, { 18, 20, 22 }, { 12, 13, 15 } },
  { SANS,          { 14, 16, 17 }, { 16, 16, 18 }, { 10, 11, 13 } },
  { CRONOS,        { 33, 36, 38 }, { 30, 33, 34 }, { 20, 22, 24 } },
  { SANS,          { 14, 16, 17 }, { 16, 16, 18 }, { 10, 11, 13 } },
  { SANS_ITALIC,   { 16, 18, 18 }, { 15, 16, 19 }, { 10, 11, 13 } },
  { CRONOS,        { 18, 20, 22 }, { 16, 18, 20 }, { 11, 12, 13 } },
  { SANS,          { 13, 14, 16 }, { 15, 16, 17 }, {  9, 11, 12 } },
  { CRONOS,        { 40, 43, 47 }, { 37, 39, 43 }, { 25, 27, 29 } },
  { CRONOS_ITALIC, { 41, 44, 48 }, { 37, 39, 43 }, { 25, 27, 29 } },
  { CRONOS,        { 33, 36, 38 }, { 30, 33, 34 }, { 20, 22, 24 } },
  { CRONOS_ITALIC, { 34, 36, 39 }, { 30, 33, 34 }, { 20, 22, 24 } },
  { CRONOS,        { 26, 30, 32 }, { 24, 27, 29 }, { 16, 18, 20 } },
  { CRONOS_ITALIC, { 27, 30, 32 }, { 24, 27, 29 }, { 16, 18, 20 } },
  { CRONOS_ITALIC, { 31, 36, 38 }, { 28, 32, 34 }, { 19, 22, 23 } },
};
#define NKNOWN (sizeof known / sizeof *known)
/* the entry fields a remap copies: sizes, sub-font count, first name, first range */
static const uint32_t remap_fields[] = { 0x04, FC_ENTRY_HEIGHT, FC_ENTRY_SUBFONTS, FC_ENTRY_NAME, FC_ENTRY_RANGE };
#define NFIELDS (sizeof remap_fields / sizeof *remap_fields)

/* 1 when family 0 is exactly the known table; else 0 and the first difference */
static int known_table(const table_t *t, char *why, size_t whylen)
{
  if (t->fam[0].nsteps != NSTEPS || t->fam[0].step[0].n != NKNOWN) {
    snprintf(why, whylen, "family 0 has %u steps of %u fonts, not %d of %u", t->fam[0].nsteps, t->fam[0].step[0].n,
             NSTEPS, (unsigned)NKNOWN);
    return 0;
  }
  for (uint32_t s = 0; s < NSTEPS; s++)
    for (uint32_t e = 0; e < NKNOWN; e++) {
      uintptr_t a = entry(t, 0, s, e);
      if (rd32(a + 4) != known[e].s4[s] || rd32(a + FC_ENTRY_HEIGHT) != known[e].s8[s]) {
        snprintf(why, whylen, "step %u font %u is %u/%u, not %u/%u", s, e, rd32(a + 4), rd32(a + FC_ENTRY_HEIGHT),
                 known[e].s4[s], known[e].s8[s]);
        return 0;
      }
    }
  return 1;
}

typedef struct { uintptr_t addr; uint32_t orig, wrote; } patch_t;
static patch_t patches[NKNOWN * NFIELDS];
static int npatches;
static uint64_t applied_sig;
static double new_scale, old_scale;

enum { APPLY_OK, APPLY_RETRY, APPLY_FAIL };

static void log_fonts(const table_t *t, uint32_t f);

static int try_apply(int first_try)
{
  char why[160];
  table_t t;
  uintptr_t vt = rdp(ctx + FC_VTABLE);
  if (vt < image || vt >= image_end || rdp(vt) != get_scale) {
    ui_log("check failed: FontContext vtable %p slot 0 %p is not GetScale %p", (void *)vt, (void *)rdp(vt), (void *)get_scale);
    return APPLY_FAIL;
  }
  if (!read_table(&t, 1, why, sizeof why)) { ui_log("check failed: %s; writing nothing", why); return APPLY_FAIL; }

  int32_t size = (int32_t)rd32(ctx + FC_SIZE);
  float inv = rdf(ctx + FC_INV_SCALE);
  double expect = game_scale(&t, size);
  /* Before the first layout with the fonts loaded, 1/scale is still the constructor's 1.0 (the
   * layout ran while GetScale had no table): patching now means no font is ever built at the
   * old size. Seen at every start so far: size 2, 1/scale 1.0, UI 1024x768. */
  int unlaid = inv == 1.0f && fabs(expect - 1.0) > 1e-3;
  if (size < -1 || size > LARGER || !(inv > 0) || (!unlaid && fabs(1.0 / inv - expect) > 1e-3)) {
    if (first_try)
      ui_log("waiting: size %d, 1/scale %.6f, table says %.6f (the game may be mid-update)", size, inv, expect);
    return APPLY_RETRY;
  }
  if (unlaid) ui_log("the UI is not laid out with the fonts yet (size %d, 1/scale 1.0): patching before it is", size);

  uint32_t f = effective_family(&t);
  log_fonts(&t, f);
  if (f != 0) {
    ui_log("the current font family is %u, not 0 (the Latin fonts this remap knows); writing nothing", f);
    return APPLY_FAIL;
  }
  if (!known_table(&t, why, sizeof why)) {
    ui_log("the font table is not the one this remap knows (%s), probably a game update; writing nothing", why);
    return APPLY_FAIL;
  }
  uint32_t h00 = known[0].s8[0];
  old_scale = (double)known[0].s8[LARGER] / h00;

  /* Font 0 sets the layout scale: the Cronos strike whose height is nearest the target (ties
   * down), capped so the layout stays at or above 1024x768. The layout before the scale is the
   * UI size times the current scale once laid out; before that the screen (the game runs
   * fullscreen; a smaller window or DPI Scaling only gets the warning once active). */
  float w = rdf(ui_w), h = rdf(ui_h);
  double pre_w = 0, pre_h = 0;
  if (!unlaid && w > 0 && h > 0) {
    pre_w = w / inv;
    pre_h = h / inv;
  }
  /* A layout at exactly the 1024x768 floor is also what the game shows before its first real
   * layout, and at Normal 1/scale 1.0 can't tell the two apart (2026-10-28 15:23: a start at
   * Normal wrote nothing). Then the screen decides, as before the first layout. */
  if (pre_w < 1024.5 && pre_h < 768.5) {
    pre_w = GetSystemMetrics(SM_CXSCREEN);
    pre_h = GetSystemMetrics(SM_CYSCREEN);
  }
  double smax = pre_w > 0 && pre_h > 0 ? fmin(pre_w / 1024, pre_h / 768) : 1e9;
  if (smax == 1e9) ui_log("screen size not known; the 1024x768 floor is checked once the scale is active");
  int d0i = -1, d0s = 0;
  for (uint32_t e = 0; e < NKNOWN; e++)
    for (int st = 0; st < NSTEPS; st++) {
      if (known[e].face != CRONOS || (double)known[e].s8[st] / h00 > smax) continue;
      double dist = fabs(known[e].s8[st] - cfg.scale * h00), best = d0i < 0 ? 1e9 : fabs(known[d0i].s8[d0s] - cfg.scale * h00);
      if (d0i < 0 || dist < best - 1e-9 || (fabs(dist - best) < 1e-9 && known[e].s8[st] < known[d0i].s8[d0s])) {
        d0i = (int)e;
        d0s = st;
      }
    }
  double scale = d0i < 0 ? old_scale : (double)known[d0i].s8[d0s] / h00;
  if (scale <= old_scale + 1e-9) {
    ui_log("target scale %.3f: no Cronos strike above Larger's %.4f fits; writing nothing", cfg.scale, old_scale);
    return APPLY_FAIL;
  }
  double r = scale / old_scale;
  ui_log("target scale %.3f: font 0 takes font %d step %d (%u/%u), scale %.4f -> %.4f, text x%.3f%s", cfg.scale, d0i,
         d0s, known[d0i].s4[d0s], known[d0i].s8[d0s], old_scale, scale, r, smax < 1e9 ? "" : " (floor unchecked)");

  /* every Larger font: the strike of its face (Cronos for the UI sans, unless sans=keep) whose
   * cap height is nearest r times its own (ties down); kept when that is no larger */
  int donor_i[NKNOWN], donor_s[NKNOWN];
  for (uint32_t x = 0; x < NKNOWN; x++) {
    donor_i[x] = -1;
    int face = known[x].face, cap = known[x].cap[LARGER];
    if (x == 0) { donor_i[0] = d0i; donor_s[0] = d0s; }
    else {
      if (cfg.keep & (1u << x)) {
        ui_log(" font %2u (%s, cap %d): kept (keep=)", x, face_name[face], cap);
        continue;
      }
      if ((face == SANS || face == SANS_ITALIC) && cfg.sans_keep) {
        ui_log(" font %2u (%s, cap %d): kept (sans=keep)", x, face_name[face], cap);
        continue;
      }
      int want = face == SANS ? CRONOS : face == SANS_ITALIC ? CRONOS_ITALIC : face;
      double target = cap * r;
      for (uint32_t e = 0; e < NKNOWN; e++)
        for (int st = 0; st < NSTEPS; st++) {
          if (known[e].face != want) continue;
          int c = known[e].cap[st];
          double dist = fabs(c - target), best = donor_i[x] < 0 ? 1e9 : fabs(known[donor_i[x]].cap[donor_s[x]] - target);
          if (donor_i[x] < 0 || dist < best - 1e-9 || (fabs(dist - best) < 1e-9 && c < known[donor_i[x]].cap[donor_s[x]])) {
            donor_i[x] = (int)e;
            donor_s[x] = st;
          }
        }
      if (donor_i[x] < 0 || known[donor_i[x]].cap[donor_s[x]] <= cap) {
        ui_log(" font %2u (%s, cap %d): kept (no larger %s strike)", x, face_name[face], cap, face_name[want]);
        donor_i[x] = -1;
        continue;
      }
    }
    ui_log(" font %2u (%s, cap %d): font %d step %d (%s, cap %d, %u/%u)", x, face_name[face], cap, donor_i[x],
           donor_s[x], face_name[known[donor_i[x]].face], known[donor_i[x]].cap[donor_s[x]],
           known[donor_i[x]].s4[donor_s[x]], known[donor_i[x]].s8[donor_s[x]]);
  }

  /* the plan from the table as it is now, before anything changes (a donor may be a Larger font) */
  npatches = 0;
  for (uint32_t x = 0; x < NKNOWN; x++) {
    if (donor_i[x] < 0) continue;
    uintptr_t to = entry(&t, 0, LARGER, x), from = entry(&t, 0, donor_s[x], donor_i[x]);
    for (uint32_t k = 0; k < NFIELDS; k++)
      patches[npatches++] = (patch_t){ to + remap_fields[k], rd32(to + remap_fields[k]), rd32(from + remap_fields[k]) };
  }
  if (!cfg.enabled) {
    /* enabled=0: everything above (checks, the font table and the plan in the log) but no write */
    ui_log("observing only (enabled=0): would write %d fields; writing nothing", npatches);
    npatches = 0;
    new_scale = old_scale;
    applied_sig = table_sig(&t);
    return APPLY_OK;
  }
  int failed = 0;
  for (int i = 0; i < npatches; i++)
    if (!wr32(patches[i].addr, patches[i].wrote) || rd32(patches[i].addr) != patches[i].wrote) failed++;
  new_scale = (double)height(&t, 0, LARGER, 0) / h00;
  applied_sig = table_sig(&t);
  ui_log("wrote %d entry fields (%d failed) in step Larger of family 0: Larger's scale %.4f -> %.4f", npatches, failed,
         old_scale, new_scale);
  if (failed) {
    for (int i = 0; i < npatches; i++) wr32(patches[i].addr, patches[i].orig);
    ui_log("a write failed; put the game's values back");
    return APPLY_FAIL;
  }
  if (size == LARGER && !unlaid)
    ui_log("Interface Size is Larger already: select another size and Larger again if it does not change");
  return APPLY_OK;
}

/* Every font of family f, per size step: its two sizes and its sub-font names with their
 * character ranges, read-only, for the log (what each face is made of, and whether a face
 * names other files at other sizes). Logged once per table, before anything is written. */
static void log_fonts(const table_t *t, uint32_t f)
{
  uintptr_t names = rdp(ctx + FC_NAMES), ranges = rdp(ctx + FC_RANGES);
  uint32_t nnames = rd32(ctx + FC_NNAMES), nranges = rd32(ctx + FC_NRANGES);
  ui_log("fonts of family %u (%u name chars, %u ranges):", f, nnames, nranges);
  for (uint32_t s = 0; s < NSTEPS; s++)
    for (uint32_t e = 0; e < t->fam[f].step[s].n; e++) {
      uintptr_t a = entry(t, f, s, e);
      uint32_t subs = rd32(a + FC_ENTRY_SUBFONTS), name = rd32(a + FC_ENTRY_NAME), range = rd32(a + FC_ENTRY_RANGE);
      char line[900];
      int o = snprintf(line, sizeof line, " step %u font %2u: %u/%u", s, e, rd32(a + 4), rd32(a + FC_ENTRY_HEIGHT));
      for (uint32_t i = 0; i < subs && i < 16 && name < nnames && o < (int)sizeof line - 80; i++) {
        /* names are dat file references (two code units each so far), so raw hex, not text */
        char n[48];
        int k = 0;
        for (uint16_t c; name < nnames && rd(names + 2 * (uintptr_t)name, &c, 2) && c; name++)
          if (k < (int)sizeof n - 6) k += snprintf(n + k, sizeof n - k, "%s%04x", k ? ":" : "", c);
        name++;  /* past the terminator */
        n[k] = 0;
        uint32_t lo = 0, hi = 0;
        if (range + i < nranges) {
          lo = rd32(ranges + 8 * (uintptr_t)(range + i)) & 0xffff;
          hi = rd32(ranges + 8 * (uintptr_t)(range + i) + 4) & 0xffff;
        }
        if (k) o += snprintf(line + o, sizeof line - o, " [%x-%x %s]", lo, hi, n);
      }
      ui_log("%s", line);
    }
}

/* The fonts FontContext has built (GetFont's cache), "index:height", for the log. */
static void log_cache(void)
{
  char line[700];
  int o = 0;
  uint32_t n = rd32(ctx + FC_NCACHE);
  uintptr_t c = rdp(ctx + FC_CACHE);
  for (uint32_t i = 0; i < n && i < 64 && o < (int)sizeof line - 16; i++) {
    uintptr_t e = c + (uintptr_t)i * FC_CACHE_SIZE;
    uintptr_t obj = rdp(e);
    /* index:cached height/the font object's own line height (+0x2c) */
    if (obj) o += snprintf(line + o, sizeof line - o, " %u:%u/%u", i, rd32(e + FC_CACHE_HEIGHT), rd32(obj + 0x2c));
  }
  ui_log("font cache: %u entries,%s", n, o ? line : " none built");
}

/* A fingerprint of GetFont's cache (which fonts are built, their objects and heights), so the
 * log shows every font the game builds later, e.g. when a story dialogue opens (Jan, 2026-11-04:
 * its text stays small). Read-only. */
static uint64_t cache_sig(void)
{
  uint64_t h = 1469598103934665603ull;
  uint32_t n = rd32(ctx + FC_NCACHE);
  uintptr_t c = rdp(ctx + FC_CACHE);
  h = (h ^ n) * 1099511628211ull;
  h = (h ^ c) * 1099511628211ull;
  for (uint32_t i = 0; i < n && i < 64; i++) {
    uintptr_t e = c + (uintptr_t)i * FC_CACHE_SIZE;
    h = (h ^ rdp(e)) * 1099511628211ull;
    h = (h ^ rd32(e + FC_CACHE_HEIGHT)) * 1099511628211ull;
  }
  return h;
}

/* 1 while our values are in place, 0 when the game replaced some (logged). */
static int still_applied(void)
{
  int orig = 0, ours = 0;
  for (int i = 0; i < npatches; i++) {
    uint32_t v = rd32(patches[i].addr);
    if (v == patches[i].wrote) ours++;
    else if (v == patches[i].orig) orig++;
  }
  if (ours == npatches) return 1;
  ui_log("font sizes changed by the game (%d ours, %d back to the original, %d other); checking again",
         ours, orig, npatches - ours - orig);
  return 0;
}

/* ---- cinema text: draw it at its font's pixel size (2026-11-04) ----
 * The story cinematics' subtitles (the letterboxed dialogue) are the cinema engine's own text
 * (sigs.h, SIG_CINE_TEXT_FONT). It sizes glyphs and line pitch by GetFont's height in UI
 * units, pixel height / scale, times the cinema's own scale: the UI scale divides it and nothing
 * multiplies it back. Every Interface Size therefore draws it about as tall as Normal, scaled from
 * the step's raster, and the remap (a raster 1.36x larger, a scale 1.36x larger) changes nothing.
 * A detour after that GetFont call divides the stored height by 1/scale (FontContext +0x14,
 * read live): the text then is its font's pixel height, drawn 1:1 like the rest of the UI. At
 * Normal 1/scale is 1 and nothing changes. This is the addon's one code patch: 7 bytes at the
 * site, the rest in a page of its own next to the game. cinema=0 in the ini leaves it out. */

/* The trampoline's data, on the page after its code (read-write; the code page is read-execute):
 * the last cinema text it converted. 2026-11-04: the slots shared the code page, which is made
 * read-execute after writing, so the first cinematic crashed on the first store. */
#define CINE_SLOTS 0x1000
typedef struct { uint64_t key; uint64_t obj; float units, px; volatile LONG count; } cine_slots_t;

static int put_rel32(uint8_t *p, uintptr_t end, uintptr_t to)
{
  int64_t d = (int64_t)to - (int64_t)end;
  if (d < INT32_MIN || d > INT32_MAX) return 0;
  int32_t v = (int32_t)d;
  memcpy(p, &v, 4);
  return 1;
}

/* The trampoline for code at `va`, slots at va + CINE_SLOTS: records the font key (rbx) and the
 * text object (rsi), turns +0x2d8 from UI units into pixels when 1/scale is above 0, then runs
 * the displaced instruction and jumps back. xmm0-2 are free here: the code right after the site
 * calls functions or returns, and GetFont (a call) has just clobbered them. Returns its length,
 * or 0 when a target is out of rel32 range. */
static int cine_tramp(uint8_t *c, uintptr_t va, uintptr_t back, uintptr_t inv_va, const uint8_t *displaced)
{
  uintptr_t s = va + CINE_SLOTS;
  int n = 0, ok = 1;
#define EMIT(...) do { const uint8_t b_[] = { __VA_ARGS__ }; memcpy(c + n, b_, sizeof b_); n += sizeof b_; } while (0)
#define REL(to) do { ok &= put_rel32(c + n, va + n + 4, (to)); n += 4; } while (0)
  EMIT(0x48, 0x89, 0x1d); REL(s + offsetof(cine_slots_t, key));               /* mov [rip+key], rbx */
  EMIT(0x48, 0x89, 0x35); REL(s + offsetof(cine_slots_t, obj));               /* mov [rip+obj], rsi */
  EMIT(0xf3, 0x0f, 0x10, 0x86, 0xd8, 0x02, 0x00, 0x00);                       /* movss xmm0,[rsi+0x2d8] */
  EMIT(0xf3, 0x0f, 0x11, 0x05); REL(s + offsetof(cine_slots_t, units));       /* movss [rip+units], xmm0 */
  EMIT(0xf3, 0x0f, 0x10, 0x0d); REL(inv_va);                                  /* movss xmm1,[rip+1/scale] */
  EMIT(0x0f, 0x57, 0xd2);                                                     /* xorps xmm2,xmm2 */
  EMIT(0x0f, 0x2f, 0xca);                                                     /* comiss xmm1,xmm2 */
  EMIT(0x76, 0x1a);                                                           /* jbe skip (not above 0, NaN) */
  EMIT(0xf3, 0x0f, 0x5e, 0xc1);                                               /* divss xmm0,xmm1 */
  EMIT(0xf3, 0x0f, 0x11, 0x86, 0xd8, 0x02, 0x00, 0x00);                       /* movss [rsi+0x2d8],xmm0 */
  EMIT(0xf3, 0x0f, 0x11, 0x05); REL(s + offsetof(cine_slots_t, px));          /* movss [rip+px], xmm0 */
  EMIT(0xff, 0x05); REL(s + offsetof(cine_slots_t, count));                   /* inc dword [rip+count] */
  /* skip: */
  memcpy(c + n, displaced, CINE_SITE_LEN); n += CINE_SITE_LEN;               /* lea r14,[rsi+0x2fc] */
  EMIT(0xe9); REL(back);                                                      /* jmp back */
#undef EMIT
#undef REL
  return ok && n <= CINE_SLOTS ? n : 0;
}

static uintptr_t cine_site, cine_page;
static cine_slots_t *cine_slots;

/* The site, checked: the pattern once, its call is the FontContext getter, and the height's use
 * follows. 0 and a reason otherwise. */
static uintptr_t cine_find(const uint8_t *text, size_t tlen, uintptr_t tva, uintptr_t getter, char *why, size_t whylen)
{
  int c;
  ptrdiff_t at = sig_scan(text, tlen, SIG_CINE_TEXT_FONT, &c);
  if (at < 0) { snprintf(why, whylen, "its pattern matched %d times, not once (game update?)", c); return 0; }
  uintptr_t call = tva + at + 5 + sig_rel32(text + at + 1);
  if (call != getter) { snprintf(why, whylen, "its call goes to %p, not the FontContext getter %p", (void *)call, (void *)getter); return 0; }
  size_t from = at + CINE_SITE, span = from + CINE_USE_RANGE <= tlen ? CINE_USE_RANGE : tlen - from;
  if (!sig_within(text + from, span, SIG_CINE_TEXT_USE)) { snprintf(why, whylen, "the glyph height's use is not after it"); return 0; }
  return tva + from;
}

static void cine_install(void)
{
  char why[160];
  uintptr_t site = cine_find(text_sec, text_len, (uintptr_t)text_sec, getter_va, why, sizeof why);
  if (!site) { ui_log("cinema text: %s; leaving it as it is", why); return; }
  /* a page within rel32 reach of the game: below the image first, then above it */
  uint8_t *page = NULL;
  for (int64_t d = 0x10000; !page && d < 0x7ff00000; d += 0x10000) {
    uintptr_t lo = (image & ~(uintptr_t)0xffff) - (uintptr_t)d;
    uintptr_t hi = ((image_end + 0xffff) & ~(uintptr_t)0xffff) + (uintptr_t)d - 0x10000;
    if (lo < image && image - lo < 0x7ff00000)
      page = VirtualAlloc((void *)lo, 0x2000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!page && hi - image < 0x7ff00000)
      page = VirtualAlloc((void *)hi, 0x2000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  }
  if (!page) { ui_log("cinema text: no memory near the game for the detour; leaving it as it is"); return; }
  int n = cine_tramp(page, (uintptr_t)page, site + CINE_SITE_LEN, ctx + FC_INV_SCALE, (const uint8_t *)site);
  uint8_t jmp[CINE_SITE_LEN] = { 0xe9, 0, 0, 0, 0, 0x90, 0x90 };
  if (!n || !put_rel32(jmp + 1, site + 5, (uintptr_t)page)) {
    VirtualFree(page, 0, MEM_RELEASE);
    ui_log("cinema text: the detour at %p is out of reach of the site; leaving it as it is", (void *)page);
    return;
  }
  DWORD old, tmp;
  /* only the code page becomes read-execute; the slots' page stays read-write */
  if (!VirtualProtect(page, 0x1000, PAGE_EXECUTE_READ, &old)) {
    VirtualFree(page, 0, MEM_RELEASE);
    ui_log("cinema text: cannot make the detour executable (%lu); leaving it as it is", (unsigned long)GetLastError());
    return;
  }
  FlushInstructionCache(GetCurrentProcess(), page, n);
  /* Written once at load, long before a cinematic runs: nothing executes the site meanwhile. */
  if (!VirtualProtect((void *)site, CINE_SITE_LEN, PAGE_EXECUTE_READWRITE, &old)) {
    ui_log("cinema text: cannot unprotect %p (%lu); leaving it as it is", (void *)site, (unsigned long)GetLastError());
    return;
  }
  memcpy((void *)site, jmp, CINE_SITE_LEN);
  VirtualProtect((void *)site, CINE_SITE_LEN, old, &tmp);
  FlushInstructionCache(GetCurrentProcess(), (void *)site, CINE_SITE_LEN);
  cine_site = site;
  cine_page = (uintptr_t)page;
  cine_slots = (cine_slots_t *)(page + CINE_SLOTS);
  ui_log("cinema text: detour at +%llx -> %p (%d bytes): its height is now its font's pixel height (/ 1/scale)",
         (unsigned long long)(site - image), (void *)page, n);
}

/* Each cinema text the detour converted, for the log: its font (key, pixel height, so its
 * index), and a second later what the cinema multiplies it by. */
static void cine_watch(void)
{
  static LONG seen;
  static DWORD at;
  static int pending;
  if (!cine_slots) return;
  LONG n = cine_slots->count;
  if (n != seen) {
    seen = n;
    pending = 1;
    at = GetTickCount();
    ui_log("cinema text #%ld: font key %016llx, %.3f UI units -> %.1f px (1/scale %.6f)", (long)n,
           (unsigned long long)cine_slots->key, cine_slots->units, cine_slots->px, rdf(ctx + FC_INV_SCALE));
  } else if (pending && GetTickCount() - at > 1000) {
    pending = 0;
    uintptr_t o = (uintptr_t)cine_slots->obj;
    /* +0x2e8: the cinema screen's +0x4c and +0x48, the DPI factor x/y, the cinema scale (+0x50) */
    float f[5], px = cine_slots->px, h = 0;
    if (rd(o + CINE_SCREEN, f, sizeof f) && rd(o + CINE_HEIGHT, &h, 4) && h == px)
      ui_log("cinema text #%ld: screen %.4g x %.4g, DPI factor %.4g/%.4g, cinema scale %.4g: line height %.1f",
             (long)n, f[0], f[1], f[2], f[3], f[4], px * f[4] * f[3]);
  }
}

static DWORD WINAPI worker(LPVOID arg)
{
  (void)arg;
  WCHAR exe[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH);
  if (n < 11 || lstrcmpiW(exe + n - 11, L"\\Gw2-64.exe")) {
    ui_log("not Gw2-64.exe; doing nothing");
    return 0;
  }
  ui_log("gw2-on-mac ui-scale, loaded as version.dll");
  read_config();
  if (!cfg.enabled) ui_log("disabled in the ini: observing only, nothing is written");
  if (!locate()) { ui_log("writing nothing this session"); return 0; }
  if (cfg.enabled && cfg.cinema) cine_install();
  else ui_log("cinema text: left as it is (%s)", cfg.enabled ? "cinema=0" : "enabled=0");

  enum { WAITING, APPLIED, STOPPED } state = WAITING;
  uint64_t stopped_sig = 0;
  int tries = 0, last_size = 99, active_logged = 0, hint_logged = 0;
  float last_inv = -1;
  uint64_t last_cache = 0;
  uint32_t last_family = 0xffffffffu;
  DWORD applied_at = 0;
  for (;; Sleep(state == WAITING ? POLL_MS : IDLE_MS)) {
    if (!rd32(ctx + FC_LOADED)) {
      if (state == APPLIED) ui_log("font table unloaded; waiting for it to load again");
      if (state != WAITING) tries = 0;
      state = WAITING;
      continue;
    }
    table_t t;
    char why[160];
    int shape = read_table(&t, 0, why, sizeof why);
    uint64_t sig = shape ? table_sig(&t) : 0;

    if (state == APPLIED && (sig != applied_sig || !still_applied())) {
      if (sig != applied_sig) ui_log("font table reloaded; checking again");
      state = WAITING;
      tries = 0;
    }
    if (state == STOPPED && sig && sig != stopped_sig) {
      ui_log("font table reloaded; checking again");
      state = WAITING;
      tries = 0;
    }
    if (state == WAITING) {
      int r = try_apply(tries == 0);
      if (r == APPLY_OK) {
        state = APPLIED;
        applied_at = GetTickCount();
        active_logged = hint_logged = 0;
      } else if (r == APPLY_FAIL || ++tries > RETRIES) {
        if (r == APPLY_RETRY) ui_log("check failed: the scale never matched the table; writing nothing");
        state = STOPPED;
        stopped_sig = sig;
      }
    }

    /* the game's view, for the log */
    int32_t size = (int32_t)rd32(ctx + FC_SIZE);
    float inv = rdf(ctx + FC_INV_SCALE);
    if (size != last_size || inv != last_inv) {
      float w = rdf(ui_w), h = rdf(ui_h);
      ui_log("Interface Size %d: scale %.4f, UI %.0fx%.0f", size + 1, inv > 0 ? 1 / inv : 0, w, h);
      log_cache();
      last_size = size;
      last_inv = inv;
      if (state == APPLIED && size == LARGER && fabs(1.0 / inv - new_scale) < 1e-3 && !active_logged) {
        ui_log("active: Larger at scale %.4f (was %.4f), UI %.0fx%.0f", new_scale, old_scale, w, h);
        if (w < 1024 || h < 768) ui_log("warning: UI %.0fx%.0f is below 1024x768; lower scale= in the ini", w, h);
        active_logged = 1;
      }
    }
    cine_watch();
    /* every later change of the built fonts, and of the family (language) */
    uint64_t csig = cache_sig();
    uint32_t family = rd32(ctx + FC_FAMILY);
    if (csig != last_cache || family != last_family) {
      if (family != last_family) ui_log("font family %u", family);
      if (last_cache) log_cache();
      last_cache = csig;
      last_family = family;
    }
    if (state == APPLIED && size == LARGER && !active_logged && !hint_logged &&
        GetTickCount() - applied_at > 3000 && fabs(1.0 / inv - old_scale) < 1e-3) {
      ui_log("Larger still shows scale %.4f: select another Interface Size, then Larger", old_scale);
      hint_logged = 1;
    }
  }
}

void ui_scale_start(HINSTANCE self)
{
  InitializeCriticalSection(&log_lock);
  DWORD n = GetModuleFileNameA(self, dir, MAX_PATH);
  while (n && dir[n - 1] != '\\') n--;
  dir[n] = 0;
  HANDLE h = CreateThread(NULL, 0, worker, NULL, 0, NULL);
  if (h) CloseHandle(h);
}
