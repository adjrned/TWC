// ============================================================================
//  twc-inject.exe <pid> <dll path> - loads twc-game.dll into Warcraft III.
//  32-bit, like the game (1.28f), so LoadLibraryA's address here is the same
//  as in the game. The companion (64-bit) runs this rather than doing it
//  itself. Exit codes: 0 loaded, 2 already loaded, 1 failed (reason on stderr).
//
//  Build: native\build.bat (32-bit, MSVC).
// ============================================================================
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int Fail(const char *what) {
    fprintf(stderr, "%s failed (error %lu)\n", what, GetLastError());
    return 1;
}

// is a module with this file name already in the process?
static bool Loaded(DWORD pid, const char *file) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snap == INVALID_HANDLE_VALUE)
        return false;
    MODULEENTRY32 m = { sizeof(m) };
    bool found = false;
    for (BOOL ok = Module32First(snap, &m); ok && !found; ok = Module32Next(snap, &m))
        found = _stricmp(m.szModule, file) == 0;
    CloseHandle(snap);
    return found;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: twc-inject <pid> <dll path>\n");
        return 1;
    }
    DWORD pid = strtoul(argv[1], nullptr, 10);
    const char *dll = argv[2];
    const char *file = strrchr(dll, '\\');
    file = file ? file + 1 : dll;
    if (GetFileAttributesA(dll) == INVALID_FILE_ATTRIBUTES)
        return Fail("finding the dll");
    if (Loaded(pid, file))
        return 2;

    HANDLE proc = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION
        | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, pid);
    if (!proc)
        return Fail("opening the game");
    BOOL wow = FALSE;
    IsWow64Process(proc, &wow);
    if (!wow) {
        CloseHandle(proc);
        fprintf(stderr, "the game isn't a 32-bit process (only 1.28 is supported)\n");
        return 1;
    }
    size_t n = strlen(dll) + 1;
    void *remote = VirtualAllocEx(proc, nullptr, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote)
        return Fail("reserving memory in the game");
    if (!WriteProcessMemory(proc, remote, dll, n, nullptr))
        return Fail("writing the dll path");
    auto load = (LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
    HANDLE t = CreateRemoteThread(proc, nullptr, 0, load, remote, 0, nullptr);
    if (!t)
        return Fail("starting the loader thread");
    WaitForSingleObject(t, 10000);
    DWORD mod = 0;
    GetExitCodeThread(t, &mod);
    CloseHandle(t);
    VirtualFreeEx(proc, remote, 0, MEM_RELEASE);
    CloseHandle(proc);
    if (!mod) {
        fprintf(stderr, "LoadLibrary in the game returned nothing\n");
        return 1;
    }
    return 0;
}
