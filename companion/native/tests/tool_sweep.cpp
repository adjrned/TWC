// Not a test: the cooldown sweep's squares as the module places them, for a look.
// Runs the module's own SweepSet against fake game calls (as test_frames does) for
// a few fractions and button sizes, and writes each shown square as a line:
//   <case> <w> <h> <f> <x> <y> <width> <height>     (UI units, y down from the top)
// sweep_png.py turns that into a picture. Build and run from native\tests (a VS x86 prompt):
//   cl /nologo /O2 /EHsc /MT /Foobj\ /Feobj\tool_sweep.exe tool_sweep.cpp && obj\tool_sweep.exe > obj\sweep.txt
//   python -I sweep_png.py obj\sweep.txt obj\sweep.png
#include "../twc-game.cpp"

static BYTE *img;
static void Stub(DWORD rva, const void *fn) {
    img[rva - 1] = 0xCC;
    img[rva] = 0xE9;
    *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5));
}
struct Cell { float x, y; };
static void *__fastcall FakeFrameCtor(BYTE *mem, int, void *) { *(DWORD *)mem = (DWORD)(img + RVA_SIMPLEFRAME_VT); return mem; }
static void *__fastcall FakeTexCtor(BYTE *mem, int, void *, DWORD, DWORD) { *(DWORD *)mem = (DWORD)(img + SWEEP_TEXTURE_VT); return mem; }
static void __fastcall FakeNop2(void *, int, const void *, DWORD) {}
static void __fastcall FakeNop(void *, int) {}
// a square's point: its x / y from the frame's top left kept at +0x10 / +0x14 (free fields of the fake)
static void __fastcall FakeSetPoint(BYTE *t, int, int, void *, int, float x, float y, int) { *(float *)(t + 0x10) = x, *(float *)(t + 0x14) = y; }
static void __fastcall FakeSetW(BYTE *t, int, float w) { *(float *)(t + LAYOUT_WIDTH) = w; }
static void __fastcall FakeSetH(BYTE *t, int, float h) { *(float *)(t + LAYOUT_HEIGHT) = h; }
static void __fastcall FakeShow(BYTE *t, int) { *(DWORD *)(t + 0x7c) = 1; }
static void __fastcall FakeHide(BYTE *t, int) { *(DWORD *)(t + 0x7c) = 0; }
static void *__stdcall FakeAlloc(DWORD size, const char *, DWORD, DWORD) { return calloc(1, size); }

int main() {
    strcpy_s(g_logPath, "sweep.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_SIMPLEFRAME_CTOR, FakeFrameCtor), Stub(RVA_TEXTURE_CTOR, FakeTexCtor), Stub(RVA_SET_TEXTURE, FakeNop2);
    Stub(RVA_SET_ALL_POINTS, FakeNop2), Stub(RVA_SET_POINT, FakeSetPoint), Stub(RVA_SET_WIDTH, FakeSetW), Stub(RVA_SET_HEIGHT, FakeSetH);
    Stub(RVA_REGION_SHOW, FakeShow), Stub(RVA_REGION_HIDE, FakeHide), Stub(0x200010, FakeNop);
    for (DWORD vt : { RVA_SIMPLEFRAME_VT, SWEEP_TEXTURE_VT })
        for (int i = 0; i < 64; i++)
            ((DWORD *)(img + vt))[i] = (DWORD)(img + 0x200010);
    g_smemAlloc = FakeAlloc;
    // the command card's 0.039 square button, the Widescreen UI's 0.0275 x 0.039 one, an inventory-sized 0.032
    static const float SIZES[][2] = { { 0.039f, 0.039f }, { 0.0275f, 0.039f }, { 0.032f, 0.032f } };
    static const float FRACS[] = { 1.0f, 0.875f, 0.75f, 0.6f, 0.5f, 0.375f, 0.25f, 0.1f, 0.02f };
    static BYTE btns[3][0x100];
    for (int c = 0; c < 3; c++) {
        BYTE *b = btns[c];
        *(float *)(b + LAYOUT_WIDTH) = SIZES[c][0], *(float *)(b + LAYOUT_HEIGHT) = SIZES[c][1];
        for (float f : FRACS) {
            SweepSet(b, f * 10, 10);
            Sweep *r = nullptr;
            for (int i = 0; i < g_swN; i++)
                if (g_sw[i].btn == b)
                    r = &g_sw[i];
            for (int k = 0; r && k < SWEEP_CELLS; k++) {
                BYTE *t = r->cell[k];
                if (*(DWORD *)(t + 0x7c))
                    printf("%d %.5f %.5f %.4f %.6f %.6f %.6f %.6f\n", c, SIZES[c][0], SIZES[c][1], f,
                           *(float *)(t + 0x10), -*(float *)(t + 0x14), *(float *)(t + LAYOUT_WIDTH), *(float *)(t + LAYOUT_HEIGHT));
            }
            printf("%d %.5f %.5f %.4f end\n", c, SIZES[c][0], SIZES[c][1], f);
        }
    }
    return 0;
}
