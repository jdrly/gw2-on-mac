/* Native test of ui_scale.c's checks and remap against a fake FontContext shaped like the one
 * measured on 2026-10-28: family 0 is the known table (sizes from ui_scale.c's `known`), with a
 * unique first name/range per entry so a copy can be traced; families 1, 5 and 6 are made up.
 * scripts/build-ui-scale.zsh runs it.
 *   cc -I addon/ui-scale/test/win -o t addon/ui-scale/test/test.c && ./t */
#include "../ui_scale.c"

static uint8_t fc[0x100];
static uintptr_t vtab[8];
static uint8_t fams[7][32], steps[7][3][32], ents[7][3][14][24];
static float g_w, g_h, g_px;
/* sub-font names (UTF-16, nul-terminated, an empty name is one 0) and ranges */
static const uint16_t names[] = { 'a', 'b', 0, 0, 'c', 'd', 'e', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
static const uint32_t ranges[13][2] = { { 0x20, 0x7f }, { 0x80, 0xff }, { 0x100, 0x17f } };
static const char *ini_scale, *ini_enabled, *ini_sans, *ini_keep;
static int failures, screen_w, screen_h;

int test_bad_ptr(const void *p, size_t n) { (void)n; return p == NULL; }
int test_screen(int axis) { return axis ? screen_h : screen_w; }
const char *test_ini(const char *key)
{
  if (!strcmp(key, "scale")) return ini_scale;
  if (!strcmp(key, "enabled")) return ini_enabled;
  if (!strcmp(key, "sans")) return ini_sans;
  if (!strcmp(key, "keep")) return ini_keep;
  return NULL;
}

#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void put32(void *p, uint32_t v) { memcpy(p, &v, 4); }
static void putp(void *p, uintptr_t v) { memcpy(p, &v, sizeof v); }
static uint32_t f32(int f, int s, int e, int off) { uint32_t v; memcpy(&v, ents[f][s][e] + off, 4); return v; }
/* the name offset each entry starts with: unique, so a remapped entry shows its donor */
static uint32_t name_of(int s, int e) { return 1000 + 100 * s + e; }
/* 1 when Larger font x now carries the fields of font e at step s */
static int took(int x, int e, int s)
{
  return f32(0, 2, x, 0x10) == name_of(s, e) && f32(0, 2, x, 0x14) == 2000 + name_of(s, e) &&
         f32(0, 2, x, 4) == known[e].s4[s] && f32(0, 2, x, 8) == known[e].s8[s];
}
static int untouched(int x) { return f32(0, 2, x, 0x10) == name_of(2, x) && f32(0, 2, x, 8) == known[x].s8[2]; }

static void build(int size, float inv)
{
  memset(fc, 0, sizeof fc); memset(fams, 0, sizeof fams); memset(steps, 0, sizeof steps); memset(ents, 0, sizeof ents);
  for (int f = 0; f < 7; f++) {
    if (f >= 2 && f <= 4) continue;
    int n = f == 6 ? 10 : 14;
    putp(fams[f] + 8, (uintptr_t)steps[f]);
    put32(fams[f] + 0x14, 3);
    for (int s = 0; s < 3; s++) {
      putp(steps[f][s] + 8, (uintptr_t)ents[f][s]);
      put32(steps[f][s] + 0x14, n);
      for (int e = 0; e < n; e++) {
        uint32_t w = f == 0 ? known[e].s4[s] : 23 + e + 2 * s, h = f == 0 ? known[e].s8[s] : 23 + e + 2 * s;
        put32(ents[f][s][e] + 4, w);
        put32(ents[f][s][e] + 8, h);
        put32(ents[f][s][e] + 12, 13);
        put32(ents[f][s][e] + 16, f == 0 ? name_of(s, e) : 0);
        put32(ents[f][s][e] + 20, f == 0 ? 2000 + name_of(s, e) : 0);
      }
    }
  }
  memset(vtab, 0, sizeof vtab);
  get_scale = (uintptr_t)&vtab[7];
  vtab[0] = get_scale;
  putp(fc + FC_VTABLE, (uintptr_t)vtab);
  put32(fc + FC_LOADED, 1);
  put32(fc + FC_FAMILY, 0);
  put32(fc + FC_SIZE, (uint32_t)size);
  memcpy(fc + FC_INV_SCALE, &inv, 4);
  putp(fc + FC_FAMILIES, (uintptr_t)fams);
  put32(fc + FC_NFAMILIES, 7);
  putp(fc + FC_NAMES, (uintptr_t)names);
  put32(fc + FC_NNAMES, 0);  /* the fake name offsets point nowhere: log_fonts prints no names */
  putp(fc + FC_RANGES, (uintptr_t)ranges);
  put32(fc + FC_NRANGES, 13);
  ctx = (uintptr_t)fc;
  image = 0;
  image_end = UINTPTR_MAX;
  ui_w = (uintptr_t)&g_w; ui_h = (uintptr_t)&g_h; ui_px = (uintptr_t)&g_px;
  g_w = 3141; g_h = 1767; g_px = inv;  /* 3840x2160 at Larger */
  screen_w = 3840; screen_h = 2160;
  ini_scale = ini_enabled = ini_sans = ini_keep = NULL;
}

static int run(const char *name)
{
  printf("--- %s\n", name);
  read_config();
  return try_apply(1);
}

/* ---- the cinema text detour ---- */

static int32_t rel_at(const uint8_t *c, int off) { return sig_rel32(c + off); }
/* the rel32 at c[off] (an instruction ending at `end` bytes into c) targets `want` */
static int targets(const uint8_t *c, uintptr_t va, int off, int end, uintptr_t want)
{
  return va + end + rel_at(c, off) == want;
}

/* The real Gw2-64.exe's .text, read-only, when GW2_EXE names it (scripts/build-ui-scale.zsh
 * passes the bottle's copy): the patterns must find the cinema site found by the analysis. */
static uint8_t *load_text(const char *path, size_t *len, uintptr_t *va)
{
  FILE *f = path ? fopen(path, "rb") : NULL;
  if (!f) return NULL;
  uint8_t h[0x1000];
  size_t got = fread(h, 1, sizeof h, f);
  uint32_t pe = 0;
  memcpy(&pe, h + 0x3c, 4);
  if (got < sizeof h || pe > sizeof h - 0x200 || memcmp(h + pe, "PE\0\0", 4)) { fclose(f); return NULL; }
  uint16_t nsec, optsz;
  uint64_t base;
  memcpy(&nsec, h + pe + 6, 2);
  memcpy(&optsz, h + pe + 20, 2);
  memcpy(&base, h + pe + 24 + 24, 8);
  uint8_t *out = NULL;
  for (int i = 0; i < nsec && pe + 24 + optsz + 40 * (i + 1) <= sizeof h; i++) {
    const uint8_t *s = h + pe + 24 + optsz + 40 * i;
    if (memcmp(s, ".text", 6)) continue;
    uint32_t vsize, rva, rawsize, raw;
    memcpy(&vsize, s + 8, 4); memcpy(&rva, s + 12, 4); memcpy(&rawsize, s + 16, 4); memcpy(&raw, s + 20, 4);
    *len = rawsize < vsize ? rawsize : vsize;
    out = malloc(*len);
    if (out && (fseek(f, raw, SEEK_SET) || fread(out, 1, *len, f) != *len)) { free(out); out = NULL; }
    *va = (uintptr_t)(base + rva);
  }
  fclose(f);
  return out;
}

static void test_cinema(void)
{
  printf("--- cinema text detour\n");
  const uint8_t lea[CINE_SITE_LEN] = { 0x4c, 0x8d, 0xb6, 0xfc, 0x02, 0x00, 0x00 };
  uint8_t c[CINE_SLOTS];
  memset(c, 0xcc, sizeof c);
  /* the 2026-10-27 build's addresses, a page just below the image */
  uintptr_t va = 0x13fff0000, back = 0x140a5e453, inv = 0x14268af70 + FC_INV_SCALE, s = va + CINE_SLOTS;
  int n = cine_tramp(c, va, back, inv, lea);
  CHECK(n == 84, "trampoline is %d bytes, want 84", n);
  CHECK(!memcmp(c, "\x48\x89\x1d", 3) && targets(c, va, 3, 7, s + offsetof(cine_slots_t, key)), "mov [key], rbx");
  CHECK(!memcmp(c + 7, "\x48\x89\x35", 3) && targets(c, va, 10, 14, s + offsetof(cine_slots_t, obj)), "mov [obj], rsi");
  CHECK(!memcmp(c + 14, "\xf3\x0f\x10\x86\xd8\x02\x00\x00", 8), "movss xmm0,[rsi+0x2d8]");
  CHECK(targets(c, va, 26, 30, s + offsetof(cine_slots_t, units)), "movss [units], xmm0");
  CHECK(!memcmp(c + 30, "\xf3\x0f\x10\x0d", 4) && targets(c, va, 34, 38, inv), "movss xmm1,[1/scale]");
  CHECK(!memcmp(c + 38, "\x0f\x57\xd2\x0f\x2f\xca\x76", 7) && 38 + 8 + c[45] == 72, "the guard must skip to the displaced lea");
  CHECK(!memcmp(c + 46, "\xf3\x0f\x5e\xc1\xf3\x0f\x11\x86\xd8\x02\x00\x00", 12), "divss; store +0x2d8");
  CHECK(targets(c, va, 62, 66, s + offsetof(cine_slots_t, px)) && !memcmp(c + 66, "\xff\x05", 2) &&
        targets(c, va, 68, 72, s + offsetof(cine_slots_t, count)), "px and count slots");
  CHECK(!memcmp(c + 72, lea, CINE_SITE_LEN) && c[79] == 0xe9 && targets(c, va, 80, 84, back), "lea r14,[rsi+0x2fc]; jmp back");
  CHECK(n <= CINE_SLOTS && c[n] == 0xcc, "wrote past its length");
  CHECK(CINE_SLOTS % 0x1000 == 0, "the slots share the read-execute code page (crashed 2026-11-04)");
  printf("trampoline:");
  for (int i = 0; i < n; i++) printf(" %02x", c[i]);
  printf("\n");
  CHECK(cine_tramp(c, 0x40000000000ull, back, inv, lea) == 0, "an unreachable page must be refused");

  /* the site's checks, on a made-up .text: the getter call, the pattern, the use after it */
  static uint8_t t[0x400];
  uint8_t pb[256], pm[256], ub[64], um[64];
  int pn = sig_parse(SIG_CINE_TEXT_FONT, pb, pm, 256), un = sig_parse(SIG_CINE_TEXT_USE, ub, um, 64);
  uintptr_t tva = 0x140001000, getter = tva + 0x300;
  memset(t, 0x90, sizeof t);
  memcpy(t + 0x40, pb, pn);
  put32(t + 0x41, (uint32_t)(getter - (tva + 0x45)));
  memcpy(t + 0x40 + CINE_SITE + 0x150, ub, un);
  char why[160];
  CHECK(cine_find(t, sizeof t, tva, getter, why, sizeof why) == tva + 0x40 + CINE_SITE, "made-up site not found");
  CHECK(!cine_find(t, sizeof t, tva, getter + 16, why, sizeof why), "a call to another function must be refused");
  t[0x40 + CINE_SITE + 0x150] = 0x90;
  CHECK(!cine_find(t, sizeof t, tva, getter, why, sizeof why), "a site without the height's use must be refused");

  /* the game's own .text, when there */
  size_t len = 0;
  uintptr_t xva = 0;
  uint8_t *x = load_text(getenv("GW2_EXE"), &len, &xva);
  if (!x) { printf("(GW2_EXE not set or unreadable: the real .text is not checked)\n"); return; }
  int cnt;
  ptrdiff_t w = sig_scan(x, len, SIG_FONT_SET_SIZE, &cnt);
  CHECK(w >= 0, "FontSetSize matched %d times", cnt);
  if (w >= 0) {
    uintptr_t g = xva + w + 13 + sig_rel32(x + w + 9);
    uintptr_t site = cine_find(x, len, xva, g, why, sizeof why);
    printf("real .text: getter %#lx, cinema site %#lx%s%s\n", (unsigned long)g, (unsigned long)site, site ? "" : ": ", site ? "" : why);
    CHECK(site, "cinema site not found in the real .text: %s", why);
    if (xva == 0x140001000) CHECK(g == 0x140a64c20 && site == 0x140a5e44c, "not the analysed addresses (build 6ad7acf4)");
    if (site) CHECK(!memcmp(x + (site - xva), lea, CINE_SITE_LEN), "the site is not lea r14,[rsi+0x2fc]");
  }
  free(x);
}

int main(void)
{
  const float larger = 18.0f / 22.0f;

  build(2, larger);
  CHECK(run("default: scale 1.75, sans=cronos") == APPLY_OK, "not applied");
  CHECK(fabs(new_scale - 30.0 / 18) < 1e-9, "new scale %f, want 30/18", new_scale);
  CHECK(took(0, 2, 0), "font 0 should take font 2 step 0 (33/30, the strike nearest 31.5, ties down)");
  CHECK(took(1, 11, 1) && took(3, 11, 1), "UI sans cap 13 -> Cronos cap 18 (font 11 step 1)");
  CHECK(took(6, 11, 0), "UI sans cap 12 -> Cronos cap 16 (font 11 step 0)");
  CHECK(took(4, 12, 1), "UI sans italic cap 13 -> Cronos italic cap 18 (font 12 step 1)");
  CHECK(took(5, 11, 1), "Cronos cap 13 -> cap 18");
  CHECK(took(2, 7, 2) && took(9, 7, 2), "Cronos cap 24 -> the largest, cap 29 (font 7 step 2)");
  CHECK(untouched(7) && untouched(8), "cap 29 has no larger strike: kept");
  CHECK(took(11, 7, 1) && took(12, 8, 1) && took(10, 8, 2) && took(13, 8, 2), "cap 20/20/24/23 donors");
  CHECK(npatches == 12 * (int)NFIELDS, "%d patches", npatches);
  for (int s = 0; s < 2; s++)
    for (int e = 0; e < 14; e++) CHECK(f32(0, s, e, 0x10) == name_of(s, e), "step %d font %d changed", s, e);
  CHECK(f32(1, 2, 0, 8) == 23 + 4, "another family changed");
  CHECK(still_applied(), "not seen as applied");
  put32(ents[0][2][3] + 8, 18);  /* the game reloads one value in place */
  CHECK(!still_applied(), "a reverted value went unnoticed");

  build(2, larger); ini_sans = "keep";
  CHECK(run("sans=keep") == APPLY_OK && untouched(1) && untouched(3) && untouched(4) && untouched(6) && took(5, 11, 1),
        "sans=keep remapped the UI sans or skipped Cronos");

  build(2, larger); ini_keep = "6, 3,x,0,40";  /* 0 (sets the scale) and 40 are not keepable */
  CHECK(run("keep=6,3") == APPLY_OK && untouched(6) && untouched(3) && took(1, 11, 1) && took(0, 2, 0),
        "keep= did not keep fonts 6 and 3 only");

  build(2, larger); ini_scale = "2";
  CHECK(run("scale 2.0") == APPLY_OK && took(0, 7, 0) && fabs(new_scale - 37.0 / 18) < 1e-9,
        "scale 2 should give font 7 step 0 (37), got %f", new_scale);

  build(2, larger); g_w = 1571; g_h = 883;  /* 1920x1080: the floor allows 1.405 */
  CHECK(run("1080p: the 1024x768 floor") == APPLY_OK && took(0, 11, 0) && fabs(new_scale - 24.0 / 18) < 1e-9,
        "1080p should give font 11 step 0 (24), got %f", new_scale);

  build(2, 1.0f); g_w = 1024; g_h = 768; screen_w = 1024; screen_h = 768;  /* nothing above Larger fits */
  CHECK(run("1024x768: no strike fits") == APPLY_FAIL && untouched(0), "wrote");

  build(2, 1.0f); g_w = 1024; g_h = 768;  /* every start so far: fonts loaded, not laid out yet */
  CHECK(run("before the first layout: the screen's floor") == APPLY_OK && took(0, 2, 0), "not applied");

  build(2, 18.0f / 20.0f);  /* size already Larger, scale still Large's */
  CHECK(run("game mid-update") == APPLY_RETRY && untouched(0), "wrote");

  build(0, 1.0f);
  CHECK(run("Normal selected, laid out") == APPLY_OK && took(0, 2, 0), "not applied");

  build(0, 1.0f); g_w = 1024; g_h = 768;  /* 15:23: a start at Normal, before the first layout */
  CHECK(run("start at Normal, not laid out: the screen's floor") == APPLY_OK && took(0, 2, 0) &&
        fabs(new_scale - 30.0 / 18) < 1e-9, "not applied");

  build(1, 1.0f); g_w = 1024; g_h = 768;  /* a start at Large, before the first layout */
  CHECK(run("start at Large, not laid out") == APPLY_OK && took(0, 2, 0), "not applied");

  build(-1, 1.0f); g_w = 1024; g_h = 768;  /* a start at Small, before the first layout */
  CHECK(run("start at Small, not laid out") == APPLY_OK && took(0, 2, 0), "not applied");

  build(-1, 1.0f / 0.9f);
  CHECK(run("Small selected") == APPLY_OK && took(0, 2, 0), "not applied");

  build(2, larger); put32(ents[0][1][4] + 4, 19);
  CHECK(run("the font table differs (game update)") == APPLY_FAIL && untouched(0), "wrote");

  build(2, 18.0f / 27.0f); put32(fc + FC_FAMILY, 1);  /* its fake font 0 at Larger: 27/18 */
  CHECK(run("another language's family") == APPLY_FAIL && untouched(0), "wrote");

  build(1, 18.0f / 20.0f); put32(fc + FC_FAMILY, 3);  /* no steps: GetScale falls back to family 0 */
  CHECK(run("family without steps, Large") == APPLY_OK && took(0, 2, 0), "not applied");

  build(2, larger); ini_enabled = "0";
  CHECK(run("enabled=0: observe, write nothing") == APPLY_OK && untouched(0) && npatches == 0, "wrote");

  build(2, larger); vtab[0] = 0;
  CHECK(run("wrong vtable") == APPLY_FAIL && untouched(0), "wrote");

  build(2, larger); put32(fams[3] + 0x14, 2); putp(fams[3] + 8, (uintptr_t)steps[0]);
  CHECK(run("a family with 2 steps") == APPLY_FAIL && untouched(0), "wrote");

  build(2, larger); put32(ents[5][1][7] + 8, 300);
  CHECK(run("a height above 255") == APPLY_FAIL && untouched(0), "wrote");

  build(2, larger); putp(steps[1][2] + 8, 0);
  CHECK(run("a missing font array") == APPLY_FAIL && untouched(0), "wrote");

  build(2, larger); ini_scale = "abc";
  CHECK(run("bad scale value: default") == APPLY_OK && took(0, 2, 0), "not applied");

  build(2, larger);
  table_t t1, t2; char why[160];
  read_table(&t1, 1, why, sizeof why);
  static uint8_t moved[14][24];
  memcpy(moved, ents[1][2], sizeof moved);
  putp(steps[1][2] + 8, (uintptr_t)moved);
  read_table(&t2, 1, why, sizeof why);
  CHECK(table_sig(&t1) != table_sig(&t2), "a reload went unnoticed");

  test_cinema();

  printf("%s (%d failure%s)\n", failures ? "FAILED" : "ok", failures, failures == 1 ? "" : "s");
  return failures != 0;
}
