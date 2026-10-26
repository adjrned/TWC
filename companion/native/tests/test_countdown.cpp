// The game start countdown (WFE's [DELAY] GAMESTART), against a fake game image
// holding the lobby's start handler as 1.28f has it: on, its 6.0 s becomes the
// wanted seconds + 0.1 (WFE's); a new value is written over ours; off and
// RestoreAll put the game's back; bytes that aren't the game's are refused.
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, csOn) == 832 && offsetof(Shared, csGame) == 844 && sizeof(Shared) >= 848, "layout 17");

static BYTE *img;
static float Secs() { return *(float *)(img + RVA_COUNTDOWN_SECS); }

int main() {
    strcpy_s(g_logPath, "countdown.log"); DeleteFileA("countdown.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    // +0x324100 .. +0x324150, the game's bytes (push esi .. ret 4); its two calls point at +0x2dd7d0, +0x35fcc0 and +0x86a3e0
    static const BYTE FN[] = {
        0x56, 0x8B, 0xF1, 0x6A, 0x00, 0x8B, 0x8E, 0xF8, 0x01, 0x00, 0x00, 0xE8, 0, 0, 0, 0,             // +0x324100
        0x6A, 0x00, 0x56, 0x6A, 0x02, 0x51, 0x8D, 0x8E, 0xC0, 0x01, 0x00, 0x00, 0xC7, 0x04, 0x24,       // +0x324110
        0x00, 0x00, 0x80, 0x3F, 0xE8, 0, 0, 0, 0, 0x8B, 0x8E, 0x68, 0x01, 0x00, 0x00, 0xE8, 0, 0, 0, 0, // +0x32411f
        0x85, 0xC0, 0x74, 0x18,
        0x6A, 0x00, 0x56, 0x6A, 0x03, 0x51, 0x8D, 0x8E, 0xDC, 0x01, 0x00, 0x00, 0xC7, 0x04, 0x24,       // +0x324137
        0x00, 0x00, 0xC0, 0x40, 0xE8, 0, 0, 0, 0, 0x5E, 0xC2, 0x04, 0x00 };                               // +0x324146
    BYTE *f = img + RVA_COUNTDOWN;
    f[-1] = 0xCC;
    memcpy(f, FN, sizeof(FN));
    auto call = [&](DWORD at, DWORD to) { *(LONG *)(img + at + 1) = (LONG)((img + to) - (img + at + 5)); };
    call(0x32410b, 0x2dd7d0), call(0x324123, 0x86a3e0), call(0x32412e, 0x35fcc0), call(0x32414a, RVA_TIMER_START);
    CHECK(CountdownFloat() == (float *)(img + RVA_COUNTDOWN_SECS) && Secs() == 6.0f, "the fake handler as 1.28f has it: the countdown's 6.0 found");

    sh.csOn = 1; sh.csSecs = 0; CountdownPass();
    CHECK(fabsf(Secs() - 0.1f) < 1e-6f && sh.csState == 1 && sh.csGame == 6.0f, "on, 0 s: %.2f (WFE's GAMESTART + 0.1), the game's own %.1f logged", Secs(), sh.csGame);
    sh.csSecs = 2.5f; CountdownPass();
    CHECK(fabsf(Secs() - 2.6f) < 1e-6f && sh.csState == 1, "2.5 s: %.2f, written over ours", Secs());
    sh.csSecs = 99; CountdownPass();
    CHECK(fabsf(Secs() - 6.1f) < 1e-6f, "at most 6 s (%.2f)", Secs());
    sh.csOn = 0; CountdownPass();
    CHECK(Secs() == 6.0f && sh.csState == 0, "off: the game's 6.0 again");
    sh.csOn = 1; sh.csSecs = 1; CountdownPass();
    RestoreAll();
    CHECK(Secs() == 6.0f && !g_csSet, "unload (RestoreAll): the game's 6.0 again");
    // someone else's bytes there: refused, nothing written
    g_csSet = 0; img[0x32413a] = 0x04;                      // the timer's id isn't 3
    CountdownPass();
    CHECK(Secs() == 6.0f && sh.csState == 3, "the bytes around it aren't the game's: refused (state %lu), nothing written", sh.csState);
    Verdict();
    return g_fails;
}
