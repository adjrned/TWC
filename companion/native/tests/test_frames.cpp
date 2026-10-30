// Frames added to the game, against a fake game image: the game functions are
// C++ fakes behind jumps at their 1.28f offsets, so every call goes through
// GameCall with the conventions the module assumes (__fastcall, stack
// arguments cleaned by the callee). Covers the timers drawn in the game,
// health numbers and mana bars: made, placed, shown and hidden with the
// health bar, destroyed with it, and everything put back when turned off.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, itOn) == 688 && offsetof(Shared, mbCount) == 728 && offsetof(Shared, itemLeft) == 732 && sizeof(Shared) >= 780, "layout 11");

static BYTE *img;
static BYTE *imgRef() { return img; }
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
    *(DWORD *)(mem + TEXT_SHADOW) = 0xFF000000, *(float *)(mem + 0x210) = 0.015f, *(float *)(mem + 0x214) = -0.015f;   // the game's default shadow (+0x12b48a)
    texts++;
    return parent && id == TEXT_ID ? mem : nullptr;
}
static void __fastcall FakeFlags(BYTE *, int, DWORD) { flagCalls++; }
static void __fastcall FakeSetText(BYTE *t, int, const char *s) { setTexts++; strcpy_s(lastText, s); strcpy_s((char *)t + 0x100, 32, s); }
static int __fastcall FakeSetFont(BYTE *, int, const char *path, float h, DWORD) { fonts++; strcpy_s(lastFont, path); lastFontH = h; return 1; }
static int refreshes, clears;
static void __fastcall FakeClearPoints(BYTE *, int, int) { clears++; }
static void __fastcall FakeRefresh(BYTE *, int, int) { refreshes++; }
static void __fastcall FakeSetPoint(BYTE *l, int, int pt, void *rel, int, float x, float y, int) {
    anchors++; lastRel = rel; lastX = x; lastY = y;
    if (*(DWORD *)l == (DWORD)(imgRef() + SWEEP_TEXTURE_VT))       // a sweep square: its top left / bottom left kept for the test
        pt == 6 ? (void)(*(float *)(l + 0x18) = y) : (void)(*(float *)(l + 0x10) = x, *(float *)(l + 0x14) = y);
}
static void __fastcall FakeSetAbs(BYTE *lay, int, int, float x, float y, int) { absPoints++; lastX = x; lastY = y; *(float *)(lay + 0x10) = y; }
static const char *__fastcall FakeSkin(const char *key, int) { return !strcmp(key, "MasterFont") ? "Fonts\\Test.ttf" : nullptr; }
static void __fastcall FakeTextHide(BYTE *t, int) { hides++; t[0x1e0] = 0; }
static BYTE barTexts[3][0x20]; static int barTextHides;
static void __fastcall FakeRegionHide(BYTE *r, int) {
    if (*(DWORD *)r == (DWORD)(imgRef() + SWEEP_TEXTURE_VT)) *(DWORD *)(r + 0x7c) = 0;
    if (r >= barTexts[0] && r < barTexts[3]) barTextHides++, r[0x10] = 0;
}
// our cooldown sweep's game calls
static int sweepFrames, sweepTextures, allPoints; static const char *sweepPath;
static BYTE *imgRef();
static void __fastcall FakeRegionShow(BYTE *r, int);
static void *__fastcall FakeFrameCtor(BYTE *mem, int, void *) { sweepFrames++; *(DWORD *)mem = (DWORD)(imgRef() + RVA_SIMPLEFRAME_VT); return mem; }
static void *__fastcall FakeTexCtor(BYTE *mem, int, void *, DWORD, DWORD) { sweepTextures++; *(DWORD *)mem = (DWORD)(imgRef() + SWEEP_TEXTURE_VT); *(DWORD *)(mem + 0x7c) = 1; return mem; }
static void __fastcall FakeSetTex(BYTE *, int, const char *path, DWORD) { sweepPath = path; }
// our sweep's squares: their tint applied (a texture's vt+0x24)
static int tints;
static void __fastcall FakeTint(BYTE *, int) { tints++; }
static void __fastcall FakeAllPoints(BYTE *, int, void *, DWORD) { allPoints++; }
static void __fastcall FakeSetW(BYTE *t, int, float w) { *(float *)(t + LAYOUT_WIDTH) = w; }
static void __fastcall FakeSetH(BYTE *t, int, float h) { *(float *)(t + LAYOUT_HEIGHT) = h; }
static void __fastcall FakeRegionShow(BYTE *r, int) {
    if (*(DWORD *)r == (DWORD)(imgRef() + SWEEP_TEXTURE_VT)) *(DWORD *)(r + 0x7c) = 1; }
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
    Stub(RVA_BAR_LEVEL, FakeBarLevel); Stub(RVA_REGION_HIDE, FakeRegionHide); Stub(RVA_REGION_SHOW, FakeRegionShow); Stub(RVA_UNIT_HP, FakeState);
    Stub(RVA_HANDLE_LOOKUP, FakeLookup);
    Stub(RVA_SIMPLEFRAME_CTOR, FakeFrameCtor); Stub(RVA_TEXTURE_CTOR, FakeTexCtor); Stub(RVA_SET_TEXTURE, FakeSetTex);
    Stub(RVA_SET_ALL_POINTS, FakeAllPoints); Stub(RVA_SET_WIDTH, FakeSetW); Stub(RVA_SET_HEIGHT, FakeSetH);
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
    static BYTE inv[0x200], ibtns[6][0x200]; static DWORD invArr[12];
    *(BYTE **)(console + 0x148) = inv; *(int *)(inv + 0x12c) = 6; *(DWORD **)(inv + 0x130) = invArr;
    for (int i = 0; i < 6; i++) { invArr[i * 2 + 1] = (DWORD)ibtns[i]; *(DWORD *)ibtns[i] = (DWORD)cv; }

    // -- timers drawn in the game ------------------------------------------------
    CHECK(FramesCheck() == 1, "the frame functions and vtables check out");
    g_framesUi = ui;
    sh.itOn = 3;                                // bits: 1 cooldowns, 2 buffs
    sh.cdLeft[0] = 5.3f; sh.cdLeft[5] = 3; sh.cdLeft[11] = 75; sh.buffLeft[2] = 0.46f; sh.buffFlags[2] = 1;
    TimerFramesDraw(ui);
    CHECK(texts == 27 && !g_tItem[0].text && g_tCd[0].text && g_tCd[11].text && !g_tCd[5].text && g_tBuff[2].text && g_tBuff[2].out[7],
        "frames for the 2 command buttons and 1 buff, each a text and its 8-copy outline: %d", texts);
    CHECK(fabsf(lastFontH - 0.013f) < 1e-6f, "the buff's text at WFE's TEXTSIZE 0.013 (%.4f)", lastFontH);
    CHECK(!strcmp(g_tCd[0].shown, "6") && !strcmp(g_tCd[11].shown, "75") && !strcmp(g_tBuff[2].shown, "0.5"), "texts: %s, %s, %s (whole seconds: WFE's DISPLAYMINUTES off)", g_tCd[0].shown, g_tCd[11].shown, g_tBuff[2].shown);
    sh.tmMinutes = MIN_COOLDOWNS;
    TimerFramesDraw(ui);
    CHECK(!strcmp(g_tCd[11].shown, "1:15") && texts == 27, "minutes on for cooldowns: %s, the same frame", g_tCd[11].shown);
    sh.tmMinutes = 0;
    TimerFramesDraw(ui);
    CHECK(!strcmp(lastFont, "Fonts\\Test.ttf") && fonts == 27 && flagCalls == 27, "the skin's MasterFont, flags set (%s, %d fonts)", lastFont, fonts);
    CHECK(g_tCd[0].text[0x1e0] == 1 && g_tCd[0].out[0][0x1e0] == 1 && *(DWORD *)(g_tCd[0].out[7] + TEXT_COLOURS) == 0xFF000000 && *(DWORD *)(g_tCd[0].text + TEXT_COLOURS) == 0xFFFFFFFF,
        "shown; white text, black outline");
    CHECK(*(DWORD *)(g_tCd[0].text + TEXT_SHADOW) == 0 && *(float *)(g_tCd[0].text + 0x210) == 0 && *(float *)(g_tCd[0].out[0] + 0x214) == 0,
        "the game's own shadow (black, 0.015 off: the dark second number) is off on our text frames");
    CHECK(anchors == 27 && lastRel == bbtns[2] && fabsf(lastY - BUFF_TEXT_Y) < 1e-6f, "anchored to their buttons (the buff text under its icon)");
    sh.itemLeft[3] = 12.2f; int a0 = anchors; TimerFramesDraw(ui);
    CHECK(texts == 36 && g_tItem[3].text && !strcmp(g_tItem[3].shown, "13") && anchors == a0 + 9 && lastRel == ibtns[3], "an item cooling down: its text on its inventory button");
    sh.itemLeft[3] = 0; TimerFramesDraw(ui);
    CHECK(g_tItem[3].text[0x1e0] == 0, "and hidden when it's ready");
    int setBefore = setTexts; TimerFramesDraw(ui);
    CHECK(setTexts == setBefore && anchors == a0 + 9, "nothing changed: no text set, no anchoring again");
    sh.cdLeft[0] = 0; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 0 && g_tCd[0].out[3][0x1e0] == 0 && texts == 36, "ready: hidden, the frames kept");
    sh.cdLeft[0] = 2; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 1 && texts == 36 && !strcmp(g_tCd[0].shown, "2"), "cooling down again: the same frames shown");
    // the cooldowns' look (layout 20): gold near the end, a size, "Ready" in green when over
    sh.cdGold = 5; sh.cdLeft[0] = 4.2f; TimerFramesDraw(ui);
    bool gold = *(DWORD *)(g_tCd[0].text + TEXT_COLOURS) == GOLD && *(DWORD *)(g_tCd[0].out[0] + TEXT_COLOURS) == BLACK;
    sh.cdLeft[0] = 8; TimerFramesDraw(ui);
    CHECK(gold && *(DWORD *)(g_tCd[0].text + TEXT_COLOURS) == WHITE, "gold at 4.2 s with 'gold from 5 s', white again at 8 s; the outline black");
    int fn0 = fonts, an0 = anchors;
    sh.cdSize = 1.5f; TimerFramesDraw(ui);
    CHECK(fonts >= fn0 + 9 && anchors >= an0 + 9 && fabsf(lastFontH - 0.021f) < 1e-5f && texts == 36, "size x1.5: %.4f, the outline anchored again further out, no new frames", lastFontH);
    sh.cdSize = 0; sh.cdReady = 1; sh.cdLeft[0] = 0.3f; TimerFramesDraw(ui);
    sh.cdLeft[0] = 0; TimerFramesDraw(ui);
    bool ready = !strcmp(g_tCd[0].shown, "Ready") && *(DWORD *)(g_tCd[0].text + TEXT_COLOURS) == GREEN && g_tCd[0].text[0x1e0] == 1;
    g_tCd[0].readyUntil = GetTickCount() - 1; TimerFramesDraw(ui);
    CHECK(ready && g_tCd[0].text[0x1e0] == 0 && texts == 36, "a cooldown over: 'Ready' in green, then hidden after its half second");
    sh.cdLeft[5] = 0; sh.cdLeft[11] = 30; TimerFramesDraw(ui); sh.cdLeft[11] = 0; TimerFramesDraw(ui);
    CHECK(g_tCd[11].text[0x1e0] == 0, "no 'Ready' when the seconds vanish from 30 (another unit selected), only when they run out");
    sh.cdGold = 0, sh.cdReady = 0, sh.cdLeft[0] = 2, sh.cdLeft[11] = 75; TimerFramesDraw(ui);
    // our sweep (cdSweep bit 2): a frame of ours over the button, squares tinted black at 60%, the part to come clockwise from 12 o'clock
    {
        DWORD old2; VirtualProtect(img + RVA_SIMPLEFRAME_VT, 0x100, PAGE_READWRITE, &old2);
        ((DWORD *)(img + RVA_SIMPLEFRAME_VT))[0x68 / 4] = StubAt(0x610000, FakeNop);
        VirtualProtect(img + SWEEP_TEXTURE_VT, 0x100, PAGE_READWRITE, &old2);
        ((DWORD *)(img + SWEEP_TEXTURE_VT))[0x24 / 4] = StubAt(0x610100, FakeTint);
        *(float *)(btns[0] + LAYOUT_WIDTH) = 0.04f, *(float *)(btns[0] + LAYOUT_HEIGHT) = 0.04f;
        sh.itOn = 1, sh.cdSweep = CD_SWEEP, sh.cdLeft[0] = 7.5f, sh.cdTotal[0] = 10;
        SweepsPass(ui, true);
        Sweep *r = g_swN ? &g_sw[0] : nullptr;
        auto tex = [&](int k) { return r->cell[k].tex; };
        auto shown = [&](int k) { return r && k < r->made && (*(DWORD *)(tex(k) + 0x7c) & 1) != 0; };
        auto count = [&]() { int n = 0; for (int k = 0; r && k < r->made; k++) n += shown(k); return n; };
        auto W = [&](int k) { return *(float *)(tex(k) + LAYOUT_WIDTH); };
        auto H = [&](int k) { return *(float *)(tex(k) + LAYOUT_HEIGHT); };
        // the shown squares against the clock: a 48 x 48 grid of points over a w x h button, the share that disagree
        auto wrong = [&](float f, float w, float h) {
            int bad = 0;
            for (int i = 0; i < 48; i++)
                for (int j = 0; j < 48; j++) {
                    float u = (i + 0.5f) / 48 * w, v = (j + 0.5f) / 48 * h;
                    bool want = f > 0 && ClockAngle(u / w * 2 - 1, 1 - v / h * 2) >= PI_2 * (1 - f), have = false;
                    for (int k = 0; r && k < r->made && !have; k++) {
                        float x = *(float *)(tex(k) + 0x10), t = -*(float *)(tex(k) + 0x14);
                        have = shown(k) && u >= x && u < x + W(k) && v >= t && v < t + H(k);
                    }
                    bad += want != have;
                }
            return bad / (48.0f * 48);
        };
        bool made = r && r->btn == btns[0] && sweepFrames == 1 && r->made > 0 && sweepTextures == r->made && allPoints == 1 && sweepPath && strstr(sweepPath, "TeamColor04")
            && tints == r->made && tex(0)[0x68] == SWEEP_ALPHA && !tex(0)[0x69] && !tex(0)[0x6b];
        // 3/4 to come (7.5 of 10 s): all but the top right quarter, as two squares (the top left quarter, the bottom half)
        float e1 = wrong(0.75f, 0.04f, 0.04f);
        bool q = count() == 2 && e1 < 0.001f;
        sh.cdLeft[0] = 2.5f; SweepsPass(ui, true);
        bool q2 = count() == 1 && wrong(0.25f, 0.04f, 0.04f) < 0.001f && fabsf(W(0) - 0.02f) < 1e-5f && fabsf(H(0) - 0.02f) < 1e-4f;   // the top left quarter
        sh.cdLeft[0] = 5; SweepsPass(ui, true);
        bool half = count() == 1 && fabsf(W(0) - 0.02f) < 1e-5f && fabsf(H(0) - 0.04f) < 1e-4f;                                         // the left half
        // a tenth, and the shapes between: right within a row's height of the edge (under 2% of the points), a few dozen squares at most
        float e3 = 0, e6 = 0, e9 = 0;
        int n6 = 0;
        sh.cdLeft[0] = 1; SweepsPass(ui, true); e3 = wrong(0.1f, 0.04f, 0.04f);
        bool wedge = shown(0) && *(float *)(tex(0) + 0x10) < 0.02f && *(float *)(tex(0) + 0x10) + W(0) <= 0.02f + 1e-6f;   // left of 12 o'clock
        sh.cdLeft[0] = 6; SweepsPass(ui, true); e6 = wrong(0.6f, 0.04f, 0.04f), n6 = count();
        // stacked squares meet exactly: a square's bottom point is the very number of the top of one under it, never over it
        int meet = 0, over = 0;
        for (int a = 0; a < r->made; a++)
            for (int b = 0; shown(a) && b < r->made; b++)
                if (b != a && shown(b)) {
                    float ab = *(float *)(tex(a) + 0x18), bt = *(float *)(tex(b) + 0x14);
                    meet += ab == bt;
                    over += bt > ab && bt < *(float *)(tex(a) + 0x14) && *(float *)(tex(b) + 0x10) < *(float *)(tex(a) + 0x10) + W(a) && *(float *)(tex(a) + 0x10) < *(float *)(tex(b) + 0x10) + W(b);
                }
        if (!meet || over)
            printf("  the 0.6 sweep's squares: %d meet exactly, %d overlap\n", meet, over);
        sh.cdLeft[0] = 8.8f; SweepsPass(ui, true); e9 = wrong(0.88f, 0.04f, 0.04f);
        bool shapes = e3 < 0.02f && e6 < 0.02f && e9 < 0.02f && wedge && n6 <= 70 && meet > 0 && !over;
        sh.cdLeft[0] = 2.5f; SweepsPass(ui, true);
        int a1 = anchors; SweepsPass(ui, true);
        bool still = anchors == a1;                 // nothing changed: no square moved
        sh.cdLeft[0] = 9.99f; SweepsPass(ui, true);
        bool full = wrong(0.999f, 0.04f, 0.04f) < 0.02f;
        // between the reads (10 a second): redrawn with the time since taken off, so it moves every frame
        sh.cdLeft[0] = 5; SweepsPass(ui, true, 2.5f);
        bool between = count() == 1 && fabsf(W(0) - 0.02f) < 1e-5f && fabsf(H(0) - 0.02f) < 1e-4f && g_swAny;   // 2.5 of 10 left: the top left quarter
        SweepsPass(ui, true, 9.0f);
        bool past = count() == 0 && g_swAny;        // run past 0 before the next read: nothing drawn, still counted as showing (the read ends it)
        if (!between || !past)
            printf("  the sweep between reads: quarter %d, kept past 0 %d\n", between, past);
        sh.cdLeft[0] = 0; SweepsPass(ui, true);
        bool swGone = count() == 0 && !g_swAny && between && past;
        sh.cdLeft[0] = 5; SweepsPass(ui, false);
        bool off = count() == 0;
        CHECK(made && q && q2 && half && shapes && still && full && swGone && off && sweepFrames == 1 && r->made <= SWEEP_CELLS,
              "our sweep: %d rows, black at 60%%; 3/4 to come: 2 squares, 1/4 and 1/2: 1; a tenth, 0.6, 0.88: %.1f%% / %.1f%% / %.1f%% of points off (%d squares at 0.6); unchanged: none moved; just cast: all; over or off: none (%d made)",
              SWEEP_ROWS, e3 * 100, e6 * 100, e9 * 100, n6, r ? r->made : 0);
        // the button's laid-out rect wins over its +0x58 / +0x5C (sized by its anchors, or narrowed by the Widescreen UI):
        // a 0.0275 x 0.04 button: half to come is one 0.01375-wide square; a new height places it again
        float *rc = (float *)(btns[0] + LAYOUT_RECT);
        rc[0] = 0.1f, rc[1] = 0.5f, rc[2] = 0.14f, rc[3] = 0.5275f;     // y first: bottom, left, top, right
        sh.cdLeft[0] = 5; SweepsPass(ui, true);
        bool narrow = count() == 1 && fabsf(W(0) - 0.01375f) < 1e-5f && fabsf(H(0) - 0.04f) < 1e-4f && wrong(0.5f, 0.0275f, 0.04f) < 0.001f;
        rc[2] = 0.132f; SweepsPass(ui, true);
        bool lower = fabsf(H(0) - 0.032f) < 1e-4f;
        // the height back while one square is used: the second, hidden then, gets the new height when it's shown
        sh.cdLeft[0] = 2.5f; SweepsPass(ui, true);
        rc[2] = 0.14f; SweepsPass(ui, true);
        sh.cdLeft[0] = 7.5f; SweepsPass(ui, true);
        lower = lower && count() == 2 && wrong(0.75f, 0.0275f, 0.04f) < 0.001f;
        float w, h;
        rc[0] = rc[1] = rc[2] = rc[3] = 0;
        *(float *)(btns[0] + LAYOUT_WIDTH) = 0, *(float *)(btns[0] + LAYOUT_HEIGHT) = 0;
        ButtonSize(btns[0], &w, &h);
        bool fallback = w == BUTTON_SIZE && h == BUTTON_SIZE;
        *(float *)(btns[0] + LAYOUT_WIDTH) = 0.032f, *(float *)(btns[0] + LAYOUT_HEIGHT) = 0.032f;
        ButtonSize(btns[0], &w, &h);
        CHECK(narrow && lower && fallback && w == 0.032f && h == 0.032f,
              "the sweep fits the button as laid out (0.0275 x 0.04: half to come %.5f wide), a lower button: placed again; no rect: its own size, else 0.039", W(0));
        *(float *)(btns[0] + LAYOUT_WIDTH) = 0.04f, *(float *)(btns[0] + LAYOUT_HEIGHT) = 0.04f;
        sh.cdLeft[0] = 0; SweepsPass(ui, true);
        bool wanted = SweepWanted();
        g_swBad = true;
        bool refused = !SweepWanted();
        g_swBad = false, sh.itOn = 2;
        CHECK(wanted && refused && !SweepWanted(), "the game's clock is hidden only while ours can be drawn: not once ours is refused, nor without cooldowns");
        sh.itOn = 1, sh.cdSweep = 0, sh.cdLeft[0] = 2;
    }
    sh.itOn = 1; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 1 && g_tBuff[2].text[0x1e0] == 0, "cooldowns only (bit 1): the buff's seconds hidden");
    sh.itOn = 2; TimerFramesDraw(ui);
    CHECK(g_tCd[0].text[0x1e0] == 0 && g_tBuff[2].text[0x1e0] == 1, "buffs only (bit 2): the cooldowns hidden");
    // the buffs' look (layout 22): gold near the end (bfGold), a size (bfSize), auras' seconds only with bfOpts 1
    sh.bfGold = 3, sh.buffLeft[2] = 2.4f; TimerFramesDraw(ui);
    bool bgold = *(DWORD *)(g_tBuff[2].text + TEXT_COLOURS) == GOLD;
    sh.buffLeft[2] = 6; TimerFramesDraw(ui);
    bool bwhite = *(DWORD *)(g_tBuff[2].text + TEXT_COLOURS) == WHITE;
    sh.cdGold = 30, sh.bfGold = 0, sh.buffLeft[2] = 2.4f; TimerFramesDraw(ui);
    CHECK(bgold && bwhite && *(DWORD *)(g_tBuff[2].text + TEXT_COLOURS) == WHITE, "a buff gold at 2.4 s with 'gold from 3 s', white at 6 s; the cooldowns' setting leaves buffs alone");
    sh.cdGold = 0, sh.bfSize = 1.5f; TimerFramesDraw(ui);
    CHECK(fabsf(lastFontH - 0.0195f) < 1e-5f && fabsf(g_tBuff[2].height - 0.0195f) < 1e-5f, "buff size x1.5: %.4f (0.013 x 1.5)", lastFontH);
    sh.bfSize = 0, sh.buffFlags[2] = 3; TimerFramesDraw(ui);
    bool auraOff = g_tBuff[2].text[0x1e0] == 0;
    sh.bfOpts = BF_AURAS; TimerFramesDraw(ui);
    CHECK(auraOff && g_tBuff[2].text[0x1e0] == 1 && !strcmp(g_tBuff[2].shown, "3"), "an aura: no seconds (WFE's default), with 'auras too' its %s", g_tBuff[2].shown);
    sh.bfOpts = 0, sh.buffFlags[2] = 1, sh.buffLeft[2] = 0.46f; TimerFramesDraw(ui);
    sh.buffFlags[2] = 3; TimerFramesDraw(ui);
    CHECK(g_tBuff[2].text[0x1e0] == 0, "an aura: no seconds (WFE's ISDRAWAURADURATION is off)");
    sh.buffFlags[2] = 1, sh.itOn = 3; TimerFramesDraw(ui);
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
        *(BYTE **)(b + BAR_TEXT) = barTexts[i]; barTexts[i][0x10] = 1;
    }
    auto update = [&](int i) { ((BarUpdateFn)bv[STATBAR_UPDATE / 4])(bars[i], 0, units[i]); };
    {   // health bar colours went on first: the bar update entry is our hook, the frames still check out
        DWORD keep = bv[STATBAR_UPDATE / 4], o2; VirtualProtect(bv, 0x100, PAGE_READWRITE, &o2);
        bv[STATBAR_UPDATE / 4] = (DWORD)BarUpdateHook;
        bool ok = GameVtable(RVA_STATBAR_VTABLE, { STATBAR_UPDATE });
        bv[STATBAR_UPDATE / 4] = keep; VirtualProtect(bv, 0x100, o2, &o2);
        CHECK(ok, "a vtable entry that's one of our hooks still checks out (colours on before the frames)");
    }
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
    CHECK(barTextHides >= 3 && !barTexts[0][0x10] && !barTexts[1][0x10], "each health bar's own text hidden (the dark copy beside the number)");
    BYTE *m0 = e0->mana;
    CHECK(*(DWORD *)(m0 + BAR_KIND) == 0 && fabsf(*(float *)(m0 + BAR_HEIGHT) - 0.003f) < 1e-6f && *(float *)(m0 + BAR_WIDTH) == 0.05f && *(int *)(m0 + BAR_CUR) == 30 && *(int *)(m0 + BAR_MAX) == 60,
        "the mana bar: kind 0, 3/4 the height, the same width, 30 of 60");
    CHECK(fabsf(*(float *)(m0 + 0x10) - (0.4f - 0.004f - MANA_GAP)) < 1e-6f && *(DWORD *)(m0 + BAR_SHOWN) == 1 && e0->textShown, "placed under the bar and shown with it");
    sh.mbWidth = 0.5f; sh.mbHeight = 1.25f; update(0);
    CHECK(*(float *)(m0 + BAR_WIDTH) == 0.025f && fabsf(*(float *)(m0 + BAR_HEIGHT) - 0.005f) < 1e-6f, "a typed mana size: half the width, x1.25 the height (%.4f x %.4f)",
        *(float *)(m0 + BAR_WIDTH), *(float *)(m0 + BAR_HEIGHT));
    sh.mbWidth = 0; sh.mbHeight = 0.75f; update(0);
    CHECK(*(float *)(m0 + BAR_WIDTH) == 0.05f, "width 0 (an older companion): the health bar's");
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
    BYTE *mGame = BxFind(bars[0], false)->mana; int mc = (int)sh.mbCount, dd = barDtors;
    ((BarDtorFn)bv[BAR_DTOR / 4])(mGame, 0, 1);
    CHECK(!BxFind(bars[0], false)->mana && (int)sh.mbCount == mc - 1 && barDtors == dd + 1, "the game destroys a mana bar itself: forgotten, not destroyed again");
    sh.mbOn = 0; FramesPass();
    CHECK(sh.mbCount == 0 && !e0->mana && g_extrasHooked && sh.mbState == 0, "mana bars off: all destroyed, numbers stay");
    sh.hnOn = 0; FramesPass();
    CHECK(g_bxCount == 0 && sh.hnCount == 0 && !g_extrasHooked && bv[BAR_HIDE / 4] == StubAt(0x200050, FakeBarHide) && bv[BAR_DTOR / 4] == StubAt(0x200040, FakeBarDtor),
        "both off: numbers hidden, entries the game's again");
    FollowColours();
    CHECK(!g_barHooked && bv[STATBAR_UPDATE / 4] == gameUpdate, "and the worker puts the bar update back");
    CHECK(frees == barCtors - 1, "every mana bar made was freed but the one the game destroyed (%d made, %d freed)", barCtors, frees);
    // a bigger buff bar (layout 23, no widescreen UI): the bar and its 8 icons k x the game's size; back when off
    {
        *(DWORD *)buffBar = (DWORD)(img + RVA_BUFF_BAR_VT);
        for (int i = 0; i < 8; i++)
            *(DWORD *)bbtns[i] = (DWORD)(img + RVA_BUFF_INDICATOR_VT), *(float *)(bbtns[i] + LAYOUT_WIDTH) = *(float *)(bbtns[i] + LAYOUT_HEIGHT) = 0.015f;
        *(float *)(buffBar + LAYOUT_WIDTH) = 0.12f, *(float *)(buffBar + LAYOUT_HEIGHT) = 0.015f;
        int r0 = refreshes;
        sh.ulOn = 0, sh.bbScale = 1; BuffBarSizePass();
        bool none = refreshes == r0 && sh.bbState == 0;
        sh.bbScale = 1.5f; BuffBarSizePass();
        bool big = fabsf(*(float *)(buffBar + LAYOUT_WIDTH) - 0.18f) < 1e-6f && fabsf(*(float *)(buffBar + LAYOUT_HEIGHT) - 0.0225f) < 1e-6f
            && fabsf(*(float *)(bbtns[7] + LAYOUT_WIDTH) - 0.0225f) < 1e-6f && fabsf(*(float *)(bbtns[0] + LAYOUT_HEIGHT) - 0.0225f) < 1e-6f && sh.bbState == 1;
        int r1 = refreshes; BuffBarSizePass();
        bool still = refreshes == r1;
        sh.bbScale = 0; BuffBarSizePass();
        bool back = fabsf(*(float *)(buffBar + LAYOUT_WIDTH) - 0.12f) < 1e-6f && fabsf(*(float *)(bbtns[3] + LAYOUT_WIDTH) - 0.015f) < 1e-6f && sh.bbState == 0 && !g_bbApplied;
        int r2 = refreshes; BuffBarSizePass();
        CHECK(none && big && still && back && refreshes == r2, "buff bar x1.5: 0.18 x 0.0225, icons 0.0225 (refreshed once, not again); off: the game's 0.12 x 0.015 and 0.015, then left alone");
        sh.bbScale = 2, sh.ulOn = 1; BuffBarSizePass();
        CHECK(fabsf(*(float *)(buffBar + LAYOUT_WIDTH) - 0.12f) < 1e-6f && sh.bbState == 1, "with the widescreen UI on: left to its layout (UlBuffs)");
        sh.bbScale = 0, sh.ulOn = 0; BuffBarSizePass();
        // raised over the console without the widescreen UI (layout 35): its bottom right at the bar's height + 0.13
        // from the screen's, its right edge where the game laid it out (0.5 of the UI's 0.8); back when off
        Stub(RVA_CLEAR_POINTS, FakeClearPoints);
        ((float *)(buffBar + LAYOUT_RECT))[3] = 0.5f;
        int a0 = anchors, c0 = clears;
        sh.bbUp = 1; BuffBarRaisePass();
        bool raised = g_bbUpApplied && sh.bbUpState == 1 && anchors == a0 + 1 && clears == c0 + 1 && lastRel == ui + FRAME_LAYOUT
            && fabsf(lastX - -0.3f) < 1e-6f && fabsf(lastY - (0.015f + 0.13f)) < 1e-6f;
        sh.ulOn = 1; BuffBarRaisePass();
        bool toWide = !g_bbUpApplied && sh.bbUpState == 0 && clears == c0 + 2;          // put back (UlRestore clears, sets the saved ones)
        sh.ulOn = 0; BuffBarRaisePass();
        bool again = g_bbUpApplied;
        sh.bbUp = 0; BuffBarRaisePass();
        CHECK(raised && toWide && again && !g_bbUpApplied && sh.bbUpState == 0, "buff bar raised without the widescreen UI: at -0.30, 0.145 from the screen's bottom right; given back with the widescreen UI on (its layout raises it) and off");
        *(DWORD *)buffBar = 0; BuffBarSizePass();
    }
    // a new game while bars are still listed: they're forgotten, not touched
    sh.hnOn = 1; FramesPass(); FollowColours(); FramesPass();
    for (int i = 0; i < 3; i++) update(i);
    int listed = g_bxCount;
    static BYTE ui2[0x400]; memcpy(ui2, ui, sizeof(ui2)); fakeUi = ui2; int s0 = setTexts, h0 = hides;
    FramesPass();
    CHECK(listed == 3 && g_bxCount == 0 && sh.hnCount == 0 && setTexts == s0 && hides == h0, "a new game UI: the last game's %d bars forgotten without a call", listed);
    Verdict();
    return g_fails;
}
