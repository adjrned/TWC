// StormCheckAt against a fake Storm image: SMemAlloc / SMemFree are taken only
// when ordinals 401 / 403 look like the 1.28f Storm.dll's (their first bytes
// are that file's, with the pushed name pointers moved to the fake image).
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, stState) == 684, "layout 11");

static BYTE *FakeStorm(DWORD stamp) {
    BYTE *s = (BYTE *)VirtualAlloc(nullptr, 0x62000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)s;
    dos->e_magic = IMAGE_DOS_SIGNATURE, dos->e_lfanew = 0x80;
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)(s + 0x80);
    nt->Signature = IMAGE_NT_SIGNATURE, nt->FileHeader.TimeDateStamp = stamp, nt->OptionalHeader.SizeOfImage = 0x62000;
    // Storm.dll 1.28f, ordinal 401 (RVA 0x2bc10) and 403 (0x2c220), first bytes
    static const BYTE A[] = { 0x55, 0x8b, 0xec, 0x51, 0x83, 0x3d, 0x2c, 0x80, 0x05, 0x15, 0x00, 0x75, 0x29, 0x6a, 0x01, 0x6a,
                              0x00, 0x6a, 0x00, 0x6a, 0xff, 0x68, 0xc8, 0x4b, 0x04, 0x15, 0x68, 0x7d, 0x00, 0x10, 0x85, 0xc7 };
    static const BYTE F[] = { 0x55, 0x8b, 0xec, 0x83, 0x3d, 0x2c, 0x80, 0x05, 0x15, 0x00, 0x75, 0x30, 0x68, 0x7d, 0x00, 0x10,
                              0x85, 0xe8, 0xca, 0x13, 0xff, 0xff, 0x83, 0x3d, 0x38, 0x84, 0x05, 0x15, 0x00, 0x74, 0x17, 0x6a,
                              0x01, 0x6a, 0x01, 0x6a, 0x00, 0x6a, 0xff, 0x68, 0x70, 0x4c, 0x04, 0x15, 0x68, 0x7d, 0x00, 0x10 };
    memcpy(s + 0x2bc10, A, sizeof(A));
    memcpy(s + 0x2c220, F, sizeof(F));
    strcpy_s((char *)s + 0x44bc8, 16, "SMemAlloc()");
    strcpy_s((char *)s + 0x44c70, 16, "SMemFree()");
    *(DWORD *)(s + 0x2bc10 + 0x16) = (DWORD)(s + 0x44bc8);      // the relocated push immediates
    *(DWORD *)(s + 0x2c220 + 0x28) = (DWORD)(s + 0x44c70);
    return s;
}

int main() {
    strcpy_s(g_logPath, "storm.log"); DeleteFileA("storm.log");
    static Shared sh; g_shared = &sh;
    g_base = (BYTE *)VirtualAlloc(nullptr, 0x10000, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    BYTE *s = FakeStorm(STORM_128F_STAMP);
    CHECK(StormCheckAt(nullptr, nullptr, nullptr) == 2 && !g_smemAlloc, "no Storm.dll in the game: 2, nothing taken");
    CHECK(StormCheckAt(g_base, s + 0x2bc10, s + 0x2c220) == 3 && !g_smemAlloc, "the game module itself: refused");
    CHECK(StormCheckAt(s, s + 0x2c220, s + 0x2bc10) == 3 && !g_smemAlloc, "401 / 403 swapped: refused");
    s[0x44bc8] = 'X';
    CHECK(StormCheckAt(s, s + 0x2bc10, s + 0x2c220) == 3 && !g_smemAlloc, "401 pushes another name: refused");
    s[0x44bc8] = 'S';
    *(DWORD *)(s + 0x2bc10 + 0x16) = (DWORD)g_base;
    CHECK(StormCheckAt(s, s + 0x2bc10, s + 0x2c220) == 3 && !g_smemAlloc, "401's name pointer outside Storm: refused");
    *(DWORD *)(s + 0x2bc10 + 0x16) = (DWORD)(s + 0x44bc8);
    CHECK(StormCheckAt(s, s + 0x2bc10, s + 0x2c220) == 1 && g_smemAlloc == (SMemAllocFn)(s + 0x2bc10) && g_smemFree == (SMemFreeFn)(s + 0x2c220),
        "the 1.28f functions: 1, SMemAlloc / SMemFree taken");
    g_smemAlloc = nullptr, g_smemFree = nullptr;
    BYTE *s2 = FakeStorm(0x12345678);
    CHECK(StormCheckAt(s2, s2 + 0x2bc10, s2 + 0x2c220) == 1 && g_smemAlloc, "another build with the same functions: used");
    char log[4096] = ""; FILE *f; if (!fopen_s(&f, "storm.log", "r")) { fread(log, 1, sizeof(log) - 1, f); fclose(f); }
    CHECK(strstr(log, "(the 1.28f Storm.dll)") && strstr(log, "(not the known 1.28f build)"), "the log tells the known build from another");
    Verdict();
    return g_fails;
}
