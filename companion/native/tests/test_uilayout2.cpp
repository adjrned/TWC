// WFE's widescreen UI layout, the second batch (each op read by hand in
// WFEDll): the upper menu bar's buttons, the resource bar's strings and
// regions, idle workers, time of day, the tooltip, the message frames and
// the chat box, against a fake game UI; each frame is saved first and put
// back when it's turned off.
#include "../twc-game.cpp"
#include "check.h"
static BYTE *img;
struct Call { int kind; BYTE *lay; DWORD pt, rel, relPt; float x, y; } calls[512]; static int nCalls, clears;
static void __fastcall FSetPoint(BYTE *lay, int, DWORD pt, DWORD rel, DWORD rp, float x, float y, DWORD) { if (nCalls < 512) calls[nCalls++] = { 2, lay, pt, rel, rp, x, y }; }
static void __fastcall FSetAbs(BYTE *lay, int, DWORD pt, float x, float y, DWORD) { if (nCalls < 512) calls[nCalls++] = { 1, lay, pt, 0, 0, x, y }; }
static void __fastcall FClear(BYTE *, int, DWORD) { clears++; }
static void __fastcall FRefresh(BYTE *, int, DWORD) {}
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static const Call *Find(BYTE *lay, DWORD pt) { for (int i = nCalls - 1; i >= 0; i--) if (calls[i].lay == lay && calls[i].pt == pt) return &calls[i]; return nullptr; }
static bool Is(const Call *c, DWORD rel, DWORD relPt, float x, float y) { return c && c->kind == 2 && c->rel == rel && c->relPt == relPt && c->x == x && c->y == y; }
static float W(BYTE *lay) { return *(float *)(lay + 0x58); }

static BYTE ui[0x500], top[0x20], menu[0x200], btn[4][0x200], res[0x200], fs[2][0x100], reg[7][0x100], link[7][0x10];
static BYTE peon[0x200], tod[0x200], tip[0x200], con[0x200], msg[0x200], umsg[0x200], chat[0x200], full[0x200];
static BYTE *Simple(BYTE *f, DWORD vt) { *(DWORD *)f = (DWORD)(img + vt); *(BYTE **)(f + 0x68) = top; *(float *)(f + 0x58) = 0.5f; return f; }
static BYTE *CFrame(BYTE *f, DWORD vt) { *(DWORD *)f = (DWORD)(img + vt); *(BYTE **)(f + 0x44) = f; *(float *)(f + 0xb4 + 0x58) = 0.5f; return f; }

int main() {
    strcpy_s(g_logPath, "uilayout2.log"); DeleteFileA("uilayout2.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_SET_POINT, FSetPoint); Stub(RVA_SET_ABS_POINT, FSetAbs); Stub(RVA_CLEAR_POINTS, FClear); Stub(RVA_LAYOUT_REFRESH, FRefresh);
    DWORD old; VirtualProtect(img + 0xa7c000, 0x2000, PAGE_READWRITE, &old); VirtualProtect(img + 0xaa0000, 0x20000, PAGE_READWRITE, &old);
    *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE);
    *(DWORD *)top = (DWORD)(img + RVA_SIMPLE_TOP_VT);
    // the menu bar and its 4 buttons (simple frames)
    *(BYTE **)(ui + 0x3d0) = Simple(menu, 0xaad28c);
    static const DWORD BTN[4] = { 0x130, 0x134, 0x138, 0x160 };
    for (int i = 0; i < 4; i++) *(BYTE **)(menu + BTN[i]) = Simple(btn[i], 0xab0f10);
    // the resource bar: 2 font strings and 7 regions in its list
    *(BYTE **)(ui + 0x3cc) = Simple(res, 0xab20d4);
    for (int i = 0; i < 2; i++) *(DWORD *)fs[i] = (DWORD)(img + RVA_FONTSTRING_VTABLE), *(BYTE **)(res + 0x148 + i * 4) = fs[i];
    *(BYTE **)(res + 0xd8) = link[0];
    for (int i = 0; i < 7; i++) {
        *(DWORD *)reg[i] = (DWORD)(img + (i < 3 ? RVA_TEXTURE_VT : RVA_FONTSTRING_VTABLE)); *(float *)(reg[i] + 0x58) = 0.02f;
        *(BYTE **)(link[i] + 8) = reg[i]; *(BYTE **)(link[i] + 4) = i < 6 ? link[i + 1] : nullptr;
    }
    *(BYTE **)(ui + 0x3e0) = Simple(peon, 0xab0f08);
    *(BYTE **)(ui + 0x3f8) = CFrame(tod, 0xab2890);
    *(BYTE **)(ui + 0x1cc) = Simple(tip, 0xaad684);
    *(BYTE **)(ui + 0x428) = Simple(con, 0xab1008);
    *(BYTE **)(ui + 0x3e4) = Simple(msg, 0xa7d2a8); *(BYTE **)(ui + 0x3e8) = Simple(umsg, 0xa7d2a8);
    *(BYTE **)(ui + 0x3fc) = CFrame(chat, 0xaadfc4); *(BYTE **)(ui + 0x41c) = CFrame(full, 0xaa0100);
    g_uiVtable = *(DWORD *)ui; g_ulUi = ui;
    DWORD root = (DWORD)(ui + 0xb4);
    for (int i = 0; i < UL_GROUP_COUNT; i++)
        if (!strcmp(UL_GROUPS[i].name, "upper menu bar") || UL_GROUPS[i].fn == UlResources || UL_GROUPS[i].fn == UlIdle || UL_GROUPS[i].fn == UlTimeOfDay
            || UL_GROUPS[i].fn == UlTooltip || UL_GROUPS[i].fn == UlMessages || UL_GROUPS[i].fn == UlChat)
            UL_GROUPS[i].fn(ui, ui + 0xb4);
    CHECK(W(btn[2]) == 0.064f && Is(Find(btn[2], 0), root, 0, 0.1f, 0) && W(btn[0]) == 0.064f && W(btn[1]) == 0.064f && W(btn[3]) == 0.064f && W(menu) == 0.5f,
          "menu bar: the Quests button [bar+0x138] top left on the game UI's at 0.1, the 4 buttons 0.064 wide, the bar itself left");
    CHECK(Is(Find(fs[0], 1), root, 1, -0.045f, -0.1f) && Is(Find(fs[1], 1), root, 1, 0.0375f, -0.1f), "resource bar: its two strings top to the game UI's top");
    bool rr = Is(Find(reg[0], 0), (DWORD)res, 0, -0.015f, -0.003125f) && Is(Find(reg[1], 0), (DWORD)res, 0, 0.05f, -0.003125f) && Is(Find(reg[2], 0), (DWORD)res, 0, 0.115f, -0.003125f)
        && Is(Find(reg[3], 2), (DWORD)res, 2, -0.2975f, -0.003125f) && Is(Find(reg[6], 2), (DWORD)res, 2, -0.0925f, -0.003125f)
        && W(reg[0]) == 0.0125f && W(reg[2]) == 0.0125f && W(reg[3]) == 0.02f;
    CHECK(rr, "resource bar: regions 0..2 0.0125 wide on its top left, 3..6 on its top right, in WFE's places");
    CHECK(W(peon) == 0.0275f && Is(Find(peon, 6), root, 6, 0.1f, 0.1725f), "idle workers: 0.0275 wide, bottom left at 0.1, 0.1725");
    const Call *t = Find(tod + 0xb4, 4);
    CHECK(t && t->kind == 1 && t->x == 0.1635f && t->y == 0, "time of day (a CFrame: +0xb4): its centre at 0.1635, 0");
    CHECK(Is(Find(tip, 8), root, 0, 0.6875f, -0.435f), "tooltip: bottom right to the game UI's top left at 0.6875, -0.435");
    CHECK(Is(Find(msg, 7), (DWORD)con, 7, -0.025f, 0.18f) && Is(Find(umsg, 7), (DWORD)msg, 1, -0.098125f + 0.025f, 0.0005f), "messages: on the console's bottom, the unit messages on top of them");
    CHECK(Is(Find(chat + 0xb4, 3), (DWORD)(full + 0xb4), 6, 0.25f, 0.2f) && Is(Find(chat + 0xb4, 5), (DWORD)(full + 0xb4), 8, -0.25f, 0.2f), "chat box: +-0.25, 0.2 on the full-screen frame's corners");
    // off: every one of them back
    int n = g_ulN;
    for (int i = g_ulN - 1; i >= 0; i--) UlRestore(g_ul[i]);
    CHECK(n >= 18 && W(btn[2]) == 0.5f && W(peon) == 0.5f && W(reg[0]) == 0.02f, "put back: %d frames, their own widths again", n);
    Verdict();
    return g_fails;
}
