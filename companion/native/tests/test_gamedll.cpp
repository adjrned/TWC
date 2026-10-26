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
        & Rtti(RVA_COMMAND_BUTTON_VTABLE, "CCommandButton") & Rtti(RVA_REGION_VT, "CSimpleRegion") & Rtti(RVA_TEXTURE_VT, "CSimpleTexture")
        & Rtti(RVA_SIMPLE_TOP_VT, "CSimpleTop") & Rtti(RVA_REL_POINT_VT, "") & Rtti(RVA_ABS_POINT_VT, "");
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

    // the widescreen UI's portrait text: the FontHeights lookup, and the font string fields it reads
    const char *fh = *(const char **)(g_base + RVA_FONT_HEIGHTS_NAME);
    CHECK(FnStart(RVA_FONT_HEIGHT) && PageIs(fh, READ) && !strcmp(fh, "FontHeights"), "the FontHeights lookup +%06lX, its section name at +%06lX", RVA_FONT_HEIGHT, RVA_FONT_HEIGHTS_NAME);
    static const BYTE PS_CALL[] = { 0xBA }, FS_TEXT_READ[] = { 0x8B, 0x86, 0x9C, 0, 0, 0 }, FS_A[] = { 0x88, 0x41, 0x68 }, FS_R[] = { 0x88, 0x41, 0x6B };
    const char *ps = *(const char **)(g_base + 0x40d2f1);
    CHECK(g_base[0x40d2f0] == PS_CALL[0] && PageIs(ps, READ) && !strcmp(ps, "PortraitStats") && SiteTarget(g_base + 0x40d2f7) == g_base + RVA_FONT_HEIGHT,
          "the portrait's own lines take FontHeights / PortraitStats from it (+40D2F7)");
    CHECK(!memcmp(g_base + RVA_FONTSTRING_SET + 6, FS_TEXT_READ, 6) && !memcmp(g_base + 0x141e4a, FS_A, 3) && !memcmp(g_base + 0x141e51, FS_R, 3),
          "a font string's text is at +0x9C (its setter), its colour at +0x68 A .. +0x6B R (+141E40)");

    // the widescreen UI's second batch: the frames' classes, and where the game UI stores them
    bool vt2 = Rtti(0xaad28c, "CUpperButtonBar") & Rtti(0xab20d4, "CResourceBar") & Rtti(0xab0f08, "CPeonBar") & Rtti(0xab2890, "CTimeOfDayIndicator")
        & Rtti(0xaad684, "CUberToolTipWar3") & Rtti(0xa7d2a8, "CSimpleMessageFrame") & Rtti(0xaadfc4, "CChatEditBar") & Rtti(0xab1008, "CSimpleConsole")
        & Rtti(0xaad510, "CBuffBar") & Rtti(0xaad470, "CBuffIndicator");
    CHECK(vt2, "menu bar, resource bar, idle workers, time of day, tooltip, messages, chat box, console, buff bar: the classes WFE's handlers expect");
    static const struct { DWORD at, field; } STORES[] = { { 0x39c53d, 0x3e0 }, { 0x39c189, 0x3f8 }, { 0x3a10f9, 0x1cc }, { 0x39c471, 0x3d0 }, { 0x39c439, 0x3cc } };
    bad = 0;
    for (const auto &s : STORES)
        if (g_base[s.at] != 0x89 || *(DWORD *)(g_base + s.at + 2) != s.field)
            bad++, printf("      +%06lX: %02X %02X %08lX, want a mov to +%lX\n", s.at, g_base[s.at], g_base[s.at + 1], *(DWORD *)(g_base + s.at + 2), s.field);
    CHECK(!bad, "the game UI stores them at +0x3e0 / +0x3f8 / +0x1cc / +0x3d0 / +0x3cc");

    // the button models: the sprite kinds, where their matrix is, and the buttons' model fields
    CHECK(Rtti(0xa7ac24, "CSpriteFrame") & Rtti(RVA_SPRITE_MINI_VT[0], "CSpriteMini_") & Rtti(RVA_SPRITE_MINI_VT[1], "CSpriteMini_")
        & Rtti(RVA_SPRITE_UBER_VT[0], "CSpriteUber_") & Rtti(RVA_SPRITE_UBER_VT[1], "CSpriteUber_"), "the model frame and sprite vtables");
    static const BYTE MINI_GET[] = { 0xF3, 0x0F, 0x6F, 0x41, 0x64 }, UBER_GET[] = { 0xF3, 0x0F, 0x6F, 0x81, 0x08, 0x01, 0x00, 0x00 };
    BYTE *mg = *(BYTE **)(g_base + RVA_SPRITE_MINI_VT[0] + 0x38), *ug = *(BYTE **)(g_base + RVA_SPRITE_UBER_VT[0] + 0x38);
    CHECK(mg == g_base + 0x1d39c0 && ug == g_base + 0x1d39f0 && !memcmp(mg + 6, MINI_GET, 5) && !memcmp(ug + 6, UBER_GET, 8),
          "the sprites' matrix getters (vtable +0x38) read +0x64 / +0x108");
    static const struct { DWORD at, off; } MODELS[] = { { 0x3e199e, 0x1a8 }, { 0x3e1ace, 0x19c }, { 0x3d2594, 0x1d8 } };
    bad = 0;
    for (const auto &s : MODELS)
        bad += !(g_base[s.at] == 0x89 && g_base[s.at + 1] == 0x87 && *(DWORD *)(g_base + s.at + 2) == s.off);
    CHECK(!bad && FnStart(0x3e1930) && FnStart(0x3e1a60), "the autocast / cooldown / hero point models are at +0x1a8 / +0x19c / +0x1d8");

    // detailed tooltips: the icon updates are the vtables' +0x6C, the tooltip setter, the getters and fields the lines use
    CHECK(*(DWORD *)(g_base + RVA_DAMAGE_ICON_VT + ICON_UPDATE) == (DWORD)(g_base + RVA_DAMAGE_UPDATE) && *(DWORD *)(g_base + RVA_ARMOR_ICON_VT + ICON_UPDATE) == (DWORD)(g_base + RVA_ARMOR_UPDATE)
          && Rtti(RVA_DAMAGE_ICON_VT, "CInfoPanelIconDamage") & Rtti(RVA_ARMOR_ICON_VT, "CInfoPanelIconArmor"), "the damage / armor icon updates are their vtables' entry +0x6C");
    CHECK(FnStart(RVA_DAMAGE_UPDATE) && FnStart(RVA_ARMOR_UPDATE) && FnStart(RVA_TOOLTIP_SET) && FnStart(RVA_ATTACK_COOLDOWN) && FnStart(RVA_MOVE_SPEED),
          "the updates, the tooltip setter, the cooldown and move speed getters are function starts");
    CHECK(g_base[0x409056] == 0xC2 && *(WORD *)(g_base + 0x409057) == 0x10 && g_base[0x4089ca] == 0xC2 && *(WORD *)(g_base + 0x4089cb) == 0xC,
          "the damage update pops 4 stack arguments (ret 0x10), the armor update 3 (ret 0xC): the hooks' own signatures");
    static const struct { DWORD at; const char *bytes; int n; } PIN[] = {
        { 0x408a1e, "\x8B\xBF\xE8\x01\x00\x00", 6 },          // atk = [unit+0x1e8]
        { 0x408a2c, "\x83\xBC\x9F\x88\x00\x00\x00\x00", 8 },  // [atk+i*4+0x88] != 0
        { 0x4cc9f9, "\x8D\x14\xF5\x54\x01\x00\x00", 7 },      // the cooldown getter's [atk+i*8+0x154] entries
        { 0x4087dd, "\x8B\xBF\xEC\x01\x00\x00", 6 },          // mv = [unit+0x1ec]
        { 0x409029, "\x8B\x8E\x28\x01\x00\x00", 6 }, { 0x40899d, "\x8B\x8E\x28\x01\x00\x00", 6 } };   // the tooltip frame [icon+0x128]   // the tooltip frame [icon+0x128]
    bad = 0;
    for (const auto &q : PIN)
        if (memcmp(g_base + q.at, q.bytes, q.n))
            bad++, printf("      +%06lX: not the bytes expected\n", q.at);
    CHECK(!bad && SiteTarget(g_base + 0x408ad3) == g_base + RVA_ATTACK_COOLDOWN && SiteTarget(g_base + 0x40884d) == g_base + RVA_MOVE_SPEED
          && SiteTarget(g_base + 0x409041) == g_base + RVA_TOOLTIP_SET && SiteTarget(g_base + 0x4089b5) == g_base + RVA_TOOLTIP_SET,
          "the fields and calls the lines rely on are where the game's own updates have them");

    // health bars: the set-unit entry +0x78 repaints the bar itself or through the update +0x74
    DWORD su = *(DWORD *)(g_base + RVA_STATBAR_VTABLE + STATBAR_SET_UNIT);
    CHECK(su == (DWORD)(g_base + 0x4101c0) && FnStart(0x4101c0) && g_base[0x410254] == 0xFF && g_base[0x410255] == 0x52 && g_base[0x410256] == STATBAR_UPDATE,
          "the bar's set-unit +0x78 is +4101C0, which calls the update +0x74 (+410254) or repaints on its own");
    // widescreen: the aspect the camera passes is its viewport's height / width
    static const BYTE VIEW[] = { 0xF3, 0x0F, 0x5C, 0x48, 0x04 }, VIEW2[] = { 0xF3, 0x0F, 0x5C, 0x00, 0xF3, 0x0F, 0x5E, 0xC8 };
    CHECK(!memcmp(g_base + 0x1e07f0, VIEW, 5) && !memcmp(g_base + 0x1e080e, VIEW2, 8), "the projection's aspect is (rect[3] - rect[1]) / (rect[2] - rect[0]) (+1E07F0 .. +1E0812)");

    // fast menus: the menu animation's start as the detour expects, and the glue singleton / models it reads
    CHECK(MenuAnimPatchable(g_base + RVA_MENU_ANIM), "the menu animation +%06lX starts 55 8B EC 83 EC 18 and nothing jumps into it", RVA_MENU_ANIM);
    CHECK(SiteTarget(g_base + 0x33a79e) == g_base + RVA_GLUE && g_base[0x3112c5] == 0xA1 && *(DWORD *)(g_base + 0x3112c6) == (DWORD)(g_base + DATA_GLUE)
          && g_base[0x33a7c5] == 0x81 && g_base[0x33a7c6] == 0xC3 && *(DWORD *)(g_base + 0x33a7c7) == GLUE_MODELS,
          "it takes the glue from +%06lX (kept at +%06lX) and walks its models from +0x194", RVA_GLUE, DATA_GLUE);
    Verdict();
    return g_fails;
}
