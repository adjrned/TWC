// The widescreen UI's portrait HP / mana text (WFE's WFEHPTextFrame /
// WFEMPTextFrame), against a fake game image: two text frames are made under
// the game UI, centred on its centre at WFE's 16:9 spots, in the game's font
// at FontHeights / PortraitStats x 0.8; after each portrait update the game's
// own lines are copied in (text and colour) and emptied; shown only with a
// unit and the game UI in mode 0 / 2 / 4; off gives the lines their text back.
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img;
static void Stub(DWORD rva, const void *fn) {
    img[rva - 1] = 0xCC;
    img[rva] = 0xE9;
    *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5));
}
static DWORD StubAt(DWORD rva, const void *fn) { Stub(rva, fn); return (DWORD)(img + rva); }

static int texts, fonts;
static float fontH[8];
static struct { BYTE *lay; DWORD pt, rel, relPt; float x, y; } pts[16];
static int nPts;
static DWORD flags[4][2];
static void *__fastcall FakeTextCtor(BYTE *mem, int, void *parent, DWORD layer, DWORD id) {
    *(DWORD *)mem = (DWORD)(img + RVA_TEXT_VTABLE);
    *(DWORD *)(mem + TEXT_LAYOUT) = (DWORD)(img + RVA_TEXT_LAYOUT_VTABLE);
    *(DWORD **)(mem + TEXT_FLAGS) = flags[texts++ & 3];
    return parent && layer == 0 ? mem : nullptr;
}
static void __fastcall FakeSetText(BYTE *t, int, const char *s) { strcpy_s((char *)t + 0x100, 64, s); }
static int __fastcall FakeSetFont(BYTE *, int, const char *, float h, DWORD) { if (fonts < 8) fontH[fonts] = h; fonts++; return 1; }
static void __fastcall FakeNop(void *, int) {}
static void __fastcall FakeRefresh(BYTE *, int, int) {}
static void __fastcall FakeSetPoint(BYTE *lay, int, DWORD pt, DWORD rel, DWORD rp, float x, float y, int) { if (nPts < 16) pts[nPts++] = { lay, pt, rel, rp, x, y }; }
static const char *__fastcall FakeSkin(const char *, int) { return "Fonts\\Test.ttf"; }
static void __fastcall FakeHide(BYTE *t, int) { t[0x1e0] = 0; }
static void __fastcall FakeShow(BYTE *t, int) { t[0x1e0] = 1; }
static float __fastcall FakeFontHeight(const char *sec, const char *key, float) { return !strcmp(sec, "FontHeights") && !strcmp(key, "PortraitStats") ? 0.01f : -1; }
// the game's font string: its buffer at +0x9c
static char bufs[2][64];
static void __fastcall FakeFsSet(BYTE *fs, int, const char *s) { strcpy_s(*(char **)(fs + FS_TEXT), 64, s); }
static void *__stdcall FakeAlloc(DWORD size, const char *, DWORD, DWORD) { return calloc(1, size); }
static BOOL __stdcall FakeFree(void *p, const char *, DWORD, DWORD) { free(p); return TRUE; }
static BYTE *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static const char *Shown(BYTE *t) { return (const char *)t + 0x100; }

int main() {
    strcpy_s(g_logPath, "ptext.log"); DeleteFileA("ptext.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_TEXT_CTOR, FakeTextCtor); Stub(RVA_TEXT_FLAGS, FakeNop); Stub(RVA_TEXT_SET, FakeSetText);
    Stub(RVA_SET_FONT, FakeSetFont); Stub(RVA_SET_POINT, FakeSetPoint); Stub(RVA_SET_ABS_POINT, FakeNop);
    Stub(RVA_SKIN_LOOKUP, FakeSkin); Stub(RVA_LAYOUT_REFRESH, FakeRefresh); Stub(RVA_FONT_HEIGHT, FakeFontHeight);
    Stub(RVA_FONTSTRING_SET, FakeFsSet);
    for (DWORD r : { RVA_BAR_CTOR, RVA_BAR_LEVEL, RVA_REGION_HIDE, RVA_UNIT_HP, RVA_HANDLE_LOOKUP }) Stub(r, FakeNop);
    static const char *fhName = "FontHeights"; *(const char **)(img + RVA_FONT_HEIGHTS_NAME) = fhName;
    DWORD *tv = (DWORD *)(img + RVA_TEXT_VTABLE), *lv = (DWORD *)(img + RVA_TEXT_LAYOUT_VTABLE), *cv = (DWORD *)(img + RVA_COMMAND_BUTTON_VTABLE);
    DWORD *bv = (DWORD *)(img + RVA_STATBAR_VTABLE), *uv = (DWORD *)(img + RVA_UI_VTABLE), *pv = (DWORD *)(img + RVA_PORTRAIT_VTABLE), *fv = (DWORD *)(img + RVA_FONTSTRING_VTABLE);
    DWORD nop = StubAt(0x200010, FakeNop);
    for (DWORD *v : { tv, lv, cv, bv, uv, pv, fv })
        for (int i = 0; i < 64; i++) v[i] = nop;
    tv[TEXT_HIDE / 4] = StubAt(0x200020, FakeHide); tv[TEXT_SHOW / 4] = StubAt(0x200030, FakeShow);
    DWORD old;
    for (BYTE *page : { img + 0xa7b000, img + 0xa7d000, img + 0xaad000, img + 0xab0000, img + 0xaaa000 }) VirtualProtect(page, 0x1000, PAGE_READWRITE, &old);
    g_smemAlloc = FakeAlloc; g_smemFree = FakeFree;
    static BYTE ui[0x500], portrait[0x300], unit[0x10], fs[2][0x100];
    *(DWORD *)ui = (DWORD)uv; fakeUi = ui; g_getUi = FakeGetUi; g_uiVtable = (DWORD)uv;
    *(DWORD *)portrait = (DWORD)pv; *(BYTE **)(ui + UI_PORTRAIT) = portrait;
    for (int i = 0; i < 2; i++) *(DWORD *)fs[i] = (DWORD)fv, *(char **)(fs[i] + FS_TEXT) = bufs[i];
    *(BYTE **)(portrait + PORTRAIT_HP) = fs[0]; *(BYTE **)(portrait + PORTRAIT_MP) = fs[1];
    *(BYTE **)(portrait + PORTRAIT_UNIT) = unit;
    strcpy_s(bufs[0], "250 / 500"); strcpy_s(bufs[1], "30 / 120");
    BYTE c[4] = { 0xff, 0x00, 0xff, 0x80 };     // as +0x141e40 stores ARGB FF80FF00: A, B, G, R
    memcpy(fs[0] + FS_COLOUR, c, 4);

    UlPortraitText(ui, ui + FRAME_LAYOUT);
    CHECK(g_ptOn && g_pt[0] && g_pt[1] && texts == 2, "on: two text frames made under the game UI");
    CHECK(fonts >= 2 && fabsf(fontH[fonts - 1] - 0.008f) < 1e-6f, "the font: FontHeights / PortraitStats (0.01) x 0.8 = %.4f", fontH[fonts - 1]);
    bool placed = nPts == 2;
    for (int i = 0; i < nPts; i++)
        placed &= pts[i].lay == g_pt[i] + TEXT_LAYOUT && pts[i].pt == 4 && pts[i].relPt == 4 && pts[i].rel == (DWORD)(ui + FRAME_LAYOUT) && pts[i].x == -0.11f && pts[i].y == PT_Y[i];
    CHECK(placed && PT_Y[0] == -0.278f && PT_Y[1] == -0.2915f, "centred on the game UI's centre at -0.11, -0.278 / -0.2915");
    CHECK(!strcmp(Shown(g_pt[0]), "250 / 500") && !strcmp(Shown(g_pt[1]), "30 / 120") && !bufs[0][0] && !bufs[1][0],
          "the game's lines copied in (\"%s\", \"%s\") and emptied", Shown(g_pt[0]), Shown(g_pt[1]));
    CHECK(*(DWORD *)(g_pt[0] + TEXT_COLOURS) == 0xFF80FF00, "the HP line's colour copied: %08lX", *(DWORD *)(g_pt[0] + TEXT_COLOURS));
    CHECK(g_pt[0][0x1e0] == 1 && g_pt[1][0x1e0] == 1 && *(DWORD *)(g_pt[0] + 0x200) == 0xe6000000 && *(float *)(g_pt[0] + 0x210) == 0.0012f, "shown, with WFE's shadow");
    // the game doesn't write a line that didn't change: ours keep the text
    PortraitTextUpdate(portrait);
    CHECK(!strcmp(Shown(g_pt[0]), "250 / 500"), "an update with the line empty: ours keep \"%s\"", Shown(g_pt[0]));
    strcpy_s(bufs[0], "260 / 500"); PortraitTextUpdate(portrait);
    CHECK(!strcmp(Shown(g_pt[0]), "260 / 500") && !bufs[0][0], "a new value: copied and emptied");
    *(DWORD *)(ui + UI_STATE180) = 1; PortraitTextUpdate(portrait);
    CHECK(g_pt[0][0x1e0] == 0 && g_pt[1][0x1e0] == 0, "the game UI in mode 1: hidden");
    *(DWORD *)(ui + UI_STATE180) = 2; *(BYTE **)(portrait + PORTRAIT_UNIT) = nullptr; PortraitTextUpdate(portrait);
    CHECK(g_pt[0][0x1e0] == 0, "no unit: hidden");
    *(BYTE **)(portrait + PORTRAIT_UNIT) = unit; PortraitTextUpdate(portrait);
    CHECK(g_pt[0][0x1e0] == 1, "mode 2 with a unit: shown");
    // the console's art hidden (Hide the UI): WFE's x 1.3635
    g_uiHidden = 0x20; int f0 = fonts; UlPortraitText(ui, ui + FRAME_LAYOUT);
    CHECK(fonts == f0 + 2 && fabsf(fontH[(fonts - 1) & 7] - 0.013635f) < 1e-6f, "Hide the UI: the font x 1.3635 (%.5f)", fontH[(fonts - 1) & 7]);
    f0 = fonts; UlPortraitText(ui, ui + FRAME_LAYOUT);
    CHECK(fonts == f0 && texts == 2, "laid out again: no new frames, the font not set again");
    PortraitTextOff();
    CHECK(!g_ptOn && !strcmp(bufs[0], "260 / 500") && !strcmp(bufs[1], "30 / 120") && g_pt[0][0x1e0] == 0, "off: the game's lines get their text back, ours hidden");
    // a new game: new frames
    static BYTE ui2[0x500]; memcpy(ui2, ui, sizeof(ui2)); fakeUi = ui2; strcpy_s(bufs[0], "1 / 2");
    UlPortraitText(ui2, ui2 + FRAME_LAYOUT);
    CHECK(texts == 4 && g_ptUi == ui2 && g_ptOn && !strcmp(Shown(g_pt[0]), "1 / 2"), "another game UI: its own frames");
    PortraitTextOff();
    // the update can't be wrapped: refused
    sh.prState = 3; static BYTE ui3[0x500]; memcpy(ui3, ui, sizeof(ui3)); fakeUi = ui3; UlPortraitText(ui3, ui3 + FRAME_LAYOUT);
    CHECK(g_ptBad && !g_ptOn && texts == 4, "the portrait update refused: no frames, the game's lines stay");
    Verdict();
    return g_fails;
}
