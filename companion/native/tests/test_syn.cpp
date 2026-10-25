#include "../twc-game.cpp"
#include "check.h"
int main() {
    BYTE *img = (BYTE *)VirtualAlloc(nullptr, 0x2000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x2000; static Shared sh; g_shared = &sh; strcpy_s(g_logPath, "syn.log");
    // g at +0x100: mov eax,[0x...]; fld dword ptr [eax+0x10]; ret
    BYTE g[] = { 0xA1, 0, 0x10, 0, 0, 0xD9, 0x40, 0x10, 0xC3 };
    // f at +0x000: push esi; mov esi,[esp+8]; call g; fsubr dword ptr [ecx+0xC]; fstp dword ptr [esi]; pop esi; test eax,eax; jle +2; xor eax,eax; ret 4
    BYTE f[] = { 0x56, 0x8B, 0x74, 0x24, 0x08, 0xE8, 0,0,0,0, 0xD8, 0x69, 0x0C, 0xD9, 0x1E, 0x5E, 0x85, 0xC0, 0x7E, 0x02, 0x33, 0xC0, 0xC2, 0x04, 0x00 };
    memcpy(img + 0x100, g, sizeof(g)); memcpy(img, f, sizeof(f));
    *(LONG *)(img + 6) = 0x100 - 10;
    CHECK(WalkGetter(img, 0), "a getter calling a getter passes");
    // h at +0x200: mov eax,[ecx]; call dword ptr [eax+8]; ret
    BYTE h[] = { 0x8B, 0x01, 0xFF, 0x50, 0x08, 0xC3 }; memcpy(img + 0x200, h, sizeof(h));
    CHECK(!WalkGetter(img + 0x200, 0), "a virtual call is refused");
    // k at +0x300: call f (f itself calls g): two levels deep
    BYTE k[] = { 0xE8, 0,0,0,0, 0xC3 }; memcpy(img + 0x300, k, sizeof(k)); *(LONG *)(img + 0x301) = 0 - 0x305;
    CHECK(!WalkGetter(img + 0x300, 0), "two levels deep is refused");
    Verdict();
    return g_fails;
}
