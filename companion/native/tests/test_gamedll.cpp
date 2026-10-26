// The module's 1.28f addresses against the real Game.dll (1.28.5.7680), if
// there's a copy here: %TWC_GAMEDLL%, or %TEMP%\twc-gamedll\Game.dll (never in
// the repo: it's the game's). The file is mapped as an image by hand (sections,
// relocations; no imports, nothing in it runs) and the module's own checks run
// on it: the functions it calls are function starts, the vtables are data with
// the RTTI names it expects, the timer getters pass the decoder, and the call
// sites it rewrites are where the in-game logs found them. Without the file:
// skipped (0 failures).
#include "../twc-game.cpp"
#include "check.h"

static BYTE *MapImage(const char *path) {
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE)
        return nullptr;
    DWORD size = GetFileSize(f, nullptr), got = 0;
    BYTE *file = (BYTE *)VirtualAlloc(nullptr, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    bool ok = file && ReadFile(f, file, size, &got, nullptr) && got == size;
    CloseHandle(f);
    if (!ok)
        return nullptr;
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)(file + ((IMAGE_DOS_HEADER *)file)->e_lfanew);
    DWORD isz = nt->OptionalHeader.SizeOfImage, pref = nt->OptionalHeader.ImageBase;
    BYTE *img = (BYTE *)VirtualAlloc((void *)pref, isz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!img)
        img = (BYTE *)VirtualAlloc(nullptr, isz, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    memcpy(img, file, nt->OptionalHeader.SizeOfHeaders);
    IMAGE_SECTION_HEADER *sec = IMAGE_FIRST_SECTION(nt);
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++)
        memcpy(img + sec[i].VirtualAddress, file + sec[i].PointerToRawData, min(sec[i].SizeOfRawData, sec[i].Misc.VirtualSize));
    DWORD delta = (DWORD)img - pref;
    IMAGE_DATA_DIRECTORY rd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
    for (DWORD o = 0; delta && o < rd.Size;) {
        IMAGE_BASE_RELOCATION *b = (IMAGE_BASE_RELOCATION *)(img + rd.VirtualAddress + o);
        if (!b->SizeOfBlock)
            break;
        WORD *e = (WORD *)(b + 1);
        for (DWORD k = 0; k < (b->SizeOfBlock - 8) / 2; k++)
            if ((e[k] >> 12) == IMAGE_REL_BASED_HIGHLOW)
                *(DWORD *)(img + b->VirtualAddress + (e[k] & 0xfff)) += delta;
        o += b->SizeOfBlock;
    }
    for (int i = 0; i < nt->FileHeader.NumberOfSections; i++) {
        DWORD c = sec[i].Characteristics, old;
        DWORD prot = (c & IMAGE_SCN_MEM_EXECUTE) ? PAGE_EXECUTE_READ : (c & IMAGE_SCN_MEM_WRITE) ? PAGE_READWRITE : PAGE_READONLY;
        VirtualProtect(img + sec[i].VirtualAddress, sec[i].Misc.VirtualSize, prot, &old);
    }
    VirtualFree(file, 0, MEM_RELEASE);
    g_imageSize = isz;
    return img;
}

static bool Rtti(DWORD rva, const char *want) {
    char n[96];
    RttiName((DWORD)(g_base + rva), g_imageSize, n, sizeof(n));
    bool ok = !PageIs(g_base + rva, EXEC) && strstr(n, want) != nullptr;
    if (!ok)
        printf("      vtable +%06lX: RTTI \"%s\", want %s\n", rva, n, want);
    return ok;
}

int main() {
    strcpy_s(g_logPath, "gamedll.log"); DeleteFileA("gamedll.log");
    static Shared sh; g_shared = &sh;
    char path[MAX_PATH];
    if (!GetEnvironmentVariableA("TWC_GAMEDLL", path, MAX_PATH)) {
        GetEnvironmentVariableA("TEMP", path, MAX_PATH);
        strcat_s(path, "\\twc-gamedll\\Game.dll");
    }
    g_base = MapImage(path);
    if (!g_base) {
        printf("skipped: no 1.28f Game.dll at %s\n", path);
        return 0;
    }
    DWORD h = 0, vn = GetFileVersionInfoSizeA(path, &h), build = 0;
    static BYTE vbuf[8192]; VS_FIXEDFILEINFO *fi = nullptr; UINT len = 0;
    if (vn && vn <= sizeof(vbuf) && GetFileVersionInfoA(path, 0, vn, vbuf) && VerQueryValueA(vbuf, "\\", (void **)&fi, &len) && fi)
        build = LOWORD(fi->dwFileVersionLS);
    CHECK(build == 7680, "the file is build %lu (1.28f is 7680)", build);

    // every function the module calls is a function start
    static const DWORD FNS[] = { RVA_GET_UI, RVA_MSG_CLEAR, RVA_LAYOUT_REFRESH, RVA_HANDLE_LOOKUP, RVA_UNIT_HP, RVA_TEXT_CTOR, RVA_TEXT_FLAGS,
        RVA_TEXT_SET, RVA_SET_FONT, RVA_SET_POINT, RVA_SET_ABS_POINT, RVA_SKIN_LOOKUP, RVA_BAR_CTOR, RVA_BAR_LEVEL, RVA_REGION_HIDE,
        RVA_REGION_SHOW, RVA_PORTRAIT_UPDATE, RVA_FONTSTRING_SET, RVA_PROJECTION, RVA_FPS_FN, RVA_OPTIONS, RVA_OPT_SET, RVA_OPT_APPLY,
        RVA_OPT_GET, RVA_CLEAR_POINTS, RVA_CONTROL_CLICK, RVA_LATENCY[0], RVA_LATENCY[1], RVA_LATENCY[2] };
    int bad = 0;
    for (DWORD f : FNS)
        if (!FnStart(f))
            bad++, printf("      +%06lX isn't a function start\n", f);
    CHECK(!bad, "all %d functions the module calls are function starts", (int)(sizeof(FNS) / sizeof(FNS[0])));

    // the vtables it checks objects against
    bool vt = Rtti(RVA_UI_VTABLE, "CGameUI") & Rtti(RVA_STATBAR_VTABLE, "CStatBar") & Rtti(RVA_TEXT_VTABLE, "CTextFrame")
        & Rtti(RVA_PORTRAIT_VTABLE, "CPortraitButton") & Rtti(RVA_FONTSTRING_VTABLE, "CSimpleFontString")
        & Rtti(RVA_COMMAND_BUTTON_VTABLE, "CCommandButton");
    CHECK(vt, "the vtables are data with the expected RTTI names");

    // the timer getters the first report refused, now 3 calls deep (and the ones that passed)
    static const DWORD GETTERS[] = { 0x8a600, 0x8a640, 0x8a130, 0x8a100, 0x451060, 0x50d620 };
    bad = 0;
    for (DWORD g : GETTERS)
        if (!WalkGetter(g_base + g, 0, GETTER_DEPTH))
            bad++, printf("      the getter +%06lX is refused (in +%06lX)\n", g, (DWORD)(g_walkBad - g_base));
    CHECK(!bad, "the timer getters pass the decoder (%d refused)", bad);

    // the call sites the module rewrites
    BYTE *sites[8];
    int n = FindCallSites(g_base + RVA_PORTRAIT_UPDATE, sites, 8);
    CHECK(n == 2 && sites[0] - g_base == 0x3f61a2 && sites[1] - g_base == 0x40ebd2, "the portrait update's 2 callers, as in game (+3F61A2, +40EBD2): %d", n);
    n = FindCallSites(g_base + RVA_PROJECTION, sites, 8);
    CHECK(n == 1 && sites[0] - g_base == RVA_PROJECTION_CALL, "the projection's one caller is +%06lX (%d found)", RVA_PROJECTION_CALL, n);
    bad = 0;
    for (DWORD l : RVA_LATENCY)
        bad += !LatencyPatchable(g_base + l);
    CHECK(!bad, "the 3 latency getters are patchable");
    CHECK(g_base[RVA_FPS_BYTE] == 0xE0, "the FPS limiter byte is the game's (%02X)", g_base[RVA_FPS_BYTE]);
    Verdict();
    return g_fails;
}
