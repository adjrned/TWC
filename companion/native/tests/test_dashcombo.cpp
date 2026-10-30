// The dash combo (layout 41), against a fake game image: while ocOn the UI's 6 calls to its point order with
// a target (+3ffe80, the ground right click's) are watched (your right click's order and flags noted, then the game's own); a run (ocGo): the
// dash's button pressed, once its SPELL_EFFECT came the star round the boss (the orbs' centre): move orders
// (as your right click's) to each orb until it's gone, back through the boss between them, then to the point south of it;
// not run without your hero selected or orbs near; off: the calls are the game's again.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, ocKey) == offsetof(Shared, ocReach) + 4 && offsetof(Shared, ocFirst) == offsetof(Shared, ocThrough) + 4, "layout 41");

static BYTE *img;
static BYTE *objs[16];
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }
static void __fastcall FakePosition(BYTE *pos, int, float *out) { BYTE *u = pos - UNIT_POSITION; out[0] = *(float *)(u + 0x200), out[1] = *(float *)(u + 0x204), out[2] = 0; }
static void __fastcall FakeEffect(void *, int, void *) {}
struct Order { DWORD order; void *target; float x, y; DWORD a, b; };
static Order orders[16];
static int nOrders;
static void __stdcall FakeOrder(DWORD order, void *agent, float x, float y, void *target, DWORD a, DWORD b) { orders[nOrders++ & 15] = { order, target, x, y, a, b }; }
static BYTE units[7][0x300];            // 0 your hero, 1-5 your orbs (top, top left, bottom left, bottom right, top right), 6 someone else's orb
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
    for (int i = 1; i < 6; i++)
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
    for (int i = 0; i < 7; i++) {
        BYTE *u = units[i];
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT), *(float *)(u + UNIT_HP) = 100, *(int *)(u + UNIT_OWNER) = i == 6 ? 3 : 1;
        *(DWORD *)(u + 0x30) = i ? 'e05P' : 'Hlm1';
        ((DWORD *)(u + UNIT_MAXHP_HANDLE))[0] = ((DWORD *)(u + UNIT_MAXHP_HANDLE))[1] = 2;
    }
    objs[2] = maxObj, *(float *)(maxObj + 0x84) = 100;
    ((DWORD *)(hero + AGENT_HANDLE))[0] = ((DWORD *)(hero + AGENT_HANDLE))[1] = 3;
    objs[3] = handle, *(BYTE **)(handle + HANDLE_OBJ) = hero, *(DWORD *)(handle + HANDLE_TAG) = '+agl';
    At(hero, 0, 0), At(units[1], 15, 410), At(units[2], -387, 103), At(units[3], -239, -356), At(units[4], 254, -315), At(units[5], 392, 121), At(units[6], 50, 0);
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
    sh.ocDash = 'A107', sh.ocOrb = 'e05P', sh.ocSouth = 150, sh.ocReach = 0, sh.ocThrough = 60, sh.ocFirst = 225;
    List({ hero }), Orbs();                     // (only the hero in the game's unit list: the orbs never are)

    sh.ocOn = 1; OrbComboPass(); BossCastPass();
    bool ours = g_ocHooked && g_bcHooked;
    for (DWORD rva : OC_SITES)
        ours = ours && SiteTarget(img + rva) == (BYTE *)PointOrderSpy;
    CHECK(ours, "on: the UI's 6 calls to its point order with a target (+3FFE80, the ground right click's) are watched (and the SPELL_EFFECT calls, for the dash)");
    // your own right click on the ground: its order and flags noted, then the game's own; an ability's point order (a
    // quickcast's Lightning Bolt, 11:16) passed on, not taken
    ((PointOrderFn)SiteTarget(img + OC_SITES[1]))(0xd0278, nullptr, 1, 2, nullptr, 0x2, 0x4);
    bool notAbility = !g_ocSeen;
    ((PointOrderFn)SiteTarget(img + OC_SITES[0]))(0xd0003, nullptr, 10, 20, nullptr, 0x5, 0x40);
    CHECK(nOrders == 2 && notAbility && orders[1].a == 0x5 && g_ocSeen && g_ocFlagA == 0x5 && g_ocFlagB == 0x40 && LogHas("your right click's order 000D0003 at (10, 20), flags 00000005 / 00000040"),
          "your right click: passed on, its order and flags noted (0x5 / 0x40); an ability's point order passed on, not taken");
    // a run: the 12:06 report's 5 orbs round the hero at (0, 0) (their centre (7, -7.4): the boss)
    sh.ocGo++; OrbComboPass();
    CHECK(pressed == 1 && g_oc.state == 1 && g_oc.castAt && LogHas("'A107' pressed with 5 orbs near"), "a run: the dash's button pressed (5 orbs near: someone else's not counted), its cast seen");
    OrbComboTick();
    Order o = orders[(nOrders - 1) & 15];
    BYTE *T = units[1], *TL = units[2], *BL = units[3], *BR = units[4], *TR = units[5];
    float cx = g_oc.cx, cy = g_oc.cy;
    auto last = [&](float x, float y) { o = orders[(nOrders - 1) & 15]; return o.x == x && o.y == y; };
    CHECK(nOrders == 3 && g_oc.state == 2 && g_oc.n == 5 && g_oc.path[0] == BL && g_oc.path[1] == TR && g_oc.path[2] == TL && g_oc.path[3] == BR && g_oc.path[4] == T
          && fabsf(cx - 7) < 0.01f && fabsf(cy + 7.4f) < 0.01f && o.order == 0xd0003 && !o.target && o.x == -239 && o.y == -356 && o.a == 0x5 && o.b == 0x40
          && LogHas("5 orbs round the boss at (7, -7) (their centre; your hero 10 from it), in the order: bottom left, top right, top left, bottom right, top; back through it after each (within 60)"),
          "the star round the boss (the orbs' centre): bottom left first, then every second one anticlockwise (the clockwise one's 7 degrees straighter: within 15, the first kept); the first order out as your right click's");
    OrbComboTick();
    At(hero, -150, -220); OrbComboTick();
    CHECK(nOrders == 3, "the orb still there (163 from it: in the map's pickup, not taken yet): no new order (no ocReach)");
    OrbGone(BL); OrbComboTick();
    CHECK(nOrders == 4 && sh.ocTaken == 1 && last(cx, cy), "the first taken (RemoveUnit): back to the boss");
    At(hero, -100, -150); OrbComboTick();
    bool notYet = nOrders == 4;
    At(hero, -20, -30); OrbComboTick();
    CHECK(notYet && nOrders == 5 && last(392, 121), "within 60 of the boss (not at 160): on to the top right one");
    OrbGone(T); OrbComboTick();
    CHECK(nOrders == 5 && sh.ocTaken == 2 && LogHas("the top orb taken early"), "another orb gone on the way: logged, no new order");
    At(hero, 300, 90), OrbGone(TR); OrbComboTick();
    At(hero, 0, 0); OrbComboTick();
    CHECK(nOrders == 7 && sh.ocTaken == 3 && last(-387, 103), "the top right taken, through the boss: on to the top left");
    At(hero, -360, 100); OrbComboTick();
    CHECK(nOrders == 8 && sh.ocTaken == 3 && last(cx, cy), "stopped at the top left (27 from it) with it still there: back to the boss (not counted taken)");
    At(hero, -200, 50); OrbComboTick();
    At(hero, -75, 15); OrbComboTick();
    bool coming = nOrders == 8;
    At(hero, 130, -60); OrbComboTick();
    CHECK(coming && nOrders == 9 && last(254, -315), "never within 60 but past the boss (85 at its closest, now 134): on to the bottom right");
    At(hero, 200, -250), OrbGone(BR); OrbComboTick();
    At(hero, 10, -10); OrbComboTick();
    CHECK(nOrders == 11 && last(cx, cy - 150) && sh.ocTaken == 4 && !g_oc.state && sh.ocState == 0 && sh.ocRuns == 1
          && LogHas("each orb (ms after the dash): bottom left taken ") && LogHas("; top left stopped at it, still there, ") && LogHas("(passed, closest 85)")
          && LogHas("; top taken early ") && LogHas("(no orbs left); then to the end point"),
          "the top one gone early: none left after the bottom right's pass, to 150 below the boss; each orb and pass logged");
    OrbGone(TL);
    // held up at the boss (no nearer in 250 ms): on anyway
    Orbs(), At(hero, 0, 0);
    sh.ocGo++; OrbComboPass(); OrbComboTick();
    At(hero, -60, -90), OrbGone(BL); OrbComboTick();
    int held = nOrders;
    OrbComboTick();
    Sleep(300); OrbComboTick();
    CHECK(nOrders == held + 1 && last(392, 121), "held up 106 from the boss (no nearer in 250 ms): on to the next");
    OrbEnd("the check", false);
    for (int i = 1; i < 6; i++)
        OrbGone(units[i]);                      // (only someone else's orb left)
    // not run: your hero not the one selected; no orbs of yours near
    *(BYTE **)(sel + SEL_ACTIVE) = units[1]; sh.ocGo++; OrbComboPass();
    bool notSel = !g_oc.state && LogHas("not run: your hero isn't the unit selected");
    *(BYTE **)(sel + SEL_ACTIVE) = hero; sh.ocGo++; OrbComboPass();
    CHECK(notSel && !g_oc.state && pressed == 2 && LogHas("not run: no 'e05P' orbs of yours near your hero"), "not run without your hero selected, or without orbs: nothing pressed");
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
