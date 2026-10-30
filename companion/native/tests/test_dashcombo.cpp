// The dash combo (layout 38), against a fake game image: while ocOn the UI's 4 calls to its point order
// (+3ffd60) are watched (your right click's order and flags noted, then the game's own); a run (ocGo): the
// dash's button pressed, once its SPELL_EFFECT came a move order (as your right click's) to the nearest of
// your orbs (from the game's unit list), the next one as each goes, then to the point south of the start;
// not run without your hero selected or orbs near; off: the calls are the game's again.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, ocKey) == offsetof(Shared, ocReach) + 4, "layout 40");

static BYTE *img;
static BYTE *objs[16];
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }
static void __fastcall FakePosition(BYTE *pos, int, float *out) { BYTE *u = pos - UNIT_POSITION; out[0] = *(float *)(u + 0x200), out[1] = *(float *)(u + 0x204), out[2] = 0; }
static void __fastcall FakeEffect(void *, int, void *) {}
struct Order { DWORD order; void *target; float x, y; DWORD a, b; };
static Order orders[16];
static int nOrders;
static void __stdcall FakeOrder(DWORD order, void *target, float x, float y, DWORD a, DWORD b) { orders[nOrders++ & 15] = { order, target, x, y, a, b }; }
static BYTE units[5][0x300];            // 0 your hero, 1-3 your orbs, 4 someone else's orb
static BYTE *hero = units[0];
static BYTE dashAbility[0x100];
static int pressed;
// the dash's button pressed: the game casts it (its SPELL_EFFECT through the first of the 3 calls)
static void __fastcall FakeClick(BYTE *btn, int, int) {
    pressed++;
    ((SpellEffectFn)SiteTarget(img + BC_SITES[0]))(hero, 0, dashAbility);
}
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
static BYTE *list[8];
// the orbs as the game makes them (the combo notes them from the unit creation: they're not in its unit list)
static void Orbs() {
    for (int i = 1; i < 5; i++)
        OrbSeen(units[i], *(DWORD *)(units[i] + 0x30));
}
static void List(std::initializer_list<BYTE *> us) {
    int n = 0;
    for (BYTE *u : us)
        list[n++] = u;
    *(DWORD *)(img + RVA_UNIT_LIST + 4) = n, *(BYTE ***)(img + RVA_UNIT_LIST + 8) = list;
}
static void At(BYTE *u, float x, float y) { *(float *)(u + 0x200) = x, *(float *)(u + 0x204) = y; }
static bool LogHas(const char *s) {
    FILE *f;
    if (fopen_s(&f, "dashcombo.log", "rb"))
        return false;
    static char buf[1 << 16];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    return strstr(buf, s) != nullptr;
}

int main() {
    strcpy_s(g_logPath, "dashcombo.log"); DeleteFileA("dashcombo.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_HANDLE_LOOKUP, FakeLookup), Stub(RVA_UNIT_POSITION, FakePosition), Stub(RVA_SPELL_EFFECT, FakeEffect), Stub(RVA_UNIT_HP, FakeStat);
    Stub(RVA_POINT_ORDER, FakeOrder), Stub(0x5f0000, FakeClick);
    for (DWORD rva : BC_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(img + RVA_SPELL_EFFECT - (img + rva + 5));
    for (DWORD rva : OC_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(img + RVA_POINT_ORDER - (img + rva + 5));
    // you: player 1, your hero selected at (0, 0); orbs 'e05P'; the command card: one button, the dash 'A107'
    static BYTE state[0x200], players[16][0x300], sel[0x200], handle[0x80], maxObj[0x100], ui[0x500], card[0x200], rowsArr[16], data[0x800];
    static BYTE *cols[4];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1, *(int *)(state + 0x54) = 16;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i];
    *(BYTE **)(players[1] + SEL_PLAYER_SELECTION) = sel, *(BYTE **)(sel + SEL_ACTIVE) = hero;
    for (int i = 0; i < 5; i++) {
        BYTE *u = units[i];
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT), *(float *)(u + UNIT_HP) = 100, *(int *)(u + UNIT_OWNER) = i == 4 ? 3 : 1;
        *(DWORD *)(u + 0x30) = i ? 'e05P' : 'Hlm1';
        ((DWORD *)(u + UNIT_MAXHP_HANDLE))[0] = ((DWORD *)(u + UNIT_MAXHP_HANDLE))[1] = 2;
    }
    objs[2] = maxObj, *(float *)(maxObj + 0x84) = 100;
    ((DWORD *)(hero + AGENT_HANDLE))[0] = ((DWORD *)(hero + AGENT_HANDLE))[1] = 3;
    objs[3] = handle, *(BYTE **)(handle + HANDLE_OBJ) = hero, *(DWORD *)(handle + HANDLE_TAG) = '+agl';
    At(hero, 0, 0), At(units[1], 400, 0), At(units[2], 300, 300), At(units[3], -400, 100), At(units[4], 50, 0);
    *(DWORD *)(dashAbility + 0x34) = 'A107';
    static BYTE btn[0x200];
    DWORD *bvt = (DWORD *)(img + 0xa79000);
    DWORD old; VirtualProtect(img + 0xa79000, 0x1000, PAGE_READWRITE, &old);         // a vtable: data
    bvt[0] = bvt[1] = (DWORD)(img + 0x5f0000), bvt[BTN_CLICK / 4] = (DWORD)(img + 0x5f0000);
    *(DWORD *)btn = (DWORD)bvt, *(BYTE **)(btn + BTN_DATA) = data, *(BYTE **)(data + 0x6d4) = dashAbility;
    cols[0] = btn, *(DWORD *)(rowsArr + 4) = 1, *(BYTE ***)(rowsArr + 8) = cols;
    *(int *)(card + 0x124) = 1, *(int *)(card + 0x128) = 1, *(BYTE **)(card + 0x154) = rowsArr;
    *(BYTE **)(ui + 0x3c8) = card;
    g_getUi = [](int, int) -> void * { return ui; };
    sh.ocDash = 'A107', sh.ocOrb = 'e05P', sh.ocSouth = 150, sh.ocReach = 190;
    List({ hero }), Orbs();                     // (only the hero in the game's unit list: the orbs never are)

    sh.ocOn = 1; OrbComboPass(); BossCastPass();
    bool ours = g_ocHooked && g_bcHooked;
    for (DWORD rva : OC_SITES)
        ours = ours && SiteTarget(img + rva) == (BYTE *)PointOrderSpy;
    CHECK(ours, "on: the UI's 4 calls to its point order are watched (and the SPELL_EFFECT calls, for the dash)");
    // your own right click on the ground: its order and flags noted, then the game's own; an ability's point order (a
    // quickcast's Lightning Bolt, 11:16) passed on, not taken
    ((PointOrderFn)SiteTarget(img + OC_SITES[1]))(0xd0278, nullptr, 1, 2, 0x2, 0x4);
    bool notAbility = !g_ocSeen;
    ((PointOrderFn)SiteTarget(img + OC_SITES[1]))(0xd0003, nullptr, 10, 20, 0x5, 0x40);
    CHECK(nOrders == 2 && notAbility && orders[1].a == 0x5 && g_ocSeen && g_ocFlagA == 0x5 && g_ocFlagB == 0x40 && LogHas("your point order 000D0003 at (10, 20), flags 00000005 / 00000040"),
          "your right click: passed on, its order and flags noted (0x5 / 0x40); an ability's point order passed on, not taken");
    // a run: orbs at (400, 0), (300, 300), (-400, 100) from the hero at (0, 0)
    sh.ocGo++; OrbComboPass();
    CHECK(pressed == 1 && g_oc.state == 1 && g_oc.castAt && LogHas("'A107' pressed with 3 orbs near"), "a run: the dash's button pressed (3 orbs near: someone else's not counted), its cast seen");
    OrbComboTick();
    Order o = orders[(nOrders - 1) & 15];
    CHECK(nOrders == 3 && g_oc.state == 2 && g_oc.n == 3 && g_oc.path[0] == units[3] && g_oc.path[1] == units[1] && g_oc.path[2] == units[2]
          && o.order == 0xd0003 && !o.target && o.x == -400 && o.y == 100 && o.a == 0x5 && o.b == 0x40 && LogHas("3 orbs, the path planned 757 long"),
          "the path planned through all 3: the shortest ((-400, 100), (400, 0), (300, 300): 757, nearest first would be 789), the first order out as your right click's");
    OrbComboTick();
    CHECK(nOrders == 3, "not in reach yet: no new order");
    At(hero, -260, 90); OrbComboTick();
    o = orders[(nOrders - 1) & 15];
    CHECK(nOrders == 4 && sh.ocTaken == 1 && o.x == 400 && o.y == 0, "in reach of the first (140 from it, the orb still there): on to the next at once");
    OrbGone(units[1]); OrbComboTick();          // the second taken by the map (RemoveUnit) before it came in reach
    o = orders[(nOrders - 1) & 15];
    CHECK(nOrders == 5 && sh.ocTaken == 2 && o.x == 300 && o.y == 300, "one gone before it was reached: on to the next");
    At(hero, 250, 250); OrbComboTick();
    o = orders[(nOrders - 1) & 15];
    CHECK(sh.ocTaken == 3 && !g_oc.state && sh.ocState == 0 && sh.ocRuns == 1 && o.x == 0 && o.y == -150 && LogHas("each orb reached (ms after the dash):") && LogHas("(every orb reached); then to the end point"),
          "every orb reached: to 150 south of the start (0, -150), the run over, each orb's time logged");
    OrbGone(units[2]), OrbGone(units[3]);       // (only someone else's orb left)
    // not run: your hero not the one selected; no orbs of yours near
    *(BYTE **)(sel + SEL_ACTIVE) = units[1]; sh.ocGo++; OrbComboPass();
    bool notSel = !g_oc.state && LogHas("not run: your hero isn't the unit selected");
    *(BYTE **)(sel + SEL_ACTIVE) = hero; sh.ocGo++; OrbComboPass();
    CHECK(notSel && !g_oc.state && pressed == 1 && LogHas("not run: no 'e05P' orbs of yours near your hero"), "not run without your hero selected, or without orbs: nothing pressed");
    // its key in the game's window (the module reads it: no companion hotkey): a run, the key kept from the game;
    // another key, or its repeat while held: not; the chat open: the game's
    Orbs(), At(hero, 0, 0);
    sh.ocKey = 'J';                             // (no Ctrl / Alt / Shift: the check's own keyboard has none down)
    bool other = !OrbComboKey('K', 0);
    int before = pressed;
    bool took = OrbComboKey('J', 0) && g_oc.state && pressed == before + 1 && LogHas("its key 4A in the game");
    OrbComboKey('J', 0x40000000);               // its repeat
    bool once = pressed == before + 1;
    OrbEnd("the check", false);
    static BYTE chat[0x200];
    *(BYTE **)(ui + UI_CHAT_STATE) = chat, *(DWORD *)(chat + 0x1dc) = 1;
    bool typing = !OrbComboKey('J', 0) && pressed == before + 1;
    *(BYTE **)(ui + UI_CHAT_STATE) = nullptr;
    CHECK(other && took && once && typing, "its key in the game: a run (the key kept from the game); another key or its repeat: no new run; the chat open: the game's");
    sh.ocOn = 0; OrbComboPass();
    bool back = !g_ocHooked;
    for (DWORD rva : OC_SITES)
        back = back && SiteTarget(img + rva) == img + RVA_POINT_ORDER;
    CHECK(back, "off: the 4 calls are the game's again");
    Verdict();
    return g_fails;
}
