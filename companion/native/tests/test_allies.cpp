// Allies' abilities (WFE's ISALLYABILITYBAR), the cooldown ping and the buff reads (WFE's
// BUFFUI), against a fake game image: the observer-view function's start is detoured to
// a copy and back, the ability callback's push points at the hook, allied units count and
// enemies don't, everything is put back off; the ping line from the hovered button; the
// buff's full time by its unit (hero +0xc8, else +0xc0) and through a linked buff.
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, alOn) == 848 && offsetof(Shared, pingText) == 864 && offsetof(Shared, tmMinutes) == 992 && offsetof(Shared, cdSize) == 1000 && offsetof(Shared, hrWant) == 1016 && offsetof(Shared, hrName) == 1416 && offsetof(Shared, bbScale) == 2580 && offsetof(Shared, blAccount) == 2604 && offsetof(Shared, blGame) == 2704 && offsetof(Shared, utOn) == 2736 && offsetof(Shared, qcState) == 2744 && offsetof(Shared, qkOn) == 2768 && offsetof(Shared, dmOn) == 2804 && offsetof(Shared, dmColour) == 3524 && offsetof(Shared, dmLocal) == 3588 && offsetof(Shared, btKnownSeq) == 3592 && offsetof(Shared, dmRingSeq) == 4244 && offsetof(Shared, dmRingAbility) == 59052 && sizeof(Shared) == 59052 + 8192 + 512 + 4096, "layout 34");

static BYTE *img;
static int displays, clicks;
static BYTE *controlled;                // the unit the local player controls (+0x6a2d90 tests ecx)
static int __fastcall FakeControls(BYTE *unit, int) { return unit && unit == controlled; }
static void __fastcall FakeClick(BYTE *, int, DWORD) { clicks++; }
static void __fastcall FakeDisplay(BYTE *, int, DWORD) { displays++; }
static int makes;
static void __fastcall FakeMake(BYTE *, int, DWORD) { makes++; }
static int __fastcall FakeMakeCallback(BYTE *, BYTE *) { return 5; }
static int __fastcall FakeCallback(BYTE *, BYTE *) { return 7; }
// a unit state (+0x81b30): the fake keeps the value itself at the state's place
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
// a getter in the image: mov eax, v; ret (passes the decoder)
static DWORD IntGetter(DWORD rva, DWORD v) { BYTE *p = img + rva; p[-1] = 0xCC, p[0] = 0xB8, *(DWORD *)(p + 1) = v, p[5] = 0xC3; return (DWORD)p; }
// a timer getter: mov eax, [esp+4]; mov dword [eax], f; ret 4
static DWORD FloatGetter(DWORD rva, float f) {
    BYTE *p = img + rva; p[-1] = 0xCC;
    BYTE b[] = { 0x8B, 0x44, 0x24, 0x04, 0xC7, 0x00, 0, 0, 0, 0, 0xC2, 0x04, 0x00 };
    memcpy(b + 6, &f, 4), memcpy(p, b, sizeof(b));
    return (DWORD)p;
}

int main() {
    strcpy_s(g_logPath, "allies.log"); DeleteFileA("allies.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    DWORD old;
    VirtualProtect(img + 0xa60000, 0x120000, PAGE_READWRITE, &old);         // vtables: data
    VirtualProtect(img + 0xd00000, 0x40000, PAGE_READWRITE, &old);          // globals
    // +0x6bffd0 as 1.28f has it: push esi; mov esi, [state]; call ...; ... ; xor eax, eax; pop esi; ret
    BYTE *f = img + RVA_SEES_ALL;
    BYTE sees[] = { 0x56, 0x8B, 0x35, 0, 0, 0, 0, 0xE8, 0, 0, 0, 0, 0x33, 0xC0, 0x5E, 0xC3 };
    *(DWORD *)(sees + 3) = (DWORD)(img + RVA_PLAYERS);
    f[-1] = 0xCC, memcpy(f, sees, sizeof(sees));
    BYTE *callee = img + 0x500000; callee[-1] = 0xCC, callee[0] = 0x33, callee[1] = 0xC0, callee[2] = 0xC3;   // xor eax, eax; ret
    *(LONG *)(f + 8) = (LONG)(callee - (f + 12));
    Stub(RVA_ABILITY_CB, FakeCallback), Stub(RVA_CONTROLS, FakeControls), Stub(RVA_ABILITY_DISPLAY, FakeDisplay), Stub(RVA_BUTTON_CLICK, FakeClick);
    Stub(RVA_ABILITY_MAKE_CB, FakeMakeCallback), Stub(RVA_ABILITY_MAKE, FakeMake);
    BYTE *pushMake = img + RVA_ABILITY_MAKE_PUSH; pushMake[0] = 0x68, *(DWORD *)(pushMake + 1) = (DWORD)(img + RVA_ABILITY_MAKE_CB);
    *(DWORD *)(img + RVA_COMMAND_BUTTON_VTABLE + 0x6c) = (DWORD)(img + RVA_BUTTON_CLICK);
    BYTE *push = img + RVA_ABILITY_CB_PUSH; push[0] = 0x68, *(DWORD *)(push + 1) = (DWORD)(img + RVA_ABILITY_CB);
    // players: local 1, allied with 2 (the colours' Allied: [p+0x38]+0x40 pair -> flags +0x78)
    static BYTE state[0x200], players[16][0x300], allyH[0x60], flagsObj[0x100];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i], players[i][0x30] = (BYTE)i;
    *(BYTE **)(players[1] + 0x38) = allyH, ((DWORD *)(allyH + 0x40))[0] = 5, ((DWORD *)(allyH + 0x40))[1] = 6;
    BYTE lk[] = { 0xB8, 0, 0, 0, 0, 0xC3 }; *(DWORD *)(lk + 1) = (DWORD)flagsObj;
    img[RVA_HANDLE_LOOKUP - 1] = 0xCC, memcpy(img + RVA_HANDLE_LOOKUP, lk, sizeof(lk));
    *(DWORD *)(flagsObj + 0x78) = 1u << 2;
    static BYTE mine[0x300], ally[0x300], enemy[0x300], ability[0x200], abEntry[0x20];
    for (BYTE *u : { mine, ally, enemy })
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT);
    *(int *)(mine + UNIT_OWNER) = 1, *(int *)(ally + UNIT_OWNER) = 2, *(int *)(enemy + UNIT_OWNER) = 3;
    *(BYTE **)(ability + 0x1bc) = abEntry, *(DWORD *)(abEntry + 8) = 0x1234;

    CHECK(AlliesPatchable(), "the fake image has both places as 1.28f");
    sh.alOn = 1; AlliesPass();
    CHECK(g_alHooked && sh.alState == 1 && f[0] == 0xE9 && *(DWORD *)(push + 1) == (DWORD)AllyAbilityHook, "on: the start detoured, the callback's push points at the hook");
    SeesFn sees2 = (SeesFn)f;
    CHECK(sees2(mine, 0) == 1 && sees2(ally, 0) == 1 && sees2(enemy, 0) == 0 && sees2(nullptr, 0) == 0,
          "sees the commands of: yours yes, an ally's yes, an enemy's no, no unit no (the game's own answer 0 through the copy)");
    controlled = mine;
    int r1 = AllyAbilityHook(ally, ability), d1 = displays;
    int r2 = AllyAbilityHook(enemy, ability), d2 = displays;
    AllyAbilityHook(mine, ability); int d3 = displays;
    CHECK(r1 == 7 && d1 == 1 && r2 == 7 && d2 == 1 && d3 == 1,
          "the callback: the game's runs (returns 7), then an ally's ability display is updated, an enemy's not; yours: left to the game (it controls them)");
    // the card's first callback (+3E4020, its push at +3FAE04): an ally's buttons made too (the card was empty without it)
    int m1 = AllyAbilityMakeHook(ally, ability), mk1 = makes;
    AllyAbilityMakeHook(enemy, ability); int mk2 = makes;
    AllyAbilityMakeHook(mine, ability); int mk3 = makes;
    CHECK(*(DWORD *)(pushMake + 1) == (DWORD)AllyAbilityMakeHook && m1 == 5 && mk1 == 1 && mk2 == 1 && mk3 == 1,
          "the card's first callback is ours too: the game's runs (5), an ally's buttons made, an enemy's not, yours the game's");
    // a click on the command card: dropped while the selection's active unit is an ally's you don't control
    DWORD *cvt = (DWORD *)(img + RVA_COMMAND_BUTTON_VTABLE);
    *(int *)(state + 0x54) = 16;
    static BYTE sel[0x200];
    *(BYTE **)(players[1] + PLAYER_SELECTION) = sel;
    ButtonClickFn click = (ButtonClickFn)cvt[0x6c / 4];
    *(BYTE **)(sel + SELECTION_ACTIVE) = ally; click(nullptr, 0, 1); int c1 = clicks;
    *(BYTE **)(sel + SELECTION_ACTIVE) = mine; click(nullptr, 0, 1); int c2 = clicks;
    *(BYTE **)(sel + SELECTION_ACTIVE) = enemy; click(nullptr, 0, 1); int c3 = clicks;
    *(BYTE **)(sel + SELECTION_ACTIVE) = nullptr; click(nullptr, 0, 1); int c4 = clicks;
    CHECK(cvt[0x6c / 4] == (DWORD)AllyClickHook && c1 == 0 && c2 == 1 && c3 == 2 && c4 == 3,
          "clicks: an ally's card dropped; yours, an enemy's, none: the game's click (%d %d %d %d)", c1, c2, c3, c4);
    // enemies too (alOn | AL_ENEMIES): an enemy's commands seen, its ability shown, a click on its card dropped
    sh.alOn = 1 | AL_ENEMIES;
    int e1 = sees2(enemy, 0), de0 = displays;
    AllyAbilityHook(enemy, ability);
    *(BYTE **)(sel + SELECTION_ACTIVE) = enemy; click(nullptr, 0, 1); int c5 = clicks;
    *(BYTE **)(sel + SELECTION_ACTIVE) = mine; click(nullptr, 0, 1); int c6 = clicks;
    AllyAbilityHook(mine, ability);
    CHECK(e1 == 1 && displays == de0 + 1 && c5 == 3 && c6 == 4, "enemies too: an enemy's commands seen, its ability shown, its card's click dropped; yours still the game's");
    sh.alOn = 1;
    sh.alOn = 0; AlliesPass();
    CHECK(!g_alHooked && !memcmp(f, sees, 7) && *(DWORD *)(push + 1) == (DWORD)(img + RVA_ABILITY_CB) && cvt[0x6c / 4] == (DWORD)(img + RVA_BUTTON_CLICK)
          && *(DWORD *)(pushMake + 1) == (DWORD)(img + RVA_ABILITY_MAKE_CB),
          "off: the start's 7 bytes, both pushes and the button's click entry are the game's again");
    sh.alOn = 1; AlliesPass(); RestoreAll();
    CHECK(!g_alHooked && !memcmp(f, sees, 7) && cvt[0x6c / 4] == (DWORD)(img + RVA_BUTTON_CLICK), "RestoreAll (unload) puts them back too");

    // the ping: the hovered button (CSimpleTop's +0x16c) is a command card button
    static BYTE top[0x200], ui[0x500], card[0x200], rowT[16], btn[0x300], data[0x800], info[0x200], panel[0x200], nameFs[0x100];
    static BYTE *btns[1];
    *(DWORD *)top = (DWORD)(img + RVA_SIMPLE_TOP_VT), *(BYTE **)(img + RVA_SIMPLE_TOP) = top;
    *(BYTE **)(ui + 0x3c8) = card, *(int *)(card + 0x124) = 1, *(int *)(card + 0x128) = 1;
    *(BYTE **)(card + 0x154) = rowT, *(DWORD *)(rowT + 4) = 1, *(BYTE ***)(rowT + 8) = btns, btns[0] = btn;
    *(BYTE **)(btn + 0x190) = data, strcpy_s((char *)data + DATA_NAME, 32, "|cffffcc00Holy|r Light");
    *(DWORD *)info = *(DWORD *)panel = (DWORD)(img + 0xab0000);
    *(BYTE **)(ui + 0x3c4) = info, *(BYTE **)(info + 0x130) = panel, *(BYTE **)(panel + 0x128) = nameFs;
    *(DWORD *)nameFs = (DWORD)(img + RVA_FONTSTRING_VTABLE), *(const char **)(nameFs + FS_TEXT) = "Paladin";
    CHECK(PingCommand(ui) == 2 && !sh.pingText[0], "nothing under the cursor: no ping");
    *(BYTE **)(top + TOP_HOVER) = btn;
    HoverPass(ui);
    int pr = PingCommand(ui);
    CHECK(sh.hover == 1 && pr == 1 && !strcmp(sh.pingText, "Paladin >> Holy Light | Ready!"), "the hovered ability, no cooldown: \"%s\"", sh.pingText);
    // cooling down: [btn+0x19c], the ability [data+0x6d4] with flags 0x200, its timer's getters
    static BYTE ab[0x200], timer[0x40], model[0x10];
    DWORD *tvt = (DWORD *)(img + 0xa6f780);
    tvt[0x18 / 4] = FloatGetter(0x600000, 7.2f), tvt[0x10 / 4] = FloatGetter(0x600100, 10);
    *(DWORD *)(ab + 0xd0) = (DWORD)tvt;
    *(BYTE **)(btn + 0x19c) = model, *(BYTE **)(data + 0x6d4) = ab, *(DWORD *)(ab + 0x34) = 'AHhb', *(DWORD *)(ab + 0x20) = 0x200;
    PingCommand(ui);
    CHECK(!strcmp(sh.pingText, "Paladin >> Holy Light | Cooldown: 8") && sh.pingChat == 0, "cooling down: \"%s\" (no Chat dialog: where the chat goes is unknown)", sh.pingText);
    // WFE's "Not enough mana!": the data's cost [+0x594] over the ability's unit's mana (+0xb8, the state getter +0x81b30)
    Stub(RVA_UNIT_HP, FakeStat);
    *(BYTE **)(ab + AGENT_OWNER) = mine, *(float *)(mine + UNIT_MANA) = 40, *(int *)(data + DATA_MANA_COST) = 75;
    *(float *)(flagsObj + 0x84) = 200;                                      // the max mana's object (the fake lookup's)
    PingCommand(ui);
    bool nm1 = !strcmp(sh.pingText, "Paladin >> Holy Light | Not enough mana! 8");
    *(DWORD *)(ab + 0x20) = 0;
    PingCommand(ui);
    bool nm2 = !strcmp(sh.pingText, "Paladin >> Holy Light | Not enough mana!");
    *(float *)(mine + UNIT_MANA) = 75;
    PingCommand(ui);
    CHECK(nm1 && nm2 && !strcmp(sh.pingText, "Paladin >> Holy Light | Ready!"), "mana cost 75 over 40 mana: not enough (with the seconds while cooling), 75 of 75: ready");
    *(DWORD *)(ab + 0x20) = 0x200, *(int *)(data + DATA_MANA_COST) = 0;
    // where Enter opens the chat: the Chat dialog's recipient ([[ui+0x23c]+0xc]+0x1a0)
    static BYTE chatMode[0x40], chatDlg[0x200];
    *(BYTE **)(ui + UI_CHAT_MODE) = chatMode, *(DWORD *)chatMode = (DWORD)(img + RVA_CHAT_MODE_VT);
    *(BYTE **)(chatMode + CHAT_DIALOG) = chatDlg, *(DWORD *)chatDlg = (DWORD)(img + RVA_CHAT_DIALOG_VT);
    DWORD to[4];
    for (DWORD k = 0; k < 4; k++)
        *(DWORD *)(chatDlg + DIALOG_TO) = k, *(int *)(chatDlg + DIALOG_PLAYER) = -1, PingCommand(ui), to[k] = sh.pingChat;
    *(DWORD *)(chatDlg + DIALOG_TO) = 0, *(int *)(chatDlg + DIALOG_PLAYER) = 3, PingCommand(ui);
    CHECK(to[0] == 1 && to[1] == 2 && to[2] == 3 && to[3] == 1 && sh.pingChat == 4, "the chat opens to: all (0, no player), allies (1), observers (2), all (3), one player");
    // DISPLAYMINUTES: whole seconds by default (WFE's), m:ss with it on
    char t1[12], t2[12], t3[12];
    TimeText(95, t1, sizeof(t1), false), TimeText(95, t2, sizeof(t2), true), TimeText(0.46f, t3, sizeof(t3), false);
    CHECK(!strcmp(t1, "95") && !strcmp(t2, "1:35") && !strcmp(t3, "0.5"), "95 s: \"%s\", with minutes \"%s\"; under a second \"%s\"", t1, t2, t3);
    // the cooldowns' trail in the log: what a read of the card found (cooling without the game's sweep model is counted too)
    *(BYTE **)(btn + 0x19c) = nullptr;
    float l0 = 0, t0 = 0;
    int f0 = ButtonCooldown(btn, &l0, &t0);
    *(BYTE **)(btn + 0x19c) = model;
    ReadCooldowns(ui);
    char logText[8192] = "";
    FILE *lf;
    if (!fopen_s(&lf, "allies.log", "rb"))
        logText[fread(logText, 1, sizeof(logText) - 1, lf)] = 0, fclose(lf);
    CHECK(f0 == (CD_BUTTON | CD_ABILITY | CD_COOLING) && l0 == 0 && strstr(logText, "cooldowns: the command card") && strstr(logText, "1 with an ability, 1 cooling down, 1 with the game's cooldown model"),
          "the card's read is logged (an ability, cooling, its model); cooling without the model: counted, no times read");
    *(const char **)(nameFs + FS_TEXT) = "";
    PingCommand(ui);
    CHECK(!strcmp(sh.pingText, "Holy Light | Cooldown: 8"), "no unit name: \"%s\"", sh.pingText);

    // buffs: a hero's buff takes its full time from +0xc8, another unit's from +0xc0
    static BYTE bar[0x200], bRow[16], ind[2][0x1000], buff[2][0x200], unit[2][0x300], linked[0x200], lobj[0x100];
    static BYTE *inds[2];
    DWORD *bvt = (DWORD *)(img + 0xa70000);
    bvt[0x1e8 / 4] = IntGetter(0x601000, 0), bvt[0x1c / 4] = IntGetter(0x601010, 'buff');
    DWORD *evt = (DWORD *)(img + 0xa70400);                                // the buff timer: CAgentTimerExtended-like
    evt[0x18 / 4] = FloatGetter(0x601100, 4.5f), evt[0x10 / 4] = FloatGetter(0x601200, 30);
    *(BYTE **)(panel + 0x16c) = bar, *(int *)(bar + 0x124) = 1, *(int *)(bar + 0x128) = 2;
    *(BYTE **)(bar + 0x154) = bRow, *(DWORD *)(bRow + 4) = 2, *(BYTE ***)(bRow + 8) = inds;
    for (int i = 0; i < 2; i++) {
        inds[i] = ind[i], *(DWORD *)(ind[i] + 0x90) = 1, *(DWORD *)(ind[i] + 0x94) = 1, *(BYTE **)(ind[i] + 0x978) = buff[i];
        *(DWORD *)buff[i] = (DWORD)bvt, *(DWORD *)(buff[i] + 0x84) = (DWORD)evt, *(DWORD *)(buff[i] + BUFF_ID) = 'Binf';
        *(float *)(buff[i] + 0xc0) = 20, *(float *)(buff[i] + 0xc8) = 12;
        *(BYTE **)(buff[i] + BUFF_UNIT) = unit[i], *(DWORD *)unit[i] = (DWORD)(img + RVA_UNIT_VT);
    }
    *(DWORD *)(unit[0] + 0x30) = 'Hpal', *(DWORD *)(unit[1] + 0x30) = 'hfoo';
    *(DWORD *)(flagsObj + HANDLE_TAG) = '+agl';                            // the units' own handles (the fake lookup's object) are alive
    memset(sh.buffLeft, 0, sizeof(sh.buffLeft));
    ReadBuffs(ui);
    CHECK(sh.buffCount == 2 && sh.buffLeft[0] == 4.5f && sh.buffTotal[0] == 12 && sh.buffTotal[1] == 20 && sh.buffId[0] == 'Binf',
          "a hero's buff: %.1f of %.0f (+0xc8), a footman's: of %.0f (+0xc0), the rawcode [buff+0x34]", sh.buffLeft[0], sh.buffTotal[0], sh.buffTotal[1]);
    // WFE's owner fallback: no [buff+0x30] yet -> the buff's handle +0xc: '+agl', its [+0x30], alive [+0x20] == 0, the unit [+0x54]
    static BYTE handleObj[0x100];
    *(BYTE **)(buff[0] + BUFF_UNIT) = nullptr, *(BYTE **)(flagsObj + HANDLE_OWNER) = handleObj, *(BYTE **)(handleObj + HANDLE_OBJ) = unit[0];
    ReadBuffs(ui);
    float fb1 = sh.buffTotal[0];
    *(DWORD *)(handleObj + HANDLE_DEAD) = 1;
    ReadBuffs(ui);
    float fb2 = sh.buffTotal[0];
    *(DWORD *)(handleObj + HANDLE_DEAD) = 0, *(DWORD *)(flagsObj + HANDLE_TAG) = 0;
    ReadBuffs(ui);
    float fb3 = sh.buffTotal[0];
    *(DWORD *)(flagsObj + HANDLE_TAG) = '+agl', *(BYTE **)(buff[0] + BUFF_UNIT) = unit[0];
    CHECK(fb1 == 12 && fb2 == 30 && fb3 == 30 && sh.buffLeft[0] == 4.5f,
          "no unit cached: the hero found through the buff's handle (%.0f, +0xc8); a dead or untagged handle: no unit, the timer's full time (%.0f, %.0f), still drawn", fb1, fb2, fb3);
    // a linked kind ('Bpsd'): its times come from the buff its +0x114 handle points at
    DWORD *lvt = (DWORD *)(img + 0xa70800);
    lvt[0x1e8 / 4] = bvt[0x1e8 / 4], lvt[0x1c / 4] = IntGetter(0x601020, 'Bpsd');
    DWORD *l2 = (DWORD *)(img + 0xa70c00);
    l2[0x1c / 4] = IntGetter(0x601030, 'BXXX');
    *(DWORD *)buff[1] = (DWORD)lvt, ((DWORD *)(buff[1] + BUFF_LINK))[0] = 9, ((DWORD *)(buff[1] + BUFF_LINK))[1] = 9;
    *(BYTE **)(flagsObj + 0x54) = linked, *(DWORD *)linked = (DWORD)l2;    // the lookup's object -> [+0x54]
    *(DWORD *)(linked + 0x84) = (DWORD)evt, *(float *)(linked + 0xc0) = 25, *(float *)(linked + 0xc8) = 25;
    ReadBuffs(ui);
    CHECK(sh.buffTotal[1] == 25, "a linked buff ('Bpsd'): the times of the buff it points at (%.0f)", sh.buffTotal[1]);
    // no unit: the game's own full time (+0x563650): the timer's total + the time run before a pause [+0xa4];
    // paused ([+0x48] > 0): the time left [+0xac] + [+0xa4]
    *(DWORD *)buff[1] = (DWORD)bvt, *(BYTE **)(buff[1] + BUFF_UNIT) = nullptr, *(DWORD *)(buff[1] + AGENT_HANDLE) = 0xFFFFFFFF;
    *(float *)(buff[1] + BUFF_RAN) = 3;
    ReadBuffs(ui);
    float gt1 = sh.buffTotal[1];
    *(int *)(buff[1] + BUFF_PAUSED) = 1, *(float *)(buff[1] + BUFF_PAUSED_LEFT) = 6;
    ReadBuffs(ui);
    float gt2 = sh.buffTotal[1], gl2 = sh.buffLeft[1];
    *(int *)(buff[1] + BUFF_PAUSED) = 0, *(float *)(buff[1] + BUFF_RAN) = 0, *(BYTE **)(buff[1] + BUFF_UNIT) = unit[1];
    CHECK(gt1 == 33 && gt2 == 9 && gl2 == 6, "no unit: the game's total, the timer's + [+0xa4] (%.0f); paused: [+0xac] %.0f left of %.0f", gt1, gl2, gt2);
    // Alt + click a buff (layout 34): the buff bar icon under the cursor (the game's pick) pings its buff
    *(BYTE **)(top + TOP_HOVER) = inds[0];
    *(DWORD *)bar = (DWORD)(img + 0xab0000);                              // a frame (the game's have their vtable)
    *(const char **)(nameFs + FS_TEXT) = "Paladin";
    int pb = PingCommand(ui);
    CHECK(pb == 1 && !strncmp(sh.pingText, "Paladin >> Binf | ", 18) && strstr(sh.pingText, "s left"), "a buff icon: \"%s\"", sh.pingText);
    // no pick from the game (an ally's or a boss's buttons don't take the mouse): the cursor against the button's rect
    struct Cur { static bool __cdecl At(float *x, float *y) { *x = 0.52f, *y = 0.03f; return true; } };
    g_cursorUi = Cur::At;
    float *rc = (float *)(btn + LAYOUT_RECT); rc[0] = 0.01f, rc[1] = 0.50f, rc[2] = 0.05f, rc[3] = 0.54f;
    *(BYTE **)(top + TOP_HOVER) = nullptr;
    int kind = 0;
    BYTE *hv = Hovered(ui, &kind);
    rc[1] = 0.60f, rc[3] = 0.64f;
    BYTE *hv2 = Hovered(ui, &kind);
    CHECK(hv == btn && hv2 == nullptr, "no hover from the game: the button under the cursor by its rect; elsewhere: none");
    Verdict();
    return g_fails;
}
