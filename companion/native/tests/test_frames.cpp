// Frames added to the game, against a fake game image: the game functions are
// C++ fakes behind jumps at their 1.28f offsets, so every call goes through
// GameCall with the conventions the module assumes (__fastcall, stack
// arguments cleaned by the callee). Covers the timers drawn in the game,
// health numbers and mana bars: made, placed, shown and hidden with the
// health bar, destroyed with it, and everything put back when turned off.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, itOn) == 688 && offsetof(Shared, mbCount) == 728 && sizeof(Shared) == 732, "layout 11");

static BYTE *img;
static void Stub(DWORD rva, const void *fn) {
    img[rva - 1] = 0xCC;
    img[rva] = 0xE9;
    *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5));
}
static DWORD StubAt(DWORD rva, const void *fn) { Stub(rva, fn); return (DWORD)(img + rva); }

// -- fakes -------------------------------------------------------------------
struct Text { BYTE raw[0x240]; };
static int texts, shows, hides, setTexts, anchors, absPoints, fonts, flagCalls;
static char lastText[64], lastFont[MAX_PATH];
static float lastX, lastY, lastFontH;
static void *lastRel;
static DWORD flagsStruct[64][2];
static void *__fastcall FakeTextCtor(BYTE *mem, int, void *parent, DWORD layer, DWORD id) {
    *(DWORD *)mem = (DWORD)(img + RVA_TEXT_VTABLE);
    *(DWORD *)(mem + TEXT_LAYOUT) = (DWORD)(img + RVA_TEXT_LAYOUT_VTABLE);
    *(DWORD **)(mem + TEXT_FLAGS) = flagsStruct[texts % 64];
    texts++;
    return parent && id == TEXT_ID ? mem : nullptr;
}
static void __fastcall FakeFlags(BYTE *, int, DWORD) { flagCalls++; }
static void __fastcall FakeSetText(BYTE *t, int, const char *s) { setTexts++; strcpy_s(lastText, s); strcpy_s((char *)t + 0x100, 32, s); }
static int __fastcall FakeSetFont(BYTE *, int, const char *path, float h, DWORD) { fonts++; strcpy_s(lastFont, path); lastFontH = h; return 1; }
static void __fastcall FakeRefresh(BYTE *, int, int) {}
static void __fastcall FakeSetPoint(BYTE *, int, int, void *rel, int, float x, float y, int) { anchors++; lastRel = rel; lastX = x; lastY = y; }
static void __fastcall FakeSetAbs(BYTE *lay, int, int, float x, float y, int) { absPoints++; lastX = x; lastY = y; *(float *)(lay + 0x10) = y; }
static const char *__fastcall FakeSkin(const char *key, int) { return !strcmp(key, "MasterFont") ? "Fonts\\Test.ttf" : nullptr; }
static void __fastcall FakeTextHide(BYTE *t, int) { hides++; t[0x1e0] = 0; }
static void __fastcall FakeTextShow(BYTE *t, int) { shows++; t[0x1e0] = 1; }
static void __fastcall FakeNop(void *, int) {}

static int barCtors, barDtors, barUpdates, ratios, frees;
static float lastRatio;
static void *__fastcall FakeBarCtor(BYTE *mem, int, int, DWORD unit, DWORD kind) {
    barCtors++;
    *(DWORD *)mem = (DWORD)(img + RVA_STATBAR_VTABLE);
    *(DWORD *)(mem + BAR_KIND) = kind;
    *(DWORD *)(mem + BAR_UNIT) = unit;
    return mem;
}
static void __fastcall FakeBarLevel(BYTE *, int, DWORD) {}
static void *__fastcall FakeBarDtor(BYTE *b, int, int) { barDtors++; return b; }
static void __fastcall FakeBarHide(BYTE *b, int) { *(DWORD *)(b + BAR_SHOWN) = 0; }
static void __fastcall FakeBarShow(BYTE *b, int) { *(DWORD *)(b + BAR_SHOWN) = 1; }
static void __fastcall FakeBarRatio(BYTE *, int, float r) { ratios++; lastRatio = r; }
static void __fastcall FakeBarUpdate(BYTE *, int, void *) { barUpdates++; }
static void __fastcall FakeState(float *st, int, float *out) { *out = *st; }
static void *__fastcall FakeLookup(DWORD a, DWORD) { return (void *)a; }
static void *__stdcall FakeAlloc(DWORD size, const char *, DWORD, DWORD) { return calloc(1, size); }
static BOOL __stdcall FakeFree(void *p, const char *, DWORD, DWORD) { frees++; free(p); return TRUE; }

static BYTE *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }

int main() {
    strcpy_s(g_logPath, "frames.log"); DeleteFileA("frames.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_TEXT_CTOR, FakeTextCtor); Stub(RVA_TEXT_FLAGS, FakeFlags); Stub(RVA_TEXT_SET, FakeSetText);
    Stub(RVA_SET_FONT, FakeSetFont); Stub(RVA_SET_POINT, FakeSetPoint); Stub(RVA_SET_ABS_POINT, FakeSetAbs);
    Stub(RVA_SKIN_LOOKUP, FakeSkin); Stub(RVA_LAYOUT_REFRESH, FakeRefresh); Stub(RVA_BAR_CTOR, FakeBarCtor);
    Stub(RVA_BAR_LEVEL, FakeBarLevel); Stub(RVA_BAR_TEXT_REFRESH, FakeNop); Stub(RVA_UNIT_HP, FakeState);
    Stub(RVA_HANDLE_LOOKUP, FakeLookup);
    // vtables: data pages (the code they point to is in the stub area at 0x200000)
    DWORD *tv = (DWORD *)(img + RVA_TEXT_VTABLE), *lv = (DWORD *)(img + RVA_TEXT_LAYOUT_VTABLE), *cv = (DWORD *)(img + RVA_COMMAND_BUTTON_VTABLE);
    DWORD *bv = (DWORD *)(img + RVA_STATBAR_VTABLE), *fv = (DWORD *)(img + 0xab0000), *uv = (DWORD *)(img + RVA_UI_VTABLE);
    DWORD nop = StubAt(0x200010, FakeNop);
    for (DWORD *v : { tv, lv, cv, bv, fv, uv })
        for (int i = 0; i < 64; i++) v[i] = nop;
    tv[TEXT_HIDE / 4] = StubAt(0x200020, FakeTextHide); tv[TEXT_SHOW / 4] = StubAt(0x200030, FakeTextShow);
    bv[BAR_DTOR / 4] = StubAt(0x200040, FakeBarDtor); bv[BAR_HIDE / 4] = StubAt(0x200050, FakeBarHide);
    bv[BAR_SHOW / 4] = StubAt(0x200060, FakeBarShow); bv[BAR_RATIO / 4] = StubAt(0x200070, FakeBarRatio);
    DWORD gameUpdate = StubAt(0x200080, FakeBarUpdate); bv[STATBAR_UPDATE / 4] = gameUpdate;
    DWORD old;
    for (BYTE *page : { img + 0xa7b000, img + 0xaad000, img + 0xab0000, img + 0xaaa000 }) VirtualProtect(page, 0x1000, PAGE_READWRITE, &old);
    g_smemAlloc = FakeAlloc; g_smemFree = FakeFree;
    // the game UI: a command card grid (3 x 4) and a buff bar (1 x 8)
    static BYTE ui[0x400], card[0x200], cardRows[3][16], console[0x200], c130[0x200], buffBar[0x200], buffRow[16];
    static BYTE btns[12][0x200], bbtns[8][0x200]; static BYTE *cardBtns[3][4], *buffBtns[8];
    *(DWORD *)ui = (DWORD)uv; fakeUi = ui; g_getUi = FakeGetUi; g_uiVtable = (DWORD)uv;
    *(BYTE **)(ui + 0x3c8) = card; *(int *)(card + 0x124) = 3; *(int *)(card + 0x128) = 4; *(BYTE **)(card + 0x154) = &cardRows[0][0];
    for (int r = 0; r < 3; r++) {
        *(DWORD *)(cardRows[r] + 4) = 4; *(BYTE ***)(cardRows[r] + 8) = cardBtns[r];
        for (int c = 0; c < 4; c++) { cardBtns[r][c] = btns[r * 4 + c]; *(DWORD *)btns[r * 4 + c] = (DWORD)cv; }
    }
    *(DWORD *)btns[5] = (DWORD)fv;      // not a command button
    *(BYTE **)(ui + 0x3c4) = console; *(BYTE **)(console + 0x130) = c130; *(BYTE **)(c130 + 0x16c) = buffBar;
    *(int *)(buffBar + 0x124) = 1; *(int *)(buffBar + 0x128) = 8; *(BYTE **)(buffBar + 0x154) = buffRow;
    *(DWORD *)(buffRow + 4) = 8; *(BYTE ***)(buffRow + 8) = buffBtns;
    for (int i = 0; i < 8; i++) { buffBtns[i] = bbtns[i]; *(DWORD *)bbtns[i] = (DWORD)fv; }

    // -- timers drawn in the game ------------------------------------------------
    CHECK(FramesCheck() == 1, "the frame functions and vtables check out");
    g_framesUi = ui;
    sh.itOn = 1;
    sh.cdLeft[0] = 5.3f; sh.cdLeft[5] = 3; sh.cdLeft[11] = 75; sh.buffLeft[2] = 0.46f; sh.buffFlags[2] = 1;
    TimerFramesDraw(ui);
    CHECK(texts == 6 && g_tCd[0].text && g_tCd[11].text && !g_tCd[5].text && g_tBuff[2].text, "frames for the 2 command buttons and 1 buff (text + shadow each): %d", texts);
    CHECK(!strcmp(g_tCd[0].shown, "6") && !strcmp(g_tCd[11].shown, "1:15") && !strcmp(g_tBuff[2].shown, "0.5"), "texts: %s, %s, %s", g_tCd[0].shown, g_tCd[11].shown, g_tBuff[2].shown);
    CHECK(!strcmp(lastFont, "Fonts\\Test.ttf") && fonts == 6 && flagCalls == 6, "the skin's MasterFont, flags set (%s, %d fonts)", lastFont, fonts);
    CHECK(g_tCd[0].text[0x1e0] == 1 && g_tCd[0].shadow[0x1e0] == 1 && *(DWORD *)(g_tCd[0].shadow + TEXT_COLOURS) == 0xFF000000 && *(DWORD *)(g_tCd[0].text + TEXT_COLOURS) == 0xFFFFFFFF,
        "shown; white text, black shadow");
    CHECK(anchors == 6 && lastRel == bbtns[2] && fabsf(lastY - BUFF_TEXT_Y) < 1e-6f, "anchored to their buttons (the buff text under its icon)");
    int setBefore = setTexts; TimerFramesDraw(ui);
    CHECK(setTexts == setBefore && anchors == 6, "nothing changed: no text set, no anchoring again");
    sh.cdLeft[0] = 0; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 0 && g_tCd[0].shadow[0x1e0] == 0 && texts == 6, "ready: hidden, the frames kept");
    sh.cdLeft[0] = 2; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 1 && texts == 6 && !strcmp(g_tCd[0].shown, "2"), "cooling down again: the same frames shown");
    sh.itOn = 0; TimerFramesPass(ui);
    CHECK(g_tCd[11].text[0x1e0] == 0 && g_tBuff[2].text[0x1e0] == 0 && sh.itState == 0, "turned off: all hidden, state 0");
    fakeUi = nullptr; FramesPass();
    CHECK(!g_framesUi && !g_tCd[0].text && sh.frCount == 0, "the game ended: the frames are forgotten (the game frees them)");
    fakeUi = ui; FramesPass();

    // -- health numbers and mana bars ------------------------------------------
    static BYTE units[3][0x200], maxObj[3][0x100], bars[3][0x200], pos[3][16], fills[4][0x80];
    static DWORD fillVt[16]; for (int i = 0; i < 16; i++) fillVt[i] = nop;
    float hp[3] = { 250, 40, 100 }, mana[3] = { 30, 0, 75 }, maxHp = 500, maxMana[3] = { 60, 0, 100 };
    for (int i = 0; i < 3; i++) {
        BYTE *u = units[i], *b = bars[i];
        *(float *)(u + UNIT_HP) = hp[i]; *(float *)(u + UNIT_MANA) = mana[i];
        *(float *)(maxObj[i] + 0x84) = maxHp; *(float *)(maxObj[i] + 0xc0) = maxMana[i];
        ((DWORD *)(u + UNIT_MAXHP_HANDLE))[0] = (DWORD)maxObj[i]; ((DWORD *)(u + UNIT_MAXHP_HANDLE))[1] = 1;
        ((DWORD *)(u + UNIT_MAXMANA_HANDLE))[0] = (DWORD)(maxObj[i] + 0x3c); ((DWORD *)(u + UNIT_MAXMANA_HANDLE))[1] = 1;   // +0x3c+0x84 = +0xc0
        *(DWORD *)b = (DWORD)bv; *(DWORD *)(b + BAR_KIND) = 5; *(BYTE **)(b + BAR_UNIT) = u; *(DWORD *)(b + BAR_SHOWN) = 1;
        *(float *)(b + BAR_WIDTH) = 0.05f; *(float *)(b + BAR_HEIGHT) = 0.004f;
        *(BYTE **)(b + BAR_POS) = pos[i]; *(float *)(pos[i] + 4) = 0.3f + i * 0.1f; *(float *)(pos[i] + 8) = 0.4f;
        *(BYTE **)(b + BAR_FILL) = fills[i]; *(DWORD **)fills[i] = fillVt;
    }
    auto update = [&](int i) { ((BarUpdateFn)bv[STATBAR_UPDATE / 4])(bars[i], 0, units[i]); };
    sh.hnOn = 1; sh.hnMode = 1; sh.mbOn = 1; sh.mbHeight = 0.75f;
    FramesPass();                        // wants the bar update
    CHECK(g_extrasWant == 1 && !g_extrasHooked, "on: asks the worker for the bar update first");
    FollowColours(); FramesPass();
    CHECK(g_barHooked && g_extrasHooked && bv[BAR_HIDE / 4] == (DWORD)BarHideHook && bv[BAR_SHOW / 4] == (DWORD)BarShowHook && bv[BAR_DTOR / 4] == (DWORD)BarDtorHook && sh.hnState == 1 && sh.mbState == 1,
        "then the hide, show and dtor entries are wrapped too (states %lu %lu)", sh.hnState, sh.mbState);
    int t0 = texts;
    for (int i = 0; i < 3; i++) update(i);
    BarExtra *e0 = BxFind(bars[0], false), *e1 = BxFind(bars[1], false), *e2 = BxFind(bars[2], false);
    CHECK(e0 && e0->mana && e0->text && e1 && !e1->mana && e1->text && e2 && e2->mana && sh.mbCount == 2 && sh.hnCount == 3 && texts == t0 + 3,
        "3 numbers, 2 mana bars (the unit without mana has none)");
    CHECK(!strcmp((char *)e0->text + 0x100, "250 / 500") && !strcmp((char *)e1->text + 0x100, "40 / 500"), "numbers: %s, %s", (char *)e0->text + 0x100, (char *)e1->text + 0x100);
    BYTE *m0 = e0->mana;
    CHECK(*(DWORD *)(m0 + BAR_KIND) == 0 && fabsf(*(float *)(m0 + BAR_HEIGHT) - 0.003f) < 1e-6f && *(float *)(m0 + BAR_WIDTH) == 0.05f && *(int *)(m0 + BAR_CUR) == 30 && *(int *)(m0 + BAR_MAX) == 60,
        "the mana bar: kind 0, 3/4 the height, the same width, 30 of 60");
    CHECK(fabsf(*(float *)(m0 + 0x10) - (0.4f - 0.004f - MANA_GAP)) < 1e-6f && *(DWORD *)(m0 + BAR_SHOWN) == 1 && e0->textShown, "placed under the bar and shown with it");
    sh.hnMode = 2; *(float *)(units[0] + UNIT_HP) = 125; update(0);
    CHECK(!strcmp((char *)e0->text + 0x100, "25%") && lastRatio == 0.5f, "percent mode: %s; mana ratio %.2f", (char *)e0->text + 0x100, lastRatio);
    ((BarFn)bv[BAR_HIDE / 4])(bars[0], 0);
    CHECK(*(DWORD *)(bars[0] + BAR_SHOWN) == 0 && *(DWORD *)(m0 + BAR_SHOWN) == 0 && e0->text[0x1e0] == 0, "the game hides the bar: its mana bar and number too");
    *(DWORD *)(bars[0] + BAR_SHOWN) = 1; update(0);
    CHECK(*(DWORD *)(m0 + BAR_SHOWN) == 0 && e0->text[0x1e0] == 0, "hidden, its updates don't show them again (only the game's show does)");
    ((BarFn)bv[BAR_SHOW / 4])(bars[0], 0);
    CHECK(*(DWORD *)(m0 + BAR_SHOWN) == 1 && e0->text[0x1e0] == 1, "and shows them with it");
    int d0 = barDtors, f0 = frees;
    BYTE *text2 = e2->text;
    ((BarDtorFn)bv[BAR_DTOR / 4])(bars[2], 0, 1);
    CHECK(barDtors == d0 + 2 && frees == f0 + 1 && !BxFind(bars[2], false) && sh.mbCount == 1 && g_textHideN == 1, "the bar destroyed: its mana bar destroyed and freed first, its number queued");
    FramesPass();
    CHECK(text2[0x1e0] == 0 && g_textPoolN == 1 && g_textHideN == 0, "the next pass hides that number and keeps it for another bar");
    *(DWORD *)(bars[2] + BAR_SHOWN) = 1; t0 = texts; update(2);
    CHECK(texts == t0 && BxFind(bars[2], false) && BxFind(bars[2], false)->text == text2, "a new bar takes the kept number frame");
    sh.mbOn = 0; FramesPass();
    CHECK(sh.mbCount == 0 && !e0->mana && g_extrasHooked && sh.mbState == 0, "mana bars off: all destroyed, numbers stay");
    sh.hnOn = 0; FramesPass();
    CHECK(g_bxCount == 0 && sh.hnCount == 0 && !g_extrasHooked && bv[BAR_HIDE / 4] == StubAt(0x200050, FakeBarHide) && bv[BAR_DTOR / 4] == StubAt(0x200040, FakeBarDtor),
        "both off: numbers hidden, entries the game's again");
    FollowColours();
    CHECK(!g_barHooked && bv[STATBAR_UPDATE / 4] == gameUpdate, "and the worker puts the bar update back");
    CHECK(frees == barCtors, "every mana bar made was freed (%d made, %d freed)", barCtors, frees);
    Verdict();
    return g_fails;
}
