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
    BuffAppearedLog(now + 300);
    CHECK(!LogHas("'B04Q' aura appeared"), "not logged before the 0.6 s after it is in");
    BuffAppearedLog(now + 700);
    CHECK(LogHas("'B04Q' aura appeared (4.0 s of 4.0)") && LogHas("30.00 s one-shot") && LogHas("0.03 s periodic"), "then logged with the timers started around it (30 s one-shot, 0.03 s periodic)");
    BuffAppeared(unit, 'B04Q', true, 3.5f, 4, now + 800), BuffAppearedLog(now + 2000);
    CHECK(!g_bsNew[0].id, "the same buff seen again soon after: not a new one");
    CHECK(TimerStartWatch(false) && !g_tsHooked && !memcmp(f, body, 5), "off: the game's bytes back");
    Start(5, 0);
    CHECK(starts == 4 && g_tsN == 2, "and nothing noted");
    f[0] = 0xE9; g_tsBad = false;
    CHECK(!TimerStartWatch(true) && !g_tsHooked && g_tsBad, "another mod's bytes there: refused");
    Verdict();
    return g_fails;
}
