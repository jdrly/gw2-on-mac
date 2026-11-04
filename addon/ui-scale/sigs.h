/* Code patterns that locate GW2's interface scale, shared by the probe and the addon.
 * Each one is unique in Gw2-64.exe's .text (build of 2026-10-27); "??" bytes are rel32
 * displacements or struct offsets that move between builds. The research is in
 * docs/research/ui-scale-2026-10-28.md. */
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* FontContext's SetSize wrapper: calls the FontContext getter (lea rax,[rip+ctx]; ret),
 * then jumps to vtable slot 0x28, which stores Interface Size - 1 at ctx+0x10. */
#define SIG_FONT_SET_SIZE \
  "40 53 48 83 EC 20 8B D9 E8 ?? ?? ?? ?? 48 8B C8 48 8B 10 4C 8B 42 28 8B D3 48 83 C4 20 5B 49 FF E0"
/* FontContext::GetScale, vtable slot 0: 1 + 0.1*size below 0, else a ratio of font heights. */
#define SIG_FONT_GET_SCALE \
  "40 53 48 83 EC 40 83 79 10 F6 48 8B D9 7F ?? 41 B8 ?? ?? ?? ?? 48 8D 15 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ?? " \
  "E8 ?? ?? ?? ?? 8B 43 10 85 C0 79 ?? 66 0F 6E C0 0F 5B C0 F3 0F 59 05"
/* The UI layout scale: after FontGetScale(), stores the UI height (+0x24), the UI units per
 * pixel (+0x2c) and reads the UI width (+0x34), each a movss [rip+disp32]. */
#define SIG_UI_LAYOUT \
  "E8 ?? ?? ?? ?? F3 0F 10 35 ?? ?? ?? ?? F3 0F 10 15 ?? ?? ?? ?? F3 0F 5E F0 0F 28 C6 F3 0F 59 D6 " \
  "F3 0F 5E C7 F3 0F 11 15 ?? ?? ?? ?? F3 0F 11 05 ?? ?? ?? ?? F3 0F 10 05"
#define UI_LAYOUT_HEIGHT_INSN 0x24
#define UI_LAYOUT_PIXEL_INSN  0x2c
#define UI_LAYOUT_WIDTH_INSN  0x34

/* Cinema text (Arena\Engine\Cinema\Content, 0x140a5e390 in the 2026-10-27 build: the subtitles
 * of story cinematics). It calls GetFont itself (FontContext getter, vtable slot 0x30) with the
 * text's font key and stores the font's height in UI units (pixel height * 1/scale) at +0x2d8;
 * the glyph height (+0x5cd) and the line pitch (0x140a5f039) are that times the cinema's own
 * scale (+0x2f8) and the DPI factor (+0x2f4), with no UI scale. The detour goes on the
 * `lea r14,[rsi+0x2fc]` right after the GetFont call (+0x28), which only runs after GetFont
 * wrote +0x2d8; the jump back is to the instruction after it. */
#define SIG_CINE_TEXT_FONT \
  "E8 ?? ?? ?? ?? 4C 8D 8E D8 02 00 00 48 C7 44 24 20 00 00 00 00 4D 8B C7 48 8B D3 48 8B 08 4C 8B 51 30 " \
  "48 8B C8 41 FF D2 4C 8D B6 FC 02 00 00 49 83 3F 00 48 89 9E D0 02 00 00"
#define CINE_SITE      0x28  /* lea r14,[rsi+0x2fc]: 7 bytes */
#define CINE_SITE_LEN  7
/* the glyph height's use, within CINE_USE_RANGE bytes after the site: movss xmm7,[rsi+0x2d8];
 * mov ecx,2; mulss xmm7,[rsi+0x2f8] */
#define SIG_CINE_TEXT_USE "F3 0F 10 BE D8 02 00 00 B9 02 00 00 00 F3 0F 59 BE F8 02 00 00"
#define CINE_USE_RANGE 0x200
#define CINE_HEIGHT    0x2d8 /* cinema text: font height in UI units (GetFont's out) */
#define CINE_SCREEN    0x2e8 /* then the cinema screen's +0x4c, +0x48, the DPI factor x/y, the cinema scale (+0x50) */

/* FontContext layout (FontContext.cpp, read from GetScale, GetFont and the AFNT loader). */
#define FC_VTABLE     0x00
#define FC_LOADED     0x08  /* 1 once the AFNT font table is loaded */
#define FC_FAMILY     0x0c  /* font family (language) */
#define FC_SIZE       0x10  /* Interface Size - 1: Small -1, Normal 0, Large 1, Larger 2 */
#define FC_INV_SCALE  0x14  /* 1 / GetScale(), multiplies font pixel heights into UI units */
#define FC_FAMILIES   0x60  /* family array (32-byte records) */
#define FC_NFAMILIES  0x6c
#define FC_CACHE      0x80  /* font cache by font index (16-byte entries: font object, ?, pixel height at +0x0c) */
#define FC_NCACHE     0x8c
#define FC_CACHE_SIZE 16
#define FC_CACHE_HEIGHT 0x0c
#define FC_NAMES      0x20  /* sub-font names: one UTF-16 array, each name nul-terminated (count in chars at +0x2c) */
#define FC_NNAMES     0x2c
#define FC_RANGES     0x40  /* sub-font character ranges: 8-byte records, first char at +0, last at +4 (count +0x4c) */
#define FC_NRANGES    0x4c
#define FC_ENTRY_SUBFONTS 0x0c  /* a font entry's sub-font count (13), its first name at +0x10, first range at +0x14 */
#define FC_ENTRY_NAME     0x10
#define FC_ENTRY_RANGE    0x14
/* family and size-step records: array pointer at +0x08, count at +0x14 */
#define FC_REC_PTR    0x08
#define FC_REC_COUNT  0x14
#define FC_REC_SIZE   32
/* font entries: 24 bytes, pixel height at +0x08 (the "height" of FontContext.cpp's asserts) */
#define FC_ENTRY_SIZE   24
#define FC_ENTRY_HEIGHT 0x08

static int sig_parse(const char *p, uint8_t *bytes, uint8_t *mask, int max)
{
  int n = 0;
  while (*p && n < max) {
    while (*p == ' ') p++;
    if (!*p) break;
    if (p[0] == '?') { bytes[n] = 0; mask[n] = 0; p += 2; }
    else {
      unsigned v = 0;
      for (int i = 0; i < 2; i++, p++)
        v = v * 16 + (*p <= '9' ? *p - '0' : (*p | 0x20) - 'a' + 10);
      bytes[n] = (uint8_t)v; mask[n] = 1;
    }
    n++;
  }
  return n;
}

/* The pattern's offset in buf when it matches exactly once, else -1 (*count says how often). */
static ptrdiff_t sig_scan(const uint8_t *buf, size_t len, const char *pattern, int *count)
{
  uint8_t b[256], m[256];
  int n = sig_parse(pattern, b, m, 256);
  ptrdiff_t hit = -1;
  *count = 0;
  for (size_t i = 0; i + n <= len; i++) {
    if (buf[i] != b[0]) continue;
    int j = 1;
    while (j < n && (!m[j] || buf[i + j] == b[j])) j++;
    if (j == n) { if (++*count == 1) hit = (ptrdiff_t)i; }
  }
  return *count == 1 ? hit : -1;
}

static int32_t sig_rel32(const uint8_t *p) { int32_t v; memcpy(&v, p, 4); return v; }

/* 1 when the pattern occurs anywhere in buf[0, len) (not only once) */
static __attribute__((unused)) int sig_within(const uint8_t *buf, size_t len, const char *pattern)
{
  uint8_t b[256], m[256];
  int n = sig_parse(pattern, b, m, 256);
  for (size_t i = 0; i + n <= len; i++) {
    int j = 0;
    while (j < n && (!m[j] || buf[i + j] == b[j])) j++;
    if (j == n) return 1;
  }
  return 0;
}
