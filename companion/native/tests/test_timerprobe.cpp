// The buff timers' probe, against a fake game image: CTimerWar3's start (+0x27c160, 1.28f's prologue)
// detoured, each start noted (when, timeout, periodic) and passed on to the game's own; a buff first
// seen is logged with the map timers started around it; off: the game's bytes back; another mod's
// bytes there: refused.
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img;
static int starts;
static float lastTimeout;
// the game's own body, after its prologue (the fake's own push ebp / esi / edi are popped first)
static void __fastcall FakeTimerBody(void *timer, int, float *timeout, int periodic, void *code) { starts++, lastTimeout = *timeout; }
static void Start(float secs, int periodic) {
    float t = secs;
    ((TimerStartFn)(g_base + RVA_MAP_TIMER_START))((void *)0x1234, 0, &t, periodic, nullptr);
}
static bool LogHas(const char *s) {
    FILE *f;
    if (fopen_s(&f, "timerprobe.log", "rb"))
        return false;
    static char buf[1 << 16];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    return strstr(buf, s) != nullptr;
}

int main() {
    strcpy_s(g_logPath, "timerprobe.log"); DeleteFileA("timerprobe.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    BYTE *f = img + RVA_MAP_TIMER_START;
    static const BYTE body[] = { 0x55, 0x8B, 0xEC, 0x56, 0x57, 0x5F, 0x5E, 0x5D, 0xE9 };    // the prologue, then pop edi / esi / ebp; jmp
    f[-1] = 0xCC, memcpy(f, body, sizeof(body));
    *(LONG *)(f + 9) = (LONG)((BYTE *)FakeTimerBody - (f + 13));

    Start(5, 0);
    CHECK(starts == 1 && !g_tsN, "off: the game's own start, nothing noted");
    CHECK(TimerStartWatch(true) && g_tsHooked && f[0] == 0xE9, "on: +27C160 detoured");
    BYTE unit[4];
    DWORD now = GetTickCount();
    Start(0.03f, 1), Start(30, 0);
    BuffAppeared(unit, 'B04Q', true, 4, 4, now);
    CHECK(starts == 3 && lastTimeout == 30 && g_tsN == 2, "each start noted and passed on to the game's own (%d starts, last %.0f s)", starts, lastTimeout);
    BuffAppearedLog(now + 600);
    CHECK(!LogHas("'B04Q' aura appeared"), "not logged before the 1 s after it is in");
    BuffAppearedLog(now + 1200);
    CHECK(LogHas("'B04Q' aura appeared (4.0 s of 4.0)") && LogHas("30.00 s one-shot") && !LogHas("0.03 s periodic") && LogHas("1 shorter left out"),
          "then logged with the timers of 0.5 s or more started around it (30 s one-shot; the 0.03 s one left out)");
    BuffAppeared(unit, 'B04Q', true, 3.5f, 4, now + 800), BuffAppearedLog(now + 2000);
    CHECK(!g_bsNew[0].id, "the same buff seen again soon after: not a new one");
    // the map's timer of a buff: a 10 s one-shot started with it, the 30 s one a cooldown on the card, a 0.5 s one too short
    static BYTE timer10[0x40], timer30[0x40];
    static BYTE fakeTimerVt[0x40];
    *(DWORD *)(timer10 + 0x24) = (DWORD)(img + RVA_AGENT_TIMER_VT[0]);
    *(DWORD *)(img + RVA_AGENT_TIMER_VT[0] + 0x18) = (DWORD)(img + 0x200000);
    static float remain = 7.5f;
    // the agent timer's time left getter, thiscall(timer, float *out), ret 4 (as TimerValue calls it)
    BYTE *g = img + 0x200000; g[-1] = 0xCC;
    BYTE code[] = { 0x8B, 0x44, 0x24, 0x04, 0x8B, 0x15, 0, 0, 0, 0, 0x89, 0x10, 0xC2, 0x04, 0x00 };   // mov eax, [esp+4]; mov edx, [&remain]; mov [eax], edx; ret 4
    *(DWORD *)(code + 6) = (DWORD)&remain;
    memcpy(g, code, sizeof(code));
    sh.cdTotal[3] = 30;
    DWORD t1 = GetTickCount() + 5000;
    auto Note = [&](float t, void *tm, DWORD at, void *code = nullptr) { TimerStartRec &r = g_tsRing[(InterlockedIncrement(&g_tsN) - 1) & 4095]; r = { at, t, 0, tm, code }; };
    Note(30, timer30, t1 - 40), Note(10, timer10, t1 - 32, (void *)0x111), Note(0.5f, timer30, t1 - 20);
    BuffAppeared(unit, 'B04Q', true, 4, 4, t1);
    float ml = 0, mt = 0;
    bool got = BuffMapLeft(unit, 'B04Q', &ml, &mt);
    CHECK(got && mt == 10 && ml == 7.5f && LogHas("'B04Q' goes with the map's 10.00 s timer"), "a buff's map timer: the 10 s one (the 30 s one as long as a cooldown, the 0.5 s one too short): %.1f of %.0f s left", ml, mt);
    remain = 0;
    CHECK(!BuffMapLeft(unit, 'B04Q', &ml, &mt), "its timer run out: none");
    DWORD t2 = t1 + 5000;
    Note(12, timer10, t2 - 30), Note(20, timer30, t2 - 30);
    BuffAppeared(unit, 'B0XX', true, 4, 4, t2);
    CHECK(!BuffMapLeft(unit, 'B0XX', &ml, &mt) && LogHas("'B0XX': no map timer of its own (2 lengths"), "two lengths started with it: no guess");
    // two items at once: B04Q (seen alone: callback 0x111, 10 s) and B0YY (seen alone: 0x222, 20 s), their timers started together
    static BYTE timerA[0x40], timerB[0x40];
    *(DWORD *)(timerA + 0x24) = *(DWORD *)(timerB + 0x24) = (DWORD)(img + RVA_AGENT_TIMER_VT[0]);
    remain = 6;
    DWORD t3 = t2 + 5000;
    Note(20, timerB, t3 - 3000, (void *)0x222);                          // B0YY alone once: learned
    BuffAppeared(unit, 'B0YY', true, 4, 4, t3 - 2990);
    for (BuffMapTimer &m : g_bmt) m.id = 0;                              // both run out
    // both items used at once: both buffs new in the same read, both timers started 30 ms before
    for (BuffMapTimer &m : g_bmt) m.id = 0;
    DWORD t4 = t3 + 5000;
    Note(20, timerB, t4 - 30, (void *)0x222), Note(10, timerA, t4 - 30, (void *)0x111);
    BuffAppeared(unit, 'B0YY', true, 4, 4, t4), BuffAppeared(unit, 'B04Q', true, 4, 4, t4);
    float la = 0, ta = 0, lb = 0, tb = 0;
    bool a = BuffMapLeft(unit, 'B04Q', &la, &ta), bb = BuffMapLeft(unit, 'B0YY', &lb, &tb);
    CHECK(a && ta == 10 && bb && tb == 20 && LogHas("by its callback"), "two items at once: each buff its own timer by its callback (B04Q %.0f s, B0YY %.0f s)", ta, tb);
    // a buff not seen alone yet among two: no guess
    for (BuffMapTimer &m : g_bmt) m.id = 0;
    DWORD t5 = t4 + 5000;
    Note(20, timerB, t5 - 30, (void *)0x333), Note(10, timerA, t5 - 30, (void *)0x444);
    BuffAppeared(unit, 'B0ZZ', true, 4, 4, t5);
    CHECK(!BuffMapLeft(unit, 'B0ZZ', &la, &ta) && LogHas("'B0ZZ': no map timer of its own (2 lengths") && LogHas("not seen alone yet"), "one never seen alone, among two: no guess");
    DWORD t6 = t5 + 5000;
    Note(8, timerA, t6 - 30, (void *)0x555);
    BuffAppeared(unit, 'B0BU', false, 0, 9999, t6);
    CHECK(!BuffMapLeft(unit, 'B0BU', &la, &ta), "a buff (not an aura: its own time, a 9999 s passive): no map timer");
    CHECK(BuffSlotDrawn(1 | 2 | 4 | 8) && !BuffSlotDrawn(1 | 2 | 4) && BuffSlotDrawn(1), "drawn with its map timer even as an aura kept up; not without it");
    CHECK(TimerStartWatch(false) && !g_tsHooked && !memcmp(f, body, 5), "off: the game's bytes back");
    LONG noted = g_tsN;
    Start(5, 0);
    CHECK(starts == 4 && g_tsN == noted, "and nothing noted");
    f[0] = 0xE9; g_tsBad = false;
    CHECK(!TimerStartWatch(true) && !g_tsHooked && g_tsBad, "another mod's bytes there: refused");
    Verdict();
    return g_fails;
}
