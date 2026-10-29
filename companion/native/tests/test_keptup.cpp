// Buffs kept up (BuffKeptUp), from simulated reads 10 a second: an aura refreshed on a beat
// shows no seconds while in range and its real time left once the refreshes stop; a plain
// buff always shows its seconds, one cast again by hand too; a buff given again on a beat is
// kept up once the beat is seen twice; each unit's buff on its own.
#include "../twc-game.cpp"
#include "check.h"

static BYTE unitA[4], unitB[4];
// a buff of `full` seconds refreshed every `beat` ms from `from` until `until` (0: never), read at `now`
static float Left(DWORD now, float full, DWORD beat, DWORD from, DWORD until) {
    DWORD last = from;
    if (beat)
        for (DWORD r = from; r <= now && (!until || r <= until); r += beat)
            last = r;
    float l = full - (now - last) / 1000.0f;
    return l > 0 ? l : 0;
}

int main() {
    const DWORD T0 = 100000;
    // an aura of 2 s refreshed every second for 10 s, then out of range
    int keptIn = 0, readsIn = 0, firstOut = -1;
    float leftAtOut = 0;
    for (DWORD t = T0; t < T0 + 14000; t += 100) {
        float l = Left(t, 2, 1000, T0, T0 + 10000);
        bool k = l > 0 && BuffKeptUp(unitA, 'BOae', true, l, t);
        if (t < T0 + 10000)
            readsIn++, keptIn += k;
        else if (!k && l > 0 && firstOut < 0)
            firstOut = (int)(t - T0 - 10000), leftAtOut = l;
    }
    CHECK(keptIn == readsIn, "an aura refreshed every 1 s: kept up at every read in range (%d of %d)", keptIn, readsIn);
    CHECK(firstOut >= 1000 && firstOut <= 1500 && leftAtOut > 0 && leftAtOut <= 1.0f,
          "out of range: its seconds once a beat and 0.4 s pass with no refresh (%d ms after the last), %.1f s left", firstOut, leftAtOut);
    // a plain 30 s buff: never kept up
    int kept = 0;
    for (DWORD t = T0; t < T0 + 30000; t += 100)
        kept += BuffKeptUp(unitA, 'Binf', false, Left(t, 30, 0, T0, 0), t);
    CHECK(!kept, "a 30 s buff: its seconds all along (%d reads kept up)", kept);
    // cast again by hand at 10 s (one jump): still its seconds
    kept = 0;
    for (DWORD t = T0; t < T0 + 30000; t += 100)
        kept += BuffKeptUp(unitA, 'Brej', false, Left(t, 12, 10000, T0, T0 + 10000), t);
    CHECK(!kept, "a buff cast again by hand once: its seconds all along (%d)", kept);
    // the map gives a buff again every 2 s: kept up once two beats agree, from the third refresh on
    int early = 0, late = 0, lateReads = 0;
    for (DWORD t = T0; t < T0 + 12000; t += 100) {
        bool k = BuffKeptUp(unitA, 'Bmap', false, Left(t, 3, 2000, T0, 0), t);
        if (t < T0 + 6000)
            early += k;
        else
            late += k, lateReads++;
    }
    CHECK(!early && late == lateReads, "a buff given again every 2 s: its seconds until two beats agree (the third refresh, 6 s), then kept up (%d early, %d of %d after)", early, late, lateReads);
    // the same aura on two units: one leaves the range, the other stays
    int aOut = 0, bOut = 0;
    for (DWORD t = T0; t < T0 + 8000; t += 100) {
        float la = Left(t, 2, 1000, T0, T0 + 3000), lb = Left(t, 2, 1000, T0, 0);
        bool ka = la > 0 && BuffKeptUp(unitA, 'BHad', true, la, t), kb = BuffKeptUp(unitB, 'BHad', true, lb, t);
        aOut += la > 0 && !ka, bOut += !kb;
    }
    CHECK(aOut > 0 && !bOut, "two units, one aura: the one out of range gets its seconds (%d reads), the other none (%d)", aOut, bOut);
    // an aura of 4 s seen for the first time and never refreshed (its beat not known): kept up its first 2.5 s, then its seconds
    int in = 0, out = 0;
    for (DWORD t = T0 + 50000; t < T0 + 54000; t += 100) {
        bool k = BuffKeptUp(unitB, 'BUau', true, Left(t, 4, 0, T0 + 50000, 0), t);
        t < T0 + 52500 ? in += k : out += !k;
    }
    CHECK(in == 25 && out == 15, "a new aura never refreshed: kept up its first 2.5 s (%d of 25), then its seconds (%d of 15)", in, out);
    Verdict();
    return g_fails;
}
