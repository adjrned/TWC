// harness: quickcast keys as WFE does them (KeyCast): the key's button pressed on the game thread
// through its own click (vtable +0x6c, 1, [+0x138] bit 2 during), then the click at the cursor
// when the game wants a target; the key kept from the game. A fake game image and a fake
// "Warcraft III" window of our own (never shown in front, no real keys or clicks: g_click is ours,
// key states are faked)
#define GetKeyState FakeKeyState
#define GetAsyncKeyState FakeAsync
#include "../twc-game.cpp"
#include "check.h"
#undef GetKeyState
#undef GetAsyncKeyState
static int syncVk[256], asyncVk[256];
SHORT WINAPI FakeKeyState(int vk) { return syncVk[vk & 0xff] ? (SHORT)0x8000 : 0; }
SHORT WINAPI FakeAsync(int vk) { return asyncVk[vk & 0xff] ? (SHORT)0x8000 : 0; }
static BYTE *img;
static BYTE ui[0x400], card[0x200], btns[12][0x200], *rowBtns[3][4], rowsTab[3][16], chat[0x200], upper[0x200];
static BYTE inv[0x200], invTab[6][8], items[6][0x200], datas[18][0x700], abils[18][0x100], targetMode[0x40];
static void *__fastcall FakeGetUi(int, int) { return ui; }
static int presses, pressArg, flagsSeen; static void *pressThis; static bool aims[0x1000];
static int __fastcall FakePress(BYTE *b, int, int arg) {
    presses++, pressArg = arg, pressThis = b, flagsSeen = *(DWORD *)(b + BTN_FLAGS);
    if (aims[(b - (BYTE *)0) & 0xfff])
        *(DWORD *)(ui + UI_MODE) = *(DWORD *)(ui + UI_TARGET_MODE);  // a targeted ability: the game asks for a target
    return 1;
}
static int __fastcall FaultPress(BYTE *, int, int) { return *(volatile int *)8; }
static int clicks; static DWORD clickFlags;
static void FakeClick(DWORD f) { clicks++, clickFlags = f; }
static int gameKeys, gameChars;
static LRESULT CALLBACK GameProc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
    if (m == WM_KEYDOWN)
        gameKeys++;
    if (m == WM_CHAR)
        gameChars++;
    return DefWindowProcA(w, m, wp, lp);
}
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static void Button(BYTE *b, int k, bool aim, DWORD vt) {
    *(DWORD *)b = vt; *(DWORD *)(b + BTN_FLAGS) = 0x10; *(BYTE **)(b + BTN_DATA) = datas[k];
    *(BYTE **)(datas[k] + 0x6d4) = abils[k]; *(DWORD *)(abils[k] + 0x34) = 'AHtb';
    aims[(b - (BYTE *)0) & 0xfff] = aim;
}
static void Idle() { *(DWORD *)(ui + UI_MODE) = 0x99; }
int main() {
    strcpy_s(g_logPath, "keycast.log"); DeleteFileA("keycast.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(0x200000, FakePress); Stub(0x200100, FaultPress);
    DWORD old; VirtualProtect(img + 0xaaa000, 0x4000, PAGE_READWRITE, &old);
    DWORD *btnVt = (DWORD *)(img + 0xaac000); btnVt[BTN_CLICK / 4] = (DWORD)(img + 0x200000);
    DWORD *badVt = (DWORD *)(img + 0xaac400); badVt[BTN_CLICK / 4] = (DWORD)(img + 0x200100);
    *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE); g_uiVtable = *(DWORD *)ui;
    *(BYTE **)(ui + UI_TARGET_MODE) = targetMode; Idle();
    *(BYTE **)(ui + 0x3c8) = card; *(BYTE **)(ui + UI_CHAT_STATE) = chat; *(BYTE **)(ui + UI_UPPER_BAR) = upper; *(DWORD *)(upper + 0x164) = 1;
    *(int *)(card + 0x124) = 3; *(int *)(card + 0x128) = 4; *(BYTE **)(card + 0x154) = (BYTE *)rowsTab;
    for (int i = 0; i < 12; i++) { Button(btns[i], i, i != 9, (DWORD)btnVt); rowBtns[i / 4][i % 4] = btns[i]; }
    for (int r = 0; r < 3; r++) { *(DWORD *)(rowsTab[r] + 4) = 4; *(BYTE ***)(rowsTab[r] + 8) = rowBtns[r]; }
    BYTE *console = ui + 0x300; *(BYTE **)(ui + 0x3c4) = console; *(BYTE **)(console + 0x148) = inv;
    *(int *)(inv + 0x12c) = 6; *(BYTE **)(inv + 0x130) = (BYTE *)invTab;
    for (int i = 0; i < 6; i++) { Button(items[i], 12 + i, false, (DWORD)btnVt); *(BYTE **)(invTab[i] + 4) = items[i]; }
    g_getUi = FakeGetUi; g_click = FakeClick;
    // TWRPG's keys: Q W E R the bottom row (slots 8-11), items on the numpad
    g_shared->qkVk[8] = 'Q', g_shared->qkVk[9] = 'W', g_shared->qkVk[10] = 'E', g_shared->qkVk[12] = VK_NUMPAD7;
    WNDCLASSA wc = {}; wc.lpfnWndProc = GameProc; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    HWND wnd = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, -3000, -3000, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(wnd, SW_SHOWNOACTIVATE);

    CHECK(!KeyCast('Q') && presses == 0, "off (the companion hasn't asked): nothing");
    g_shared->qkOn = 1; FollowKeyCast();
    CHECK(g_shared->qkState == 1 && g_oldProc, "on: the game window is ours (state %lu)", g_shared->qkState);
    bool r = KeyCast('Q');
    CHECK(r && presses == 1 && pressThis == btns[8] && pressArg == 1 && (flagsSeen & 2) && *(DWORD *)(btns[8] + BTN_FLAGS) == 0x10 && clicks == 1 && clickFlags == 0
        && g_shared->qkPressed == 1 && g_shared->qkClicked == 1,
        "Q: slot 8's button pressed with 1 (bit 2 during, flags back), the game wants a target: clicked at once, no Shift");
    Idle();
    r = KeyCast('W');
    CHECK(r && presses == 2 && pressThis == btns[9] && clicks == 1, "W: an instant ability: pressed, no click, the key kept from the game");
    *(DWORD *)(abils[10] + 0x20) = 0x200;
    r = KeyCast('E');
    CHECK(!r && presses == 2, "E cooling down: not pressed, the key goes to the game (as WFE)");
    *(DWORD *)(abils[10] + 0x20) = 0;
    *(DWORD *)(btns[10] + BTN_DATA) = 0;
    CHECK(!KeyCast('E') && presses == 2, "an empty slot: the game's key");
    *(BYTE **)(btns[10] + BTN_DATA) = datas[10];
    CHECK(!KeyCast('R') && !KeyCast('Z') && presses == 2, "keys that don't quickcast: the game's");
    syncVk[VK_CONTROL] = 1;
    CHECK(!KeyCast('Q') && presses == 2, "Ctrl+Q: the game's (a control group or so)");
    syncVk[VK_CONTROL] = 0;
    syncVk[VK_SHIFT] = asyncVk[VK_SHIFT] = 1; Idle();
    KeyCast('Q');
    DWORD held = clickFlags;
    asyncVk[VK_SHIFT] = 0; Idle();
    KeyCast('Q');
    syncVk[VK_SHIFT] = 0;
    CHECK(held == 1 && clickFlags == 3 && clicks == 3, "Shift (a queued order): kept while held (1), pressed around the click once it's up (3)");
    // WFE's checks (0x10066a86..abb)
    int before = presses;
    *(DWORD *)(ui + UI_BUSY) = 1; bool c1 = KeyCast('Q'); *(DWORD *)(ui + UI_BUSY) = 0;
    *(DWORD *)(upper + 0x164) = 0; bool c2 = KeyCast('Q'); *(DWORD *)(upper + 0x164) = 1;
    *(DWORD *)(chat + 0x1dc) = 1; bool c3 = KeyCast('Q'); *(DWORD *)(chat + 0x1dc) = 0;
    CHECK(!c1 && !c2 && !c3 && presses == before, "WFE's checks: [ui+0x258], the upper bar's +0x164 = 0, [[ui+0x3fc]+0x1dc]: not now");
    Idle();
    r = KeyCast(VK_NUMPAD7);
    CHECK(r && pressThis == items[0] && pressArg == 1, "Numpad 7: the first item's button pressed");
    // through the game window: a quickcast key never reaches the game, others do
    Idle(); gameKeys = 0;
    SendMessageA(wnd, WM_KEYDOWN, 'Q', 0);
    SendMessageA(wnd, WM_CHAR, 'q', 0);
    SendMessageA(wnd, WM_KEYDOWN, 'Z', 0);
    SendMessageA(wnd, WM_CHAR, 'z', 0);
    CHECK(gameKeys == 1 && gameChars == 1, "through the window: Q and its character kept from the game, Z and its character passed on (%d, %d)", gameKeys, gameChars);
    g_shared->qkOn = 0; FollowKeyCast(); gameKeys = 0;
    SendMessageA(wnd, WM_KEYDOWN, 'Q', 0);
    CHECK(g_shared->qkState == 0 && gameKeys == 1, "off again: Q goes to the game");
    g_shared->qkOn = 1; FollowKeyCast();
    // a button that faults: off for good, the key to the game
    *(DWORD *)btns[11] = (DWORD)badVt; g_shared->qkVk[11] = 'T';
    r = KeyCast('T');
    CHECK(!r && g_shared->qkState == 3 && !KeyCast('Q'), "a press faulting: caught, quickcast keys off (state 3)");
    Unsubclass(); DestroyWindow(wnd);
    Verdict();
    return g_fails;
}
