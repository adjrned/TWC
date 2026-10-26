// The shared memory layout, for the companion: engine\GameLayout.ahk holds
// every Shared field's offset (class Shm), and the AHK side reads and writes
// through those names, never through numbers of its own.
//   test_layout.exe          checks GameLayout.ahk is what Shared is now
//   test_layout.exe write    writes it (after a change to Shared)
// The list below can't drift from Shared: each field must start where the
// one before ends and the last must end at sizeof(Shared), so a field left
// out (or a new one) fails, and a renamed one doesn't build.
#include "../twc-game.cpp"
#include "check.h"
#include <string>

#define FIELDS(X) X(magic) X(layout) X(build) X(status) X(heartbeat) X(targeting) X(probe) X(ui) X(qcSeq) X(qcUntil) \
    X(qcFlags) X(qcDone) X(qcResult) X(qcMs) X(probeText) X(tmWant) X(tmSeq) X(tmFlags) X(cdLeft) X(cdTotal) X(buffCount) \
    X(buffLeft) X(buffTotal) X(buffFlags) X(buffId) X(cmdSeq) X(cmd) X(cmdDone) X(cmdResult) X(hbOn) X(hbHeight) X(hbWidth) \
    X(hbState) X(hbDefHeight) X(hbDefWidth) X(hbCount) X(hcOn) X(hcMode) X(hcColours) X(hcState) X(wsOn) X(wsState) X(fpsOn) \
    X(fpsLimit) X(fpsState) X(fpsGameLimit) X(scHeld) X(scState) X(scCount) X(cmdArg) X(latOn) X(latMs) X(latState) X(latGame) \
    X(uiHide) X(uiState) X(stState) X(itOn) X(itState) X(frCount) X(hnOn) X(hnMode) X(hnState) X(mbOn) X(mbHeight) X(mbState) \
    X(hnCount) X(mbCount) X(itemLeft) X(itemTotal) X(prOn) X(prMode) X(prState) X(mbWidth) X(unload) X(stamp) X(ulOn) X(ulState) X(ulCount)

struct Field { const char *name; size_t off, size; };
#define ENTRY(f) { #f, offsetof(Shared, f), sizeof(((Shared *)0)->f) },
static const Field LIST[] = { FIELDS(ENTRY) };

static std::string Ahk() {
    std::string s =
        "#Requires AutoHotkey v2.0\r\n"
        "; ============================================================================\r\n"
        ";  Shm - where each field of the game module's shared memory is (byte\r\n"
        ";  offsets into \"Local\\TWC_Game_<pid>\"; Shared in native\\twc-game.cpp).\r\n"
        ";  WRITTEN BY native\\tests\\test_layout.exe write - don't edit by hand;\r\n"
        ";  run-tests.bat fails when it's out of date.\r\n"
        "; ============================================================================\r\n"
        "class Shm {\r\n";
    char line[96];
    for (const Field &f : LIST) {
        sprintf_s(line, "    static %s := %u\r\n", f.name, (unsigned)f.off);
        s += line;
    }
    sprintf_s(line, "    static size := %u\r\n", (unsigned)sizeof(Shared));
    s += line;
    s += "}\r\n";
    return s;
}

int main(int argc, char **argv) {
    size_t end = 0;
    int gaps = 0;
    for (const Field &f : LIST) {
        if (f.off != end)
            printf("  %s is at %u, the field before it ends at %u\n", f.name, (unsigned)f.off, (unsigned)end), gaps++;
        end = f.off + f.size;
    }
    CHECK(!gaps && end == sizeof(Shared), "the list covers Shared field by field (%u bytes, %d fields)", (unsigned)sizeof(Shared), (int)(sizeof(LIST) / sizeof(LIST[0])));
    const char *path = "..\\..\\..\\engine\\GameLayout.ahk";      // from native\tests\obj
    std::string want = Ahk();
    if (argc > 1 && !strcmp(argv[1], "write")) {
        FILE *f;
        CHECK(!fopen_s(&f, path, "wb") && fwrite(want.data(), 1, want.size(), f) == want.size() && !fclose(f), "wrote engine\\GameLayout.ahk");
    } else {
        std::string have;
        FILE *f;
        if (!fopen_s(&f, path, "rb")) {
            char b[4096];
            size_t n;
            while ((n = fread(b, 1, sizeof(b), f)) > 0)
                have.append(b, n);
            fclose(f);
        }
        CHECK(have == want, "engine\\GameLayout.ahk matches Shared (if not: obj\\test_layout.exe write, from native\\tests)");
    }
    Verdict();
    return g_fails;
}
