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

// does the vtable's class have base at offset 0 (its RTTI class hierarchy: base class descriptors, mdisp +8)
static bool BaseAt0(DWORD vt, const char *base) {
    DWORD col = *(DWORD *)(g_base + vt - 4), chd = *(DWORD *)(col + 16), n = *(DWORD *)(chd + 8), arr = *(DWORD *)(chd + 12);
    for (DWORD i = 0; i < n && i < 16; i++) {
        DWORD bcd = ((DWORD *)arr)[i], td = *(DWORD *)bcd;
        if (strstr((const char *)td + 8, base) && *(int *)(bcd + 8) == 0)
            return true;
    }
    return false;
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

    // health bar colours: the game state is [+0xd305e0] itself (the game: mov ecx, [it]; movzx eax, word [ecx+0x28]), players at +0x58
    CHECK(g_base[0x22b560] == 0x8B && g_base[0x22b561] == 0x0D && *(DWORD *)(g_base + 0x22b562) == (DWORD)(g_base + RVA_PLAYERS)
          && g_base[0x22b567] == 0x0F && g_base[0x22b568] == 0xB7 && g_base[0x22b569] == 0x41 && g_base[0x22b56a] == 0x28
          && g_base[0x21372f] == 0x8B && g_base[0x213730] == 0x44 && g_base[0x213731] == 0x81 && g_base[0x213732] == 0x58,
          "the local player is word [[+0xD305E0]+0x28] (one deref, +22B560), players [state+0x58+4i] (+21372F)");
    // RenderEdge_Widescreen's two hooks are where the module looks for them (the game's own bytes here: no other mod)
    char who[64];
    CHECK(FnStart(RVA_UNIT_BAR_WORK) && SiteTarget(g_base + 0x688f65) == g_base + RVA_UNIT_BAR_WORK && !ForeignDetour(RVA_UNIT_BAR_WORK, who, sizeof(who))
          && !ForeignDetour(RVA_PROJECTION, who, sizeof(who)), "the unit bar work +3C6700 (called from +688F65) and the projection: the game's own bytes");
    // health bars: the unit list and the extra unit as the game reads them (count [+0xd328f4], units [+0xd328f8];
    // [+0xd32900] is the unit itself: mov eax, [it]; ... call [vt+0x1c] on it; inc [eax+4])
    CHECK(g_base[0x3c6542] == 0xA1 && *(DWORD *)(g_base + 0x3c6543) == (DWORD)(g_base + RVA_UNIT_LIST + 4)
          && g_base[0x3c6558] == 0x8B && g_base[0x3c6559] == 0x0D && *(DWORD *)(g_base + 0x3c655a) == (DWORD)(g_base + RVA_UNIT_LIST + 8)
          && g_base[0x3c64ff] == 0xA1 && *(DWORD *)(g_base + 0x3c6500) == (DWORD)(g_base + RVA_UNIT_EXTRA)
          && !memcmp(g_base + 0x3c6520, "\x8B\x4D\xEC\x8B\xD8\x8B\x11\xFF\x52\x1C", 10) && !memcmp(g_base + 0x3c653f, "\xFF\x40\x04", 3),
          "the unit list (count +4, units +8) and the extra unit [+D32900] read as the game does (+3C64FF..+3C655A: one deref)");
    // the bar work +0x3c6700 sets each health bar's width for its unit (+0x13fce0 writes +0x58) right before the
    // bar's set-unit (+0x3c68ab) or update (+0x3c6912): the two return addresses the width multiplier waits for
    static const BYTE SETW[] = { 0xF3, 0x0F, 0x11, 0x41, 0x58 };
    CHECK(!memcmp(g_base + 0x13fce8, SETW, 5) && SiteTarget(g_base + 0x3c689e) == g_base + 0x13fce0 && SiteTarget(g_base + 0x3c6905) == g_base + 0x13fce0
          && !memcmp(g_base + RVA_BAR_WIDTH_SET_UNIT_RET - 3, "\xFF\x50\x78", 3) && !memcmp(g_base + RVA_BAR_WIDTH_UPDATE_RET - 3, "\xFF\x50\x74", 3)
          && *(DWORD *)(g_base + 0x3c67f5) == 0x3b83126f && SiteTarget(g_base + 0x3c67f9) == g_base + 0x13fb40,
          "the bar work sets the width (+3C689E / +3C6905) before calling +0x78 / +0x74 (returns +%06lX / +%06lX); the height 0.004 only once (+3C67F9)",
          RVA_BAR_WIDTH_SET_UNIT_RET, RVA_BAR_WIDTH_UPDATE_RET);
    // the stack sizes of every game function the module calls or wraps directly (not through GameCall): each pops what the module's type says
    // (the last ret of each, found with capstone: every ret in each function pops the same; rets.py in %TEMP%\twc-re)
    static const struct { DWORD rva, ret; WORD pops; } RETS[] = {
        { RVA_GET_UI, 0x3a0bf5, 0 }, { RVA_MSG_CLEAR, 0x14480a, 0 }, { RVA_LAYOUT_REFRESH, 0x13fa22, 4 }, { RVA_UNIT_HP, 0x81b97, 4 },
        { RVA_HANDLE_LOOKUP, 0x7e0fd, 0 }, { RVA_OPTIONS, 0x6bf93, 0 }, { RVA_OPT_SET, 0x6dc1b, 8 }, { RVA_OPT_APPLY, 0x6b459, 4 },
        { RVA_OPT_GET, 0x6c0b1, 8 }, { RVA_REGION_HIDE, 0x141cfa, 0 }, { RVA_REGION_SHOW, 0x141e9a, 0 }, { RVA_CONTROL_CLICK, 0x1407ea, 4 },
        { RVA_PROJECTION, 0x1555f1, 16 }, { RVA_MENU_ANIM, 0x33a8ae, 16 }, { RVA_PORTRAIT_UPDATE, 0x40d834, 0 }, { RVA_DAMAGE_UPDATE, 0x409056, 16 },
        { RVA_ARMOR_UPDATE, 0x4089ca, 12 }, { 0x4101c0, 0x41038f, 4 }, { 0x40ecb0, 0x40eeb1, 4 }, { 0x13b940, 0x13b9b1, 0 }, { 0x13c390, 0x13c429, 0 },
        { 0x3dcb80, 0x3dcbfb, 4 }, { 0x141d00, 0x141d81, 0 }, { 0x13d7f0, 0x13d85f, 4 }, { RVA_TIMER_EVENT, 0x2727fc, 4 }, { RVA_SPELL_EFFECT, 0x6b112e, 4 } };
    bad = 0;
    for (const auto &q : RETS) {
        const BYTE *r = g_base + q.ret;
        bool ok = FnStart(q.rva) && (q.pops ? r[0] == 0xC2 && *(const WORD *)(r + 1) == q.pops : r[0] == 0xC3);
        if (!ok)
            bad++, printf("      +%06lX: its ret at +%06lX isn't one that pops %u\n", q.rva, q.ret, q.pops);
    }
    CHECK(!bad, "every directly called / wrapped game function pops what the module's signature says (%d)", (int)(sizeof(RETS) / sizeof(RETS[0])));
    CHECK(*(DWORD *)(g_base + RVA_STATBAR_VTABLE + STATBAR_UPDATE) == (DWORD)(g_base + 0x40ecb0) && *(DWORD *)(g_base + RVA_STATBAR_VTABLE + BAR_HIDE) == (DWORD)(g_base + 0x13b940)
          && *(DWORD *)(g_base + RVA_STATBAR_VTABLE + BAR_SHOW) == (DWORD)(g_base + 0x13c390) && *(DWORD *)(g_base + RVA_STATBAR_VTABLE + BAR_DTOR) == (DWORD)(g_base + 0x3dcb80)
          && *(DWORD *)(g_base + RVA_TEXTURE_VT + 0x24) == (DWORD)(g_base + 0x141d00) && *(DWORD *)(g_base + RVA_COMMAND_BUTTON_VTABLE + BTN_CLICK) == (DWORD)(g_base + 0x13d7f0),
          "the bar's update / hide / show / dtor, a texture's +0x24 and a command button's +0x6C are those functions");
    CHECK(*(DWORD *)(g_base + RVA_BUFF_BAR_VT + 0x64) == (DWORD)(g_base + 0x13b940) && *(DWORD *)(g_base + RVA_BUFF_BAR_VT + 0x68) == (DWORD)(g_base + 0x13c390),
          "Hide the UI's buff bar: CBuffBar's +0x64 / +0x68 are the simple frame's hide / show (no stack arguments)");
    // UiStillHidden: the hides do nothing when it's so already: the simple frame's tests [+0x94] 0 first, the
    // CFrame's [+0xb0] bit 1 (and sets it); the time of day's own +0xd0 (+0x125800) ends in the CFrame's
    CHECK(!memcmp(g_base + 0x13b943, "\x83\xBF\x94\x00\x00\x00\x00\x74", 8) && !memcmp(g_base + 0x13b97f, "\xC7\x87\x94\x00\x00\x00\x00\x00\x00\x00", 10)
          && !memcmp(g_base + 0x11c6d3, "\x8B\x87\xB0\x00\x00\x00\xA8\x01\x75", 9) && SiteTarget(g_base + 0x12582f) == g_base + 0x11c6d0 && g_base[0x12582f] == 0xE9,
          "Hide the UI's still-hidden test: a simple frame's hide returns on [+0x94] 0, a CFrame's on [+0xB0] bit 1 (the time of day's too)");
    // the damage meter's feed: CUnit's vtable +0x120 is +6CF530 (thiscall, ret 0x10), which writes what was dealt to *[ebp+8]
    // (its invulnerable exit: 0 there, +6CF548..+6CF553); UnitDamageTarget +24AE80 makes the record with +6D6F80 (source
    // [+0] = its 3rd argument, the amount [+0x10] = *1st) and calls vt+0x120 with (&dealt, &record, 0, 0)
    CHECK(Rtti(RVA_UNIT_VT, "CUnit") && *(DWORD *)(g_base + RVA_UNIT_VT + UNIT_DAMAGE_SLOT) == (DWORD)(g_base + RVA_UNIT_DAMAGE)
          && !memcmp(g_base + RVA_UNIT_DAMAGE, "\x55\x8B\xEC", 3) && !memcmp(g_base + 0x6cf558, "\xC2\x10\x00", 3)
          && !memcmp(g_base + 0x6cf548, "\x8B\x45\x08\x8B\x0D", 5) && !memcmp(g_base + 0x6cf553, "\x89\x08", 2)
          && SiteTarget(g_base + 0x24aeef) == g_base + 0x6d6f80 && !memcmp(g_base + 0x6d6f91, "\x8B\x45\x10\x89\x01", 5) && !memcmp(g_base + 0x6d6f83, "\x8B\x45\x08\x8B\x00\x89\x41\x10", 8)
          && !memcmp(g_base + 0x24af01, "\x8D\x4D\xFC\x51\x8B\xCE\xFF\x92\x20\x01\x00\x00", 12),
          "the damage feed: CUnit's +0x120 is +6CF530 (ret 0x10, *dealt written), the record's source [+0] and amount [+0x10]");
    // the damage meter's causes: CTimerWar3's event entry (vtable +A8EFB4 slot +0xC, its only pointer) is +2727E0: 0x80204 (the
    // expiry its agent timer posts, +27C19D) and 0x80272 both run +272860, which fires the timer's trigger [+0x40] (+22ABF0);
    // GetSpellAbilityId reads the trigger context's slot 6 (+235FC0 -> +2BB780: [ctx + 16 * slot + 0x98] entries at [+0x9C], the
    // last one), the context [state+0x1C] (+2135F0)
    CHECK(Rtti(RVA_TIMER_VT, "CTimerWar3") && *(DWORD *)(g_base + RVA_TIMER_VT + TIMER_EVENT_SLOT) == (DWORD)(g_base + RVA_TIMER_EVENT)
          && !memcmp(g_base + RVA_TIMER_EVENT, "\x55\x8B\xEC\x56\x8B\xF1", 6) && !memcmp(g_base + 0x2727ec, "\x2D\x04\x02\x08\x00", 5) && !memcmp(g_base + 0x2727f3, "\x83\xE8\x6E", 3)
          && SiteTarget(g_base + 0x272802) == g_base + 0x272860 && SiteTarget(g_base + 0x27281b) == g_base + 0x272860
          && !memcmp(g_base + 0x2728b0, "\x8B\x4E\x40", 3) && SiteTarget(g_base + 0x2728c5) == g_base + 0x22abf0
          && !memcmp(g_base + 0x27c19d, "\x68\x04\x02\x08\x00", 5) && SiteTarget(g_base + 0x27c1a3) == g_base + 0x08a520,
          "map timers: CTimerWar3's +0xC is +2727E0 (its expiry 0x80204 / 0x80272 -> +272860, the trigger at [+0x40]), posted by the start +27C160");
    CHECK(SiteTarget(g_base + RVA_SPELL_ABILITY_ID) == g_base + 0x235fc0 && !memcmp(g_base + 0x235fcb, "\x6A\x06", 2) && SiteTarget(g_base + 0x235fcf) == g_base + 0x2bb780
          && !memcmp(g_base + 0x2bb786, "\x03\xC0\x8B\x94\xC1\x98\x00\x00\x00", 9) && !memcmp(g_base + 0x2bb793, "\x8B\x84\xC1\x9C\x00\x00\x00\x8B\x44\x90\xFC", 11)
          && !memcmp(g_base + 0x2135f0, "\x83\x79\x1C\x00", 4),
          "the running trigger's event: slot 6 of the context [state+0x1C], its last entry (as GetSpellAbilityId reads it)");
    // the boss timers' feed: the units' SPELL_EFFECT +6B0FC0 (thiscall(unit, ability), ret 4: edi the unit, the unit event
    // 0x80323 and the player event 0x80312 asked for listeners), called from 3 places with ecx the ability's owner [+0x30]
    // and the ability pushed; an ability's rawcode [+0x34] (GetSpellAbilityId's +6B82D9)
    CHECK(!memcmp(g_base + RVA_SPELL_EFFECT, "\x55\x8B\xEC\x6A\xFF", 5) && !memcmp(g_base + 0x6b0feb, "\x8B\xF9", 2)
          && !memcmp(g_base + 0x6b0ff2, "\x68\x23\x03\x08\x00", 5) && !memcmp(g_base + 0x6b1009, "\x68\x12\x03\x08\x00", 5)
          && g_base[BC_SITES[0]] == 0xE8 && SiteTarget(g_base + BC_SITES[0]) == g_base + RVA_SPELL_EFFECT && !memcmp(g_base + 0x42cd18, "\x8B\x47\x30", 3) && !memcmp(g_base + 0x42cd24, "\x57\x8B\xC8", 3)
          && g_base[BC_SITES[1]] == 0xE8 && SiteTarget(g_base + BC_SITES[1]) == g_base + RVA_SPELL_EFFECT && !memcmp(g_base + 0x43f491, "\x8B\x7E\x30", 3) && !memcmp(g_base + 0x43f4a1, "\x56\x8B\xCF", 3)
          && g_base[BC_SITES[2]] == 0xE8 && SiteTarget(g_base + BC_SITES[2]) == g_base + RVA_SPELL_EFFECT && !memcmp(g_base + 0x595a65, "\x8B\x46\x30", 3) && !memcmp(g_base + 0x595a73, "\x56\x8B\xC8", 3)
          && !memcmp(g_base + 0x6b82d9, "\x8B\x40\x34", 3) && FindCallSites(g_base + RVA_SPELL_EFFECT, nullptr, 0) == 3,
          "SPELL_EFFECT: +6B0FC0 (the unit, the ability; events 0x80323 / 0x80312), its only 3 calls with the ability's owner and the ability; the rawcode at +0x34");
    // layout 33's hit details: the ctor's 2nd argument -> [+0x14], 4th -> [+0xc], 5th -> [+4]; UnitDamageTarget passes
    // 1 << damage type (cl = its 7th), flags 0x100 (attack) | 1 (ranged), then writes the attack type (its 6th) at [+0x20]
    CHECK(!memcmp(g_base + 0x6d6f8b, "\x8B\x45\x0C\x89\x41\x14", 6) && !memcmp(g_base + 0x6d6f96, "\x8B\x45\x18\x89\x41\x04", 6) && !memcmp(g_base + 0x6d6f9c, "\x8B\x45\x14\x89\x41\x0C", 6)
          && !memcmp(g_base + 0x24aea9, "\x8B\x4D\x20", 3) && !memcmp(g_base + 0x24aee1, "\xB8\x01\x00\x00\x00\xD3\xE0", 7) && !memcmp(g_base + 0x24aeca, "\xC7\x45\xFC\x00\x01\x00\x00", 7)
          && !memcmp(g_base + 0x24aeb5, "\x8B\x5D\x1C", 3) && !memcmp(g_base + 0x24aee8, "\x8D\x4D\xD8", 3) && !memcmp(g_base + 0x24aefb, "\x89\x5D\xF8", 3),
          "the record: [+0x14] 1 << damage type, [+0xc] attack / ranged, [+4] weapon, [+0x20] attack type (record at ebp-0x28, written at ebp-8)");
    // the unit types' names: GetUnitName +236570 -> +3782B0 fastcall([unit+0x30], 0), field "name", else "Default string"
    CHECK(!memcmp(g_base + 0x236581, "\x8B\x48\x30\x33\xD2\xE8", 6) && SiteTarget(g_base + 0x236586) == g_base + RVA_OBJECT_NAME && FnStart(RVA_OBJECT_NAME)
          && !memcmp(g_base + RVA_OBJECT_NAME, "\x56\x8B\xF2\xBA", 4) && !strcmp(*(const char **)(g_base + RVA_OBJECT_NAME + 4), "name")
          && g_base[0x3782d6] == 0xB8 && !strcmp(*(const char **)(g_base + 0x3782d7), "Default string"),
          "unit type names: GetUnitName's lookup +3782B0 (the 'name' field, 'Default string' without one)");
    // allies' cards: the card fill +3FAD60 pushes +3E4020 (makes the buttons: +6B2650, ret 4) at +3FAE04 and +3E4060 (updates: +6B2700)
    // at +3FAE1A; both test control (+6A2D90) first
    CHECK(g_base[RVA_ABILITY_MAKE_PUSH] == 0x68 && *(DWORD *)(g_base + RVA_ABILITY_MAKE_PUSH + 1) == (DWORD)(g_base + RVA_ABILITY_MAKE_CB)
          && SiteTarget(g_base + 0x3e4041) == g_base + RVA_CONTROLS && SiteTarget(g_base + 0x3e404d) == g_base + RVA_ABILITY_MAKE
          && SiteTarget(g_base + 0x3e4081) == g_base + RVA_CONTROLS && SiteTarget(g_base + 0x3e408d) == g_base + RVA_ABILITY_DISPLAY
          && FnStart(RVA_ABILITY_MAKE) && !memcmp(g_base + 0x6b26ca, "\xC2\x04\x00", 3) && !memcmp(g_base + 0x6b26a8, "\xFF\x90\xC0\x01\x00\x00", 6),
          "the card's two callbacks: +3E4020 (pushed at +3FAE04) makes the buttons through +6B2650 (vt+0x1C0), +3E4060 updates (+6B2700), each after the control test");
    // stats pings: the info panel icons (RTTI, their update entries +0x6c), the text font strings they write (+40C6E0 on
    // [fs+0x9c]: armor [+0x130] / [+0x134], the hero's [+0x12c] / [+0x130] / [+0x134]), shown [+0x94]; the hero level
    // (+6B92E0: [unit+0x1f0]'s counter +0x6c, +0805A0: the lookup of its pair [+8] / [+0xc], [+0x78], then + 1)
    CHECK(Rtti(RVA_ICON_DAMAGE_VT, "CInfoPanelIconDamage") && Rtti(RVA_ICON_ARMOR_VT, "CInfoPanelIconArmor") && Rtti(RVA_ICON_HERO_VT, "CInfoPanelIconHero")
          && *(DWORD *)(g_base + RVA_ICON_HERO_VT + 0x6c) == (DWORD)(g_base + 0x409290) && *(DWORD *)(g_base + RVA_ICON_ARMOR_VT + 0x6c) == (DWORD)(g_base + 0x4083a0)
          && !memcmp(g_base + 0x4083cd, "\x83\xBE\x94\x00\x00\x00\x00", 7)
          && !memcmp(g_base + 0x4085f0, "\x8B\x8E\x30\x01\x00\x00", 6) && SiteTarget(g_base + 0x4085fc) == g_base + 0x40c6e0
          && !memcmp(g_base + 0x40862e, "\x8B\x8E\x34\x01\x00\x00", 6) && !memcmp(g_base + 0x4093c3, "\x8B\xB3\x2C\x01\x00\x00", 6)
          && !memcmp(g_base + 0x4094df, "\x8B\xB3\x30\x01\x00\x00", 6) && !memcmp(g_base + 0x4095fc, "\x8B\xB3\x34\x01\x00\x00", 6)
          && !memcmp(g_base + 0x40c6f9, "\x8B\x87\x9C\x00\x00\x00", 6)
          && !memcmp(g_base + 0x6b92e0, "\x8B\x81\xF0\x01\x00\x00\x85\xC0\x74\x0A\x8D\x48\x6C\xE8", 14) && SiteTarget(g_base + 0x6b92ed) == g_base + 0x0805a0
          && !memcmp(g_base + 0x0805a0, "\x8B\x51\x0C\x8B\x49\x08\xE8", 7) && SiteTarget(g_base + 0x0805a6) == g_base + RVA_HANDLE_LOOKUP
          && !memcmp(g_base + 0x0805ab, "\x8B\x40\x78\xC3", 4) && SiteTarget(g_base + 0x232af0) == g_base + 0x6b92e0,
          "stats pings: the icons' classes and text fields, shown [+0x94]; the hero level as GetHeroLevel reads it");
    // a spell hit's ability (layout 34): GetSpellAbilityId +235000 (registered at +23AFC7) asks the event id (+235FC0: the game
    // state's trigger context +2135F0 = [state+0x1c], made when 0; slot 6 of its stack +2BB780: [ctx + slot*16 + 0x98] entries at
    // [+0x9c]); a spell event is 272 + 0..0x15; cdecl, ret 0
    CHECK(!memcmp(g_base + 0x23afc7, "\xB9", 1) && *(DWORD *)(g_base + 0x23afc8) == (DWORD)(g_base + RVA_SPELL_ABILITY_ID) && FnStart(RVA_SPELL_ABILITY_ID)
          && SiteTarget(g_base + RVA_SPELL_ABILITY_ID) == g_base + 0x235fc0 && !memcmp(g_base + 0x235005, "\x05\xF0\xFE\xFF\xFF\x83\xF8\x15", 8)
          && !memcmp(g_base + 0x235fc0, "\x8B\x0D", 2) && *(DWORD *)(g_base + 0x235fc2) == (DWORD)(g_base + RVA_PLAYERS) && SiteTarget(g_base + 0x235fc6) == g_base + 0x2135f0
          && !memcmp(g_base + 0x235fcb, "\x6A\x06", 2) && SiteTarget(g_base + 0x235fcf) == g_base + 0x2bb780
          && !memcmp(g_base + 0x2135f0, "\x83\x79\x1C\x00", 4) && !memcmp(g_base + 0x2bb788, "\x8B\x94\xC1\x98\x00\x00\x00", 7) && g_base[0x235041] == 0xC3,
          "GetSpellAbilityId +235000: the event id from the trigger context [state+0x1c]'s stack, spell events 272-293, cdecl");
    // the map's text lines: the 3 DisplayText natives call the game UI's +3A8EB0 (thiscall, 5 arguments, ret 0x14)
    bool mtSites = true;
    for (DWORD rva : MT_SITES)
        mtSites = mtSites && g_base[rva] == 0xE8 && SiteTarget(g_base + rva) == g_base + RVA_UI_TEXT;
    CHECK(mtSites && FnStart(RVA_UI_TEXT) && !memcmp(g_base + 0x3a8ef8, "\xC2\x14\x00", 3) && SiteTarget(g_base + 0x22ffcc) == g_base + RVA_GET_UI
          && SiteTarget(g_base + 0x23011c) == g_base + RVA_GET_UI && SiteTarget(g_base + 0x230096) == g_base + RVA_GET_UI,
          "map text: +22FFD3, +23009D, +230123 call +3A8EB0 (ret 0x14) on the game UI");
    // the players' names: GetPlayerName +233F70 -> +29A990 (the slot byte [+0x30]), the string at +0x24 read by +98510 ([[+8]+0x1C])
    CHECK(SiteTarget(g_base + 0x233f85) == g_base + 0x29a990 && !memcmp(g_base + 0x29a9a4, "\x8D\x4F\x24\xE8", 4) && SiteTarget(g_base + 0x29a9a7) == g_base + 0x98510
          && !memcmp(g_base + 0x98510, "\x8B\x41\x08\x85\xC0\x74\x04\x8B\x40\x1C\xC3", 11) && !memcmp(g_base + 0x29a9ca, "\x0F\xB6\x47\x30", 4),
          "the players' names: GetPlayerName's string at CPlayer +0x24, its text [[+8]+0x1C], the slot byte +0x30");
    // why the first name is kept: SetPlayerName +246550 writes that same string (lea ecx, [esi+0x24]); GetPlayerColor +233ED0 reads [+0x264]
    CHECK(!memcmp(g_base + 0x24656b, "\x8D\x4E\x24\xE8", 4) && SiteTarget(g_base + 0x24656e) == g_base + 0x98130 && !memcmp(g_base + 0x233ee1, "\x8B\x80\x64\x02\x00\x00", 6) && PLAYER_COLOUR == 0x264,
          "SetPlayerName rewrites CPlayer +0x24 (the map's renames), GetPlayerColor reads +0x264");
    // the buff timers' probe: TimerStart +2492F0 calls CTimerWar3's start +27C160 (timer, &timeout, periodic, code), ret 0xC, 5-byte prologue
    CHECK(SiteTarget(g_base + 0x24930a) == g_base + RVA_MAP_TIMER_START && SiteTarget(g_base + 0x272922) == g_base + RVA_MAP_TIMER_START
          && !memcmp(g_base + RVA_MAP_TIMER_START, "\x55\x8B\xEC\x56\x57", 5) && !memcmp(g_base + 0x27c1ab, "\xC2\x0C\x00", 3)
          && !memcmp(g_base + 0x2492ff, "\xFF\x75\x14\x8B\xC8\xFF\x75\x10\xFF\x75\x0C", 11),
          "the map's timer start: +27C160 (from TimerStart and +272922), its 5-byte prologue, ret 0xC, (&timeout, periodic, code)");
    // the start countdown: the lobby's start handler +0x324100 (its one caller +0x322458) starts timer 3 with 6.0 s at +0x324146
    float *cs = CountdownFloat();
    CHECK(cs == (float *)(g_base + RVA_COUNTDOWN_SECS) && *cs == 6.0f && SiteTarget(g_base + 0x322458) == g_base + RVA_COUNTDOWN && FnStart(RVA_TIMER_START),
          "the start countdown's 6.0 s at +%06lX, in the handler +%06lX the lobby calls (+322458)", RVA_COUNTDOWN_SECS, RVA_COUNTDOWN);
    // allies' abilities: the observer-view function's start as the detour copies it, its 24 callers, the callback's one push
    BYTE *sites2[32];
    int nsees = FindCallSites(g_base + RVA_SEES_ALL, sites2, 32);
    CHECK(AlliesPatchable() && nsees == 24 && g_base[0x39ea4e] == 0x8B && g_base[0x39ea4f] == 0xCE && g_base[0x3a0554] == 0x8B && g_base[0x3a0555] == 0xCE,
          "+6BFFD0 starts push esi; mov esi, [state] (24 callers, each with the unit in ecx, e.g. +39EA4E / +3A0554); the callback +3E4060 is pushed at +3FAE1A only");
    CHECK(g_base[0x6c0010] == 0xC3 && g_base[0x6c0017] == 0xC3 && g_base[0x3e406a] == 0xC3 && g_base[0x6b276a] == 0xC2 && *(WORD *)(g_base + 0x6b276b) == 4
          && g_base[0x3e4081] == 0xE8 && SiteTarget(g_base + 0x3e4081) == g_base + RVA_CONTROLS && SiteTarget(g_base + 0x3e408d) == g_base + RVA_ABILITY_DISPLAY
          && *(DWORD *)(g_base + 0x3e407d) == (DWORD)(g_base + DATA_ABILITY_DEFAULT),
          "both return with no stack arguments, the display update pops 4; the callback updates only after the control test, else [+B68800]");
    // +6A2D90 is "the local player controls the unit in ecx" (+6A2DA0(ecx, local), the owner [+0x58] first), and the
    // callback passes it the unit (+3E4061 mov edi, ecx .. +3E4081); a command button's click (vt+0x6C, from its mouse
    // handlers +13D9AA) ends in +3C6B60, which does nothing unless the player controls the selection's active unit
    static const BYTE CT_MOV[] = { 0x8B, 0xF1 }, CT_OWNER[] = { 0x3B, 0x7E, 0x58 }, GATE[] = { 0x8B, 0x48, 0x34 }, GATE2[] = { 0x8B, 0xC8 };
    CHECK(SiteTarget(g_base + 0x6a2d9a) == g_base + 0x6a2da0 && g_base[0x6a2d9f] == 0xC3 && !memcmp(g_base + 0x6a2db7, CT_MOV, 2) && !memcmp(g_base + 0x6a2de4, CT_OWNER, 3)
          && !memcmp(g_base + 0x3e4061, "\x8B\xF9", 2) && g_base[0x3e408b] == 0x8B && g_base[0x3e408c] == 0xCF
          && *(DWORD *)(g_base + RVA_COMMAND_BUTTON_VTABLE + 0x50) == (DWORD)(g_base + 0x13d950) && !memcmp(g_base + 0x13d9aa, "\xFF\x50\x6C", 3)
          && SiteTarget(g_base + 0x3c6b72) == g_base + 0x213720 && !memcmp(g_base + 0x3c6b77, GATE, 3) && SiteTarget(g_base + 0x3c6b7a) == g_base + 0x2c24a0
          && !memcmp(g_base + 0x2c24a0, "\x8B\x81\xE0\x01\x00\x00\xC3", 7) && !memcmp(g_base + 0x3c6b8c, GATE2, 2) && SiteTarget(g_base + 0x3c6b8e) == g_base + RVA_CONTROLS
          && g_base[0x3c6b95] == 0x74 && PLAYER_SELECTION == 0x34 && SELECTION_ACTIVE == 0x1e0 && RVA_BUTTON_CLICK == 0x13d7f0,
          "+6A2D90 tests control of the unit in ecx; a card click is dropped by the game unless you control the active unit [[player+0x34]+0x1E0]");
    CHECK(Rtti(RVA_UNIT_VT, "CUnit") && *(DWORD *)(g_base + RVA_UNIT_VT + 0xec) == (DWORD)(g_base + 0x6b9f30) && !memcmp(g_base + 0x6b9f30, "\x8B\x41\x58\xC3", 4),
          "CUnit's vtable +B68914: its owner (vt+0xEC) is [unit+0x58]");
    // the ping: CSimpleTop [+D0F948] (its getter +13B920) keeps the frame under the cursor at +0x16C (+13A320)
    CHECK(g_base[0x13b920] == 0xA1 && *(DWORD *)(g_base + 0x13b921) == (DWORD)(g_base + RVA_SIMPLE_TOP) && !memcmp(g_base + 0x13a320, "\x89\x9F\x6C\x01\x00\x00", 6)
          && Rtti(RVA_SIMPLE_TOP_VT, "CSimpleTop"), "the frame under the cursor: [[+D0F948]+0x16C] (set by the mouse-move pass +13A320)");
    // the ping's "Not enough mana!": the button data's [+0x594] is the tooltip's first cost (+3FE008 -> +4002B0), which sets
    // the flag +0x164 (+40031B) that +40DC7A draws with icon 0 of +AAC684: 'ToolTipManaIcon'
    static const BYTE MC_PUSH[] = { 0xFF, 0xB1, 0x94, 0x05, 0, 0 }, MC_FLAG[] = { 0xC7, 0x87, 0x64, 0x01, 0, 0, 1, 0, 0, 0 }, MC_LEA[] = { 0x8D, 0x83, 0x64, 0x01, 0, 0 };
    CHECK(DATA_MANA_COST == 0x594 && !memcmp(g_base + 0x3fe008, MC_PUSH, 6) && SiteTarget(g_base + 0x3fe011) == g_base + 0x4002b0 && !memcmp(g_base + 0x4002ed, "\x8B\x45\x0C", 3)
          && !memcmp(g_base + 0x40031b, MC_FLAG, 10) && !memcmp(g_base + 0x40dc49, MC_LEA, 6) && *(DWORD *)(g_base + 0x40dc7d) == (DWORD)(g_base + 0xaac684)
          && *(DWORD *)(g_base + 0xaac684) == (DWORD)(g_base + 0xaacce8) && !strcmp((const char *)g_base + 0xaacce8, "ToolTipManaIcon"),
          "the button data's +0x594 is the mana cost the tooltip shows (its first cost: the flag +0x164, icon ToolTipManaIcon)");
    // an agent's unit: the game's ability code reads [+0x30], else +7F820 (the handle +0xC / +0x10, '+agl', [+0x30], alive [+0x20] == 0, [+0x54]); mana = +81B30 on unit+0xB8
    static const BYTE OW_FN[] = { 0x8B, 0x51, 0x10, 0x8B, 0x49, 0x0C }, OW_TAG[] = { 0x81, 0x79, 0x0C, 0x6C, 0x67, 0x61, 0x2B }, OW_MANA[] = { 0x8D, 0x88, 0xB8, 0, 0, 0 };
    CHECK(!memcmp(g_base + 0x460914, "\x8B\x46\x30", 3) && SiteTarget(g_base + 0x46091d) == g_base + 0x7f820 && !memcmp(g_base + 0x460926, OW_MANA, 6) && SiteTarget(g_base + 0x46092c) == g_base + RVA_UNIT_HP
          && !memcmp(g_base + 0x7f820, OW_FN, 6) && SiteTarget(g_base + 0x7f826) == g_base + RVA_HANDLE_LOOKUP && !memcmp(g_base + 0x7f833, OW_TAG, 7)
          && !memcmp(g_base + 0x7f83d, "\x8B\x40\x30", 3) && !memcmp(g_base + 0x7f844, "\x83\x78\x20\x00", 4) && !memcmp(g_base + 0x7f84a, "\x8B\x40\x54", 3)
          && AGENT_OWNER == 0x30 && AGENT_HANDLE == 0xc && UNIT_MANA == 0xb8, "an ability's unit is [+0x30], else from its handle (+7F820, done by hand); its mana +81B30(unit+0xB8)");
    // where Enter opens the chat: [ui+0x23C] is the CChatMode (+3A4250), its [+0xC] the CChatDialog (+3D10C8), whose [+0x1A0] starts as all (3),
    // observers (2) or allies (1) (+3D0B7B..), read by +3EA100; the bar's show +3E3890 takes Ctrl (key 1) as allies first
    static const BYTE CM_STORE[] = { 0x89, 0xBE, 0x3C, 0x02, 0, 0 }, CD_ALL[] = { 0xC7, 0x87, 0xA0, 0x01, 0, 0, 3, 0, 0, 0 }, CD_ALLY[] = { 0xC7, 0x87, 0xA0, 0x01, 0, 0, 1, 0, 0, 0 };
    CHECK(!memcmp(g_base + 0x3a4250, CM_STORE, 6) && SiteTarget(g_base + 0x3a4224) == g_base + 0x3d1060 && *(DWORD *)(g_base + 0x3d1098) == (DWORD)(g_base + RVA_CHAT_MODE_VT)
          && *(DWORD *)(g_base + 0x3d10bf) == (DWORD)(g_base + 0xaa9948) && !strcmp((const char *)g_base + 0xaa9948, "ChatDialog") && !memcmp(g_base + 0x3d10c8, "\x89\x46\x0C", 3)
          && *(DWORD *)(g_base + 0x3d0b59) == (DWORD)(g_base + RVA_CHAT_DIALOG_VT) && !memcmp(g_base + 0x3d0b7b, CD_ALL, 10) && !memcmp(g_base + 0x3d0bf7, CD_ALLY, 10)
          && !memcmp(g_base + 0x3ea100, "\x8B\x91\xA0\x01\x00\x00", 6) && Rtti(RVA_CHAT_MODE_VT, "CChatMode") && Rtti(RVA_CHAT_DIALOG_VT, "CChatDialog")
          && !memcmp(g_base + 0x3e38f9, "\xB9\x01\x00\x00\x00", 5) && SiteTarget(g_base + 0x3e38fe) == g_base + 0x9cdd0 && SiteTarget(g_base + 0x3e3924) == g_base + 0x404600,
          "the chat opens to the Chat dialog's recipient ([[ui+0x23C]+0xC]+0x1A0, allies when you have one), Ctrl: allies");
    // the number badge: SetNumber +4034B0 makes it (+3E1CB0: the frame [btn+0x194] at +3E1D1A, the number [btn+0x198] at +3E1E69)
    // and shows the frame (our sweep's frame is made the same way); the region hide takes a shown region ([r+0x7C] bit 1) out of
    // its frame [r+0x74] (our squares are hidden with it)
    static const BYTE BG_FRAME[] = { 0x89, 0x86, 0x94, 0x01, 0, 0 }, BG_NUM[] = { 0x89, 0xBE, 0x98, 0x01, 0, 0 }, RH[] = { 0xF6, 0x46, 0x7C, 0x01 };
    CHECK(SiteTarget(g_base + 0x4034e1) == g_base + 0x3e1cb0 && !memcmp(g_base + 0x3e1d1a, BG_FRAME, 6) && !memcmp(g_base + 0x3e1e69, BG_NUM, 6)
          && *(DWORD *)(g_base + 0x4034f1) == (DWORD)(g_base + 0xa702a0) && !strcmp((const char *)g_base + 0xa702a0, "%d") && !memcmp(g_base + 0x141ce3, RH, 4)
          && !memcmp(g_base + 0x141cec, "\x8B\x4E\x74", 3),
          "the command button's number badge [+0x194] ('%%d' into [+0x198]); the region hide works on [r+0x7C] / [r+0x74]");
    // our cooldown sweep's frame and squares, made as the badge is: a CSimpleFrame (+13AE90(mem, parent), ret 4, vtable +A7CC14 at +13AEBE), CSimpleTextures
    // (+141FE0(mem, frame, 2, 1), ret 12, vtable +A7D13C at +142019; the badge's at +3E1D86..+3E1D92), SetTexture (path, 0) ret 8,
    // SetAllPoints ret 8, SetPoint ret 24, the width / height setters writing the layout's +0x58 / +0x5C then refreshing
    static const BYTE TX_CALL[] = { 0x6A, 0x01, 0x6A, 0x02, 0xFF, 0xB6, 0x94, 0x01, 0, 0, 0x8B, 0xC8 }, SW[] = { 0xF3, 0x0F, 0x11, 0x41, 0x58 }, SH2[] = { 0xF3, 0x0F, 0x11, 0x41, 0x5C };
    const BYTE *rb[] = { g_base + 0x13b04b, g_base + 0x142158, g_base + 0x143804, g_base + 0x13fb3a, g_base + 0x13fc92 };
    static const WORD rp[] = { 4, 12, 8, 8, 24 };
    bool retsOk = true;
    for (int i = 0; i < 5; i++)
        retsOk = retsOk && rb[i][0] == 0xC2 && *(const WORD *)(rb[i] + 1) == rp[i];
    CHECK(retsOk && *(DWORD *)(g_base + 0x13aec0) == (DWORD)(g_base + RVA_SIMPLEFRAME_VT) && *(DWORD *)(g_base + 0x14201b) == (DWORD)(g_base + SWEEP_TEXTURE_VT)
          && Rtti(RVA_SIMPLEFRAME_VT, "CSimpleFrame") && Rtti(SWEEP_TEXTURE_VT, "CSimpleTexture") && !memcmp(g_base + 0x3e1d86, TX_CALL, 12) && SiteTarget(g_base + 0x3e1d92) == g_base + RVA_TEXTURE_CTOR
          && SiteTarget(g_base + 0x3e1d03) == g_base + RVA_SIMPLEFRAME_CTOR && !memcmp(g_base + RVA_SET_WIDTH + 8, SW, 5) && !memcmp(g_base + RVA_SET_HEIGHT + 8, SH2, 5)
          && *(DWORD *)(g_base + RVA_SIMPLEFRAME_VT + 0x68) == (DWORD)(g_base + 0x13c390),
          "the sweep's frame and textures are made as the game makes the badge's; their setters' stack sizes and fields");
    // the sweep's size: a layout's rect is y first: bottom +0x44, left +0x48, top +0x4C, right +0x50. A grid's vt+0 (+13CC90) takes
    // the rect's [+4]..[+0xC] span over its column count [+0x128] (the cells' width) and [+0]..[+8] over its rows [+0x124]; +13BC72 pairs
    // the rect's +4 / +0xC with the frame's +0x48 / +0x50 (+13F690 compares the same fields). And a frame given a parent is drawn
    // one level over it (+13C30A: [parent+0x84] + 1)
    CHECK(!memcmp(g_base + 0x13f6b6, "\xF3\x0F\x10\x79\x4C", 5) && !memcmp(g_base + 0x13f6c3, "\xF3\x0F\x10\x71\x50", 5)
          && !memcmp(g_base + 0x13f6c8, "\xF3\x0F\x5C\x79\x44", 5) && !memcmp(g_base + 0x13f6cd, "\xF3\x0F\x5C\x71\x48", 5) && LAYOUT_RECT == 0x44
          && !memcmp(g_base + 0x13ccb1, "\x8B\x87\x28\x01\x00\x00", 6) && !memcmp(g_base + 0x13ccdd, "\xF3\x0F\x58\x46\x04", 5)
          && !memcmp(g_base + 0x13ccea, "\xF3\x0F\x10\x46\x0C", 5) && !memcmp(g_base + 0x13cd13, "\xF3\x0F\x58\x06", 4)
          && !memcmp(g_base + 0x13bc72, "\xF3\x0F\x10\x47\x50", 5) && !memcmp(g_base + 0x13bc79, "\xF3\x0F\x5C\x47\x48", 5)
          && !memcmp(g_base + 0x13bc7e, "\xF3\x0F\x10\x4E\x0C", 5) && !memcmp(g_base + 0x13bc83, "\xF3\x0F\x5C\x4E\x04", 5)
          && !memcmp(g_base + 0x13c30a, "\x8B\x81\x84\x00\x00\x00\x40\x89\x86\x84\x00\x00\x00", 13) && SiteTarget(g_base + 0x13afeb) == g_base + 0x13c2d0,
          "a layout's rect at +0x44..+0x50, y first (+0x48 / +0x50 are the x span: the grid's columns); a new simple frame's level is its parent's + 1 (over the button's icon)");
    // buffs: the rawcode [buff+0x34] (the game looks the buff's data up with it), its unit [+0x30]
    CHECK(!memcmp(g_base + 0x45b9e8, "\x8B\x4E\x34", 3) && !memcmp(g_base + 0x45b9ed, "\x89\x46\x30", 3) && SiteTarget(g_base + 0x45b9f0) == g_base + 0x6e06e0
          && Rtti(0xa6fcd0, "CAgentTimerExtended") && Rtti(0xa6f780, "CAgentTimer"), "a buff's rawcode is [+0x34], its unit [+0x30] (+45B9E8); the timers' classes");
    // the buff questions of study_buffs2.md, settled: (1) the rawcode is [buff+0x34]: the game's own buff bar fill +3DE270
    // takes it (+3DE290 mov ebx, [eax+0x34]) to find the buff's UI record in the table [+D33150] / mask [+D33158] (key [rec]),
    // whose name it shows (rec+0x11C, +3DE350); CBuff's vt+0x1BC writes [+0x34] out as text (+46E149, +95F30)
    CHECK(!memcmp(g_base + 0x3de290, "\x8B\x58\x34", 3) && g_base[0x3de2dc] == 0xA1 && *(DWORD *)(g_base + 0x3de2dd) == (DWORD)(g_base + 0xd33158)
          && g_base[0x3de2f0] == 0xA1 && *(DWORD *)(g_base + 0x3de2f1) == (DWORD)(g_base + 0xd33150) && !memcmp(g_base + 0x3de304, "\x39\x1E", 2)
          && !memcmp(g_base + 0x3de350, "\x8D\x86\x1C\x01\x00\x00", 6) && *(DWORD *)(g_base + 0xab55c8 + 0x1bc) == (DWORD)(g_base + 0x46e140)
          && !memcmp(g_base + 0x46e149, "\x8B\x49\x34", 3) && SiteTarget(g_base + 0x46e14c) == g_base + 0x95f30 && Rtti(0xab55c8, "CBuff"),
          "a buff's rawcode is [+0x34]: the buff bar finds the buff's icon and name by it (+3DE290), CBuff vt+0x1BC prints it");
    // (2) +0xC0 / +0xC8 are the normal / hero durations: FloatMinis (vtable +A8DC08 at +0xBC / +0xC4 in CBuff's ctor), packed by
    // +41F420 where it packs an ability's level data Dur (+4490D0: record +8) / HeroDur (+449650: +0xC), loaded under those names
    const char *const *names = (const char *const *)(g_base + 0xcb4214);
    CHECK(!memcmp(g_base + 0x41f509, "\x8B\x86\xC0\x00\x00\x00", 6) && !memcmp(g_base + 0x41f512, "\x8B\x86\xC8\x00\x00\x00", 6)
          && !memcmp(g_base + 0x41f50f, "\x89\x47\x18", 3) && !memcmp(g_base + 0x41f51d, "\x89\x47\x1C", 3)
          && SiteTarget(g_base + 0x41f4ac) == g_base + 0x4490d0 && !memcmp(g_base + 0x41f4b8, "\x89\x47\x18", 3)
          && SiteTarget(g_base + 0x41f4bf) == g_base + 0x449650 && !memcmp(g_base + 0x41f4c6, "\x89\x47\x1C", 3)
          && !memcmp(g_base + 0x44910b, "\x8B\x4C\x08\x08", 4) && !memcmp(g_base + 0x44968b, "\x8B\x4C\x08\x0C", 4)
          && !strcmp(names[0], "Dur") && !strcmp(names[1], "HeroDur")
          && *(DWORD *)(g_base + 0x6db8b6) == (DWORD)(g_base + 0xcb4214) && !memcmp(g_base + 0x6db8e3, "\x89\x46\x08", 3)
          && *(DWORD *)(g_base + 0x6db8eb) == (DWORD)(g_base + 0xcb4218) && !memcmp(g_base + 0x6db918, "\x89\x46\x0C", 3)
          && !memcmp(g_base + 0x41e632, "\xC7\x86\xBC\x00\x00\x00", 6) && *(DWORD *)(g_base + 0x41e638) == (DWORD)(g_base + 0xa8dc08)
          && !memcmp(g_base + 0x41e647, "\xC7\x86\xC4\x00\x00\x00", 6) && Rtti(0xa8dc08, "FloatMini") && BUFF_DUR == 0xc0 && BUFF_HERO_DUR == 0xc8,
          "a buff's +0xC0 / +0xC8 are its Dur / HeroDur (packed as an ability's level data, +41F509 vs +4490D0 / +449650)");
    // (3) [+0xA4]: the pause +565540 saves the timer's time left at +0xAC (FloatMini +0xA8) and its elapsed (vt+0x1C) at +0xA4
    // (FloatMini +0xA0); a fresh start +566C70 zeroes it; the game's total +563650 (ret 4) is the timer's total + [+0xA4]
    CHECK(!memcmp(g_base + 0x565558, "\xFF\x50\x18", 3) && !memcmp(g_base + 0x56555b, "\x8B\x96\xA8\x00\x00\x00", 6)
          && !memcmp(g_base + 0x56557c, "\xFF\x50\x1C", 3) && !memcmp(g_base + 0x56557f, "\x8B\x96\xA0\x00\x00\x00", 6)
          && !memcmp(g_base + 0x566c82, "\x8B\x87\xA0\x00\x00\x00", 6) && *(DWORD *)(g_base + 0x566c91) == (DWORD)(g_base + 0xd04350) && *(float *)(g_base + 0xd04350) == 0
          && !memcmp(g_base + 0x56365a, "\x83\x7F\x48\x00", 4) && !memcmp(g_base + 0x56367e, "\x8B\x87\xA4\x00\x00\x00", 6) && !memcmp(g_base + 0x5636ba, "\x8B\x87\xAC\x00\x00\x00", 6)
          && g_base[0x5636b7] == 0xC2 && *(WORD *)(g_base + 0x5636b8) == 4 && BUFF_RAN == 0xa4 && BUFF_PAUSED_LEFT == 0xac && BUFF_PAUSED == 0x48,
          "a buff's [+0xA4] is the time it ran before a pause (+565540; 0 on a fresh start, +566C70): the game's total adds it (+563650)");
    // your hero's buffs (ReadHeroBuffs), as the bar fill lists a unit's (+6B2460, called from +3FAA22): the chain from [unit+0x1DC]
    // (+6B24AE), resolved by +8AE90 (the lookup, alive [x+0x20], [x+0x54]), kept on vt+0x1E0 / +0x1E4, next [+0x24] / [+0x28] (+6B2589);
    // CBuff's own 0x1E0 / 0x1E4 say 0, its tag 'buff'; the buff UI table read as +3DE2DC .. +3DE310 does (bucket id & mask, 12 bytes,
    // first [b+8], next [rec + [b] + 4] while > 0), its name 64 bytes at +0x11C (RegisterBuffOnce +3FE27B)
    DWORD v0 = 1, v1 = 1, v2 = 0;
    BYTE fakeBuff[4] = {}; *(DWORD *)fakeBuff = (DWORD)(g_base + 0xab55c8);
    CHECK(SiteTarget(g_base + 0x3faa22) == g_base + 0x6b2460 && !memcmp(g_base + 0x6b24ae, "\x81\xC1\xDC\x01\x00\x00", 6) && SiteTarget(g_base + 0x6b24c5) == g_base + 0x8ae90
          && !memcmp(g_base + 0x6b24d8, "\xFF\x90\xE0\x01\x00\x00", 6) && !memcmp(g_base + 0x6b24e6, "\xFF\x90\xE4\x01\x00\x00", 6)
          && !memcmp(g_base + 0x6b2589, "\x8B\x47\x28\x8D\x4F\x24", 6) && SiteTarget(g_base + 0x6b2596) == g_base + 0x8ae90
          && !memcmp(g_base + 0x8ae90, "\x8B\x51\x04\x8B\x09", 5) && SiteTarget(g_base + 0x8ae95) == g_base + RVA_HANDLE_LOOKUP
          && !memcmp(g_base + 0x8ae9e, "\x83\x78\x20\x00", 4) && !memcmp(g_base + 0x8aea4, "\x8B\x40\x54", 3)
          && UNIT_ABILITIES == 0x1dc && ABILITY_NEXT == 0x24 && HANDLE_DEAD == 0x20 && HANDLE_OBJ == 0x54
          && ConstGetter(*(BYTE **)(g_base + 0xab55c8 + 0x1e0), &v0) && ConstGetter(*(BYTE **)(g_base + 0xab55c8 + 0x1e4), &v1) && !v0 && !v1
          && VirtualConst(fakeBuff, 0x1c) == 'buff' && ConstGetter(g_base + 0x451060, &v2) && v2 == 1,
          "a unit's buffs: the chain [unit+0x1DC] / next [+0x24] as +6B2460 walks it; CBuff's +0x1E0 / +0x1E4 0, its tag 'buff', CBuffAura's aura test 1");
    CHECK(!memcmp(g_base + 0x3de2ea, "\x23\xC3", 2) && !memcmp(g_base + 0x3de2ed, "\x8D\x0C\x40", 3) && !memcmp(g_base + 0x3de2f5, "\x8B\x74\x88\x08", 4)
          && !memcmp(g_base + 0x3de308, "\x8B\x01\x8B\x74\x30\x04", 6) && !memcmp(g_base + 0x3de30e, "\x85\xF6\x7F\xF2", 4)
          && *(DWORD *)(g_base + 0x3fe214) == (DWORD)(g_base + BUFF_UI_MASK) && *(DWORD *)(g_base + 0x3fe22a) == (DWORD)(g_base + BUFF_UI_BUCKETS)
          && !memcmp(g_base + 0x3fe27b, "\x6A\x40", 2) && !memcmp(g_base + 0x3fe27e, "\x8D\x86\x1C\x01\x00\x00", 6) && BUFF_UI_NAME == 0x11c,
          "the buff UI table: bucket id & mask (12 bytes), the chain [rec + [bucket] + 4] while > 0, the name 64 bytes at +0x11C");
    // a buff indicator is a simple frame / layout frame at +0 as a command button is (the bigger buff bar sizes it at +0x58 / +0x5C)
    CHECK(BaseAt0(0xaad470, "CSimpleFrame@") && BaseAt0(0xaad470, "CLayoutFrame@") && BaseAt0(RVA_COMMAND_BUTTON_VTABLE, "CSimpleFrame@") && BaseAt0(RVA_COMMAND_BUTTON_VTABLE, "CLayoutFrame@"),
          "CBuffIndicator and CCommandButton both start with CSimpleFrame / CLayoutFrame (RTTI)");
    // the buff bar size: CBuffBar's ctor +3D0100 makes a 1 x 8 grid (+13D380(1, 8)) 0.12 x 0.015 and 8 indicators of 0.015 x 0.015;
    // the grid lays its items out again on a rect change (its vt+0 +13CC90, pointing each item, +13CE4E); the info panel pins the bar's
    // bottom right (+3E8126: SetPoint 8 -> 8, -0.003); the module's sizes are those
    const float f012 = 0.12f, f015 = 0.015f, fm003 = -0.003f;
    CHECK(!memcmp(g_base + 0x3d013f, "\x6A\x08\x6A\x01", 4) && SiteTarget(g_base + 0x3d0152) == g_base + 0x13d380 && !memcmp(g_base + 0x3d014e, "\x10\xD5\xAA", 3)
          && *(float *)(g_base + 0x3d015d) == f012 && SiteTarget(g_base + 0x3d0161) == g_base + RVA_SET_WIDTH
          && *(float *)(g_base + 0x3d016c) == f015 && SiteTarget(g_base + 0x3d0170) == g_base + RVA_SET_HEIGHT
          && *(float *)(g_base + 0x3d01f9) == f015 && SiteTarget(g_base + 0x3d01fd) == g_base + RVA_SET_WIDTH
          && *(float *)(g_base + 0x3d0208) == f015 && SiteTarget(g_base + 0x3d020c) == g_base + RVA_SET_HEIGHT
          && !memcmp(g_base + 0x3d027b, "\x83\xFF\x08", 3) && SiteTarget(g_base + 0x3d019c) == g_base + 0x3d0390 && *(DWORD *)(g_base + 0x3d03d9) == (DWORD)(g_base + RVA_BUFF_INDICATOR_VT)
          && *(DWORD *)(g_base + RVA_BUFF_BAR_VT) == (DWORD)(g_base + 0x13cc90) && SiteTarget(g_base + 0x13ce4e) == g_base + RVA_SET_POINT
          && !memcmp(g_base + 0x3e8126, "\x8B\x8F\x6C\x01\x00\x00", 6) && *(float *)(g_base + 0x3e813c) == fm003 && !memcmp(g_base + 0x3e8140, "\x6A\x08\x57\x6A\x08", 5)
          && SiteTarget(g_base + 0x3e8145) == g_base + RVA_SET_POINT && GAME_BUFF_BAR_W == f012 && GAME_BUFF_BAR_H == f015 && GAME_BUFF_ICON == f015 && Rtti(RVA_BUFF_INDICATOR_VT, "CBuffIndicator"),
          "the buff bar: a 1 x 8 grid 0.12 x 0.015 of 0.015 icons (+3D0100), laid out again on a rect change (vt+0 +13CC90), pinned by its bottom right (+3E8126)");
    // Battle.net login: the main menu's BattleNetButton is its command 1 (+30E9B3 .. +30E9C4, +314480 -> the name lookup and +141430,
    // the click event 0x40090064), which connects (+322D79 -> +318EB0); the login screen's boxes AccountName / Password at +0x1F8 / +0x1FC
    // and LogonButton command 5 (+30A4C8), whose handler (+321568 -> +32D450) reads the boxes' text [box+0x1E4] (+1311C0)
    const BYTE *jt5 = *(const BYTE **)(g_base + 0x321764 + 5 * 4), *jt1 = *(const BYTE **)(g_base + 0x322f48 + 1 * 4);
    CHECK(!memcmp(g_base + 0x30e9b3, "\x6A\x01\x6A\x01\x68", 5) && !strcmp(*(const char **)(g_base + 0x30e9b8), "BattleNetButton") && SiteTarget(g_base + 0x30e9c4) == g_base + 0x314480
          && SiteTarget(g_base + 0x31448c) == g_base + RVA_FRAME_BY_NAME && !memcmp(g_base + 0x314487, "\x33\xD2", 2) && SiteTarget(g_base + 0x31449b) == g_base + 0x141430
          && *(DWORD *)(g_base + 0x141447) == 0x40090064 && *(DWORD *)(g_base + 0x1407b5) == 0x40090064 && jt1 == g_base + 0x322d79 && SiteTarget(g_base + 0x322d79) == g_base + 0x318eb0
          && !memcmp(g_base + 0x30a4c8, "\x6A\x05\x68", 3) && !strcmp(*(const char **)(g_base + 0x30a4cb), "LogonButton") && SiteTarget(g_base + 0x30a4d7) == g_base + 0x3141d0
          && !strcmp(*(const char **)(g_base + 0x30a4f7), "AccountName") && SiteTarget(g_base + 0x30a4fb) == g_base + RVA_FRAME_BY_NAME && !memcmp(g_base + 0x30a502, "\x89\x86\xF8\x01\x00\x00", 6)
          && !strcmp(*(const char **)(g_base + 0x30a509), "Password") && !memcmp(g_base + 0x30a514, "\x89\x86\xFC\x01\x00\x00", 6) && !memcmp(g_base + 0x30a4dc, "\x33\xD2", 2)
          && *(DWORD *)(g_base + 0xa9e764 + 0xc) == (DWORD)(g_base + 0x321510) && *(DWORD *)(g_base + 0xaa1abc + 0xc) == (DWORD)(g_base + 0x322b70)
          && jt5 == g_base + 0x321568 && SiteTarget(g_base + 0x32156a) == g_base + 0x32d450 && SiteTarget(g_base + 0x32d46e) == g_base + 0x1311c0 && !memcmp(g_base + 0x1311c0, "\x8B\x81\xE4\x01\x00\x00\xC3", 7)
          && Rtti(0xa9e764, "CBattleNetMain") & Rtti(0xaa1abc, "CMainMenu"),
          "the main menu's Battle.net is its command 1 (connects), the login screen's Logon its command 5 (reads AccountName / Password)");
    // the module's calls: the name lookup (fastcall(name, 0), read-only: +1213B0 with create 0, the record's +0x18), the shown test
    // ([+0xB0] & 3), the control click (ret 4), the edit box's setter (ret 8, the screen's own prefill +30AFF8), the classes it checks
    CHECK(!memcmp(g_base + 0x1212f8, "\x6A\x00\xE8", 3) && SiteTarget(g_base + 0x1212fa) == g_base + 0x1213b0 && !memcmp(g_base + 0x121303, "\x8B\x40\x18", 3) && g_base[0x121309] == 0xC3
          && !memcmp(g_base + 0x11cdf0, "\xF6\x81\xB0\x00\x00\x00\x03", 7) && *(DWORD *)(g_base + 0xa9e764 + 0xd0) == (DWORD)(g_base + 0x11c6d0) && !memcmp(g_base + 0x11c6dd, "\x83\xC8\x01", 3)
          && g_base[0x1407ea] == 0xC2 && *(WORD *)(g_base + 0x1407eb) == 4 && g_base[0x132894] == 0xC2 && *(WORD *)(g_base + 0x132895) == 8
          && SiteTarget(g_base + 0x30aff8) == g_base + RVA_EDIT_SET_TEXT && !memcmp(g_base + 0x30aff5, "\x6A\x01", 2)
          && Rtti(RVA_GLUE_BUTTON_VT[0], "CGlueButtonWar3") & Rtti(RVA_GLUE_BUTTON_VT[1], "CGlueTextButtonWar3") & Rtti(RVA_EDIT_VT[0], "CGlueEditBoxWar3") & Rtti(RVA_EDIT_VT[1], "CEditBox") && *(DWORD *)(g_base + 0x1306a1) == (DWORD)(g_base + RVA_EDIT_VT[1]) && BaseAt0(RVA_EDIT_VT[0], "CEditBox@")
          && RVA_CONTROL_CLICK == 0x1407b0 && FRAME_HIDDEN == 0xb0,
          "the login's game calls: the name lookup, the shown test, the click (ret 4), the edit box setter (ret 8), the glue classes");
    // the login screen itself: the glue's screen list (+CB3130: id, frame name, maker) has id 0xE "BattleNetMainFrame" made by +2F38F0,
    // which builds a CBattleNetMain (+2F3942 -> +2F7170, vtable at +2F71B2); its init keeps its Logon at +0x214 (+30A4DE)
    CHECK(*(DWORD *)(g_base + 0xcb31d8) == 0xe && !strcmp(*(const char **)(g_base + 0xcb31dc), BNET_SCREEN_NAME) && *(DWORD *)(g_base + 0xcb31e0) == (DWORD)(g_base + 0x2f38f0)
          && SiteTarget(g_base + 0x2f3942) == g_base + 0x2f7170 && *(DWORD *)(g_base + 0x2f71b4) == (DWORD)(g_base + RVA_BNET_MAIN_VT)
          && !memcmp(g_base + 0x30a4de, "\x89\x86\x14\x02\x00\x00", 6) && BNET_LOGON == 0x214 && BNET_ACCOUNT == 0x1f8 && BNET_PASSWORD == 0x1fc,
          "the login screen is the frame 'BattleNetMainFrame' (a CBattleNetMain); its own Logon +0x214, boxes +0x1F8 / +0x1FC");
    // after the login, the custom games: the chat panel's CustomGameButton is its command 3 (kept at +0x2E0), which opens them; the
    // custom games panel keeps its name box +0x204, its games list +0x208 (a ListBoxWar3); JoinGameButton (command 4) goes to +0x214
    // first, then LoadGameButton (command 3) over it in the same init (+309CC1), so Join is found by name as the init finds it (+314150);
    // Join joins the list's selected game (vt+0x148 on +0x208) else the typed name (+0x307540); the selected item is [list+0x1F4]
    const BYTE *cj3 = *(const BYTE **)(g_base + 0x3208b4 + 3 * 4), *jj4 = *(const BYTE **)(g_base + 0x321194 + 4 * 4);
    CHECK(!memcmp(g_base + 0x307cba, "\x6A\x03\x68", 3) && !strcmp(*(const char **)(g_base + 0x307cbd), "CustomGameButton") && SiteTarget(g_base + 0x307cc9) == g_base + 0x3140a0
          && !memcmp(g_base + 0x307cd7, "\x89\x86\xE0\x02\x00\x00", 6) && SiteTarget(g_base + 0x3140ac) == g_base + RVA_FRAME_BY_NAME && SiteTarget(g_base + 0x3140bb) == g_base + 0x141430
          && *(DWORD *)(g_base + RVA_CHAT_PANEL_VT + 0xc) == (DWORD)(g_base + 0x320320) && cj3 == g_base + 0x320356 && SiteTarget(g_base + 0x320358) == g_base + 0x31e4f0
          && !strcmp(*(const char **)(g_base + 0x3099ab), "JoinGameNameEditBox") && !memcmp(g_base + 0x3099bc, "\x89\x87\x04\x02\x00\x00", 6)
          && !strcmp(*(const char **)(g_base + 0x3099c3), "ListBoxWar3") && !memcmp(g_base + 0x3099ce, "\x89\x87\x08\x02\x00\x00", 6)
          && !memcmp(g_base + 0x3099f0, "\x6A\x04\x68", 3) && !strcmp(*(const char **)(g_base + 0x3099f3), "JoinGameButton") && SiteTarget(g_base + 0x3099ff) == g_base + 0x314150
          && !memcmp(g_base + 0x309a0b, "\x89\x87\x14\x02\x00\x00", 6) && *(DWORD *)(g_base + RVA_JOIN_PANEL_VT + 0xc) == (DWORD)(g_base + 0x320fb0)
          && !memcmp(g_base + 0x309caa, "\x6A\x03\x68", 3) && !strcmp(*(const char **)(g_base + 0x309cad), "LoadGameButton") && SiteTarget(g_base + 0x309cb3) == g_base + 0x314150
          && !memcmp(g_base + 0x309cc1, "\x89\x87\x14\x02\x00\x00", 6) && SiteTarget(g_base + 0x31415c) == g_base + RVA_FRAME_BY_NAME && !memcmp(g_base + 0x314156, "\x33\xD2", 2)
          && *(const BYTE **)(g_base + 0x321194 + 3 * 4) == g_base + 0x320ff0 && SiteTarget(g_base + 0x320ff2) == g_base + 0x328f50 && !strcmp(JOIN_BUTTON_NAME, "JoinGameButton")
          && jj4 == g_base + 0x320ffc && SiteTarget(g_base + 0x321000) == g_base + 0x3270d0
          && !memcmp(g_base + 0x32713a, "\x8B\x8F\x08\x02\x00\x00", 6) && !memcmp(g_base + 0x32715d, "\xFF\x90\x48\x01\x00\x00", 6)
          && !memcmp(g_base + 0x32727f, "\x8B\x8F\x04\x02\x00\x00", 6) && SiteTarget(g_base + 0x327292) == g_base + 0x307540
          && *(DWORD *)(g_base + RVA_LISTBOX_WAR3_VT + 0x148) == (DWORD)(g_base + 0x2e1fc0) && !memcmp(g_base + 0x2e1fcc, "\x8B\xBA\xF4\x01\x00\x00", 6)
          && !strcmp(*(const char **)(g_base + 0xa995dc), "BattleNetChatPanel") && !strcmp(*(const char **)(g_base + 0xa995e4), "BattleNetCustomJoinPanel")
          && Rtti(RVA_CHAT_PANEL_VT, "CBattleNetChatPanel") & Rtti(RVA_JOIN_PANEL_VT, "CBattleNetCustomJoinPanel") & Rtti(RVA_LISTBOX_WAR3_VT, "CListBoxWar3")
          && CHAT_CUSTOM_BUTTON == 0x2e0 && JOIN_NAME == 0x204 && JOIN_LIST == 0x208 && JOIN_LOAD_BUTTON == 0x214 && LIST_SELECTED == 0x1f4,
          "the chat panel's Custom Game (command 3), the custom games' name box / list / Join (command 4, by name: the selected game, else the typed name); +0x214 ends up as Load (command 3)");
    // our sweep's tint: a texture's vt+0x24 (+141D00) multiplies its alpha +0x68 by its frame's [+0x88] into +0x6C and takes its
    // colour from +0x69 / +0x6A / +0x6B (white: none)
    CHECK(*(DWORD *)(g_base + SWEEP_TEXTURE_VT + 0x24) == (DWORD)(g_base + 0x141d00) && !memcmp(g_base + 0x141d0c, "\x0F\xB6\xB0\x88\x00\x00\x00", 7)
          && !memcmp(g_base + 0x141d13, "\x0F\xB6\x41\x68", 4) && !memcmp(g_base + 0x141d2d, "\x88\x41\x6C", 3) && !memcmp(g_base + 0x141d35, "\x80\x79\x6B\xFF", 4)
          && !memcmp(g_base + 0x141d41, "\x80\x79\x69\xFF", 4) && !memcmp(g_base + 0x141d50, "\x8D\x41\x69", 3),
          "a texture's alpha is +0x68 (times its frame's +0x88), its colour +0x69..+0x6B, applied by its vt+0x24 (+141D00): our sweep's tint");
    // a control's enabled state: SetEnabled (vt+0x10c of the glue buttons and the edit box, +12B9C0) sets / clears bit 1 of [+0x1D4]
    // (+1406E0 ors it in, +141700 masks it out); the login screen disables its Logon that way (+32D3FC .. +32D404: vt+0x10c(0))
    CHECK(*(DWORD *)(g_base + RVA_GLUE_BUTTON_VT[0] + 0x10c) == (DWORD)(g_base + 0x12b9c0) && *(DWORD *)(g_base + RVA_GLUE_BUTTON_VT[1] + 0x10c) == (DWORD)(g_base + 0x12b9c0)
          && *(DWORD *)(g_base + RVA_EDIT_VT[1] + 0x10c) == (DWORD)(g_base + 0x12b9c0) && !memcmp(g_base + 0x12b9c9, "\xC7\x45\x08\x01\x00\x00\x00", 7)
          && SiteTarget(g_base + 0x12b9d1) == g_base + 0x1406e0 && SiteTarget(g_base + 0x12b9de) == g_base + 0x141700
          && !memcmp(g_base + 0x1406e3, "\x8B\x81\xD4\x01\x00\x00", 6) && !memcmp(g_base + 0x1406f1, "\x0B\x55\x08", 3) && !memcmp(g_base + 0x14170c, "\xF7\xD2\x23\xD0", 4)
          && !memcmp(g_base + 0x32d3fc, "\x8B\x8E\x14\x02\x00\x00", 6) && !memcmp(g_base + 0x32d404, "\xFF\x90\x0C\x01\x00\x00", 6)
          && CONTROL_STATE == 0x1d4 && CONTROL_ENABLED == 1,
          "a control is enabled when [+0x1D4] bit 1 is set (SetEnabled vt+0x10C +12B9C0); the login screen disables Logon with it");
    // the quest sprite: the menu bar's +0x13c, a CSpriteFrame (+0x124ff0) the game makes once (+0x3e4da9) and fits onto the Quests button [+0x138] (SetAllPoints +0x13fad0)
    static const BYTE QS_TEST[] = { 0x83, 0xBF, 0x3C, 0x01, 0, 0, 0 }, QS_STORE[] = { 0x89, 0x87, 0x3C, 0x01, 0, 0 }, QS_PUSH[] = { 0xFF, 0xB7, 0x38, 0x01, 0, 0 };
    CHECK(!memcmp(g_base + 0x3e4da9, QS_TEST, 7) && SiteTarget(g_base + 0x3e4ded) == g_base + 0x124ff0 && !memcmp(g_base + 0x3e4df8, QS_STORE, 6)
          && !memcmp(g_base + 0x3e4e2a, QS_PUSH, 6) && SiteTarget(g_base + 0x3e4e36) == g_base + 0x13fad0 && *(DWORD *)(g_base + 0x125029) == (DWORD)(g_base + 0xa7ac24),
          "the quest sprite [bar+0x13C] is a CSpriteFrame the game makes once and sets onto the Quests button [bar+0x138] (+3E4D80)");
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

    // the name tip over the hovered unit: CUnitTip (vtable +AB2C00) made once by +3C5F60 (kept at +D328C4, its ctor +3D6760);
    // the hover code calls the getter (+3C6662 / +3C684A / +3C998F, the hovered unit [+D32900]); +4057C0 (the tip for a unit,
    // ret 4) shows it with [+0x90] = 1 then vt+0x68 (+405BE0); entry +0x68 is CSimpleFrame's show +13C390 (thiscall, ret 0,
    // eax 1 / 0), +0x64 its hide +13B940 (ret 0)
    const BYTE *tv = g_base + RVA_UNITTIP_VT;
    CHECK(Rtti(RVA_UNITTIP_VT, "CUnitTip") && *(DWORD *)(tv + UNITTIP_SHOW) == (DWORD)(g_base + RVA_SIMPLEFRAME_SHOW) && *(DWORD *)(tv + 0x64) == (DWORD)(g_base + 0x13b940)
          && *(DWORD *)(g_base + RVA_SIMPLEFRAME_VT + 0x68) == (DWORD)(g_base + RVA_SIMPLEFRAME_SHOW)
          && !memcmp(g_base + 0x3c5fd8, "\x89\x35", 2) && *(DWORD *)(g_base + 0x3c5fda) == (DWORD)(g_base + 0xd328c4) && SiteTarget(g_base + 0x3c5fcd) == g_base + 0x3d6760
          && SiteTarget(g_base + 0x3c6662) == g_base + 0x3c5f60 && SiteTarget(g_base + 0x3c684a) == g_base + 0x3c5f60 && SiteTarget(g_base + 0x3c998f) == g_base + 0x3c5f60
          && !memcmp(g_base + 0x405be0, "\xC7\x81\x90\x00\x00\x00\x01\x00\x00\x00\xFF\x50\x68", 13)
          && g_base[0x13c425] == 0xC3 && g_base[0x13c429] == 0xC3 && !memcmp(g_base + 0x13c41f, "\xB8\x01\x00\x00\x00", 5) && !memcmp(g_base + 0x13c426, "\x33\xC0", 2)
          && g_base[0x405c84] == 0xC2 && *(WORD *)(g_base + 0x405c85) == 4,
          "the name tip: CUnitTip's vtable +0x68 is the show (+13C390, ret 0, eax 1 / 0) the hover code calls (+405BE0); one tip, at +D328C4");
    // quickcast as the game opens the target mode: [ui+0x210] is a CTargetMode (made by +39CFA0, called at +39CC47, stored at
    // +39CC7E; the ctor writes vtable +AAA220 at +39CFCD); SetMode +3A8330 returns for the mode it's in (+3A8361 cmp / je), calls
    // the new mode's vt+0x24 (+3A843C) and writes [ui+0x1b4] (+3A8451) only when it gave nonzero (+3A8441), ret 8; Enter
    // +3DD8F0 is thiscall (+3DD91E mov edi, ecx), its one exit returns 1 (+3DDF07, ret +3DDF27), and only that slot holds it
    int enterRefs = 0;
    for (DWORD o = 0; o + 4 <= g_imageSize; o += 4)
        enterRefs += *(DWORD *)(g_base + o) == (DWORD)(g_base + RVA_TARGETMODE_ENTER);
    const BYTE *tm = g_base + RVA_TARGETMODE_VT;
    CHECK(Rtti(RVA_TARGETMODE_VT, "CTargetMode") && *(DWORD *)(tm + TARGETMODE_ENTER) == (DWORD)(g_base + RVA_TARGETMODE_ENTER) && enterRefs == 1
          && g_base[RVA_TARGETMODE_ENTER - 1] == 0xCC && !memcmp(g_base + 0x3dd91e, "\x8B\xF9", 2)
          && !memcmp(g_base + 0x3ddf07, "\xB8\x01\x00\x00\x00", 5) && g_base[0x3ddf27] == 0xC3
          && !memcmp(g_base + 0x39cfcd, "\xC7\x06", 2) && *(DWORD *)(g_base + 0x39cfcf) == (DWORD)tm && SiteTarget(g_base + 0x39cc47) == g_base + 0x39cfa0
          && !memcmp(g_base + 0x39cc7e, "\x89\xB7\x10\x02\x00\x00", 6) && UI_TARGET_MODE == 0x210 && UI_MODE == 0x1b4
          && !memcmp(g_base + 0x3a8361, "\x3B\xCF\x0F\x84", 4) && !memcmp(g_base + 0x3a843c, "\xFF\x50\x24\x85\xC0\x75\x0E", 7)
          && !memcmp(g_base + 0x3a8451, "\x89\x3B", 2) && !memcmp(g_base + 0x3a8457, "\xC2\x08\x00", 3) && !memcmp(g_base + 0x3a8358, "\x8D\x9E\xB4\x01\x00\x00", 6),
          "the target mode: CTargetMode (vtable +AAA220) at [ui+0x210]; its Enter +3DD8F0 (vt+0x24, thiscall, ret 0, returns 1, one slot) runs in SetMode before [ui+0x1b4] is set (%d refs)", enterRefs);
    // quickcast keys (KeyCast): the game's window procedure +0BAD40 (WFE's [0x1013ce14] for 0x1E00; fastcall(hwnd, msg), ret 8,
    // msg in edi) only queues input: +0BAC80 (ret 0xc) writes an entry of the ring at +D05010 (+0BACC0), called for keys at
    // +0BAE9D; [ui+0x3d0] is the UpperButtonBarFrame (+39C460 its name, stored at +39C471); CCommandButton's click (vt+0x6c,
    // +13D7F0) is pinned above
    CHECK(g_base[0x0bad3f] == 0xCC && !memcmp(g_base + 0x0bad4b, "\x8B\xD9\x57\x8B\xFA\x83\xFF\x1C", 8) && !memcmp(g_base + 0x0bacc0, "\x89\x1C\x8D", 3)
          && *(DWORD *)(g_base + 0x0bacc3) == (DWORD)(g_base + 0xd05010) && SiteTarget(g_base + 0x0bae9d) == g_base + 0x0bac80 && !memcmp(g_base + 0x0bacf3, "\xC2\x0C\x00", 3)
          && *(DWORD *)(g_base + 0x39c461) == (DWORD)(g_base + 0xaa9a60) && !strcmp((const char *)g_base + 0xaa9a60, "UpperButtonBarFrame")
          && !memcmp(g_base + 0x39c471, "\x89\x87\xD0\x03\x00\x00", 6) && UI_UPPER_BAR == 0x3d0 && UI_CHAT_STATE == 0x3fc && UI_BUSY == 0x258,
          "quickcast keys: the window procedure +0BAD40 queues input (+0BAC80, the ring at +D05010); [ui+0x3d0] is the UpperButtonBarFrame");
    Verdict();
    return g_fails;
}
