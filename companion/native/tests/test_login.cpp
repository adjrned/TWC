// Battle.net login at game start (LoginPass), against a fake game image: the main menu's
// Battle.net button clicked once it's shown (a second after it came up), the login screen
// waited for, the companion asked (blState 2), the account and password typed in with the
// edit box setter, Logon clicked, the password wiped; nothing in a game, nothing when off,
// frames of other classes left alone, no second try.
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img;
static BYTE mainBtn[0x200], logonBtn[0x200], accBox[0x300], pwBox[0x300], other[0x200];
static bool menuUp, loginUp;
static BYTE *clicked[8];
static int clicks, sets;
static char setAcc[64], setPw[64];
static BYTE *inGameUi;
static BYTE *__fastcall FakeByName(const char *name, int ctx) {
    if (ctx)
        return nullptr;
    if (!strcmp(name, "BattleNetButton"))
        return menuUp ? mainBtn : nullptr;
    if (!strcmp(name, "LogonButton"))
        return loginUp ? logonBtn : nullptr;
    if (!strcmp(name, "AccountName"))
        return loginUp ? accBox : nullptr;
    if (!strcmp(name, "Password"))
        return loginUp ? pwBox : nullptr;
    return nullptr;
}
static int __fastcall FakeClick(BYTE *c, int, int button) { if (clicks < 8) clicked[clicks] = c; clicks++; return button; }
static void __fastcall FakeSetText(BYTE *box, int, const char *t, int) { sets++; strcpy_s(box == accBox ? setAcc : setPw, t); }
static void *__fastcall FakeGetUi(int, int) { return inGameUi; }
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }

int main() {
    strcpy_s(g_logPath, "login.log"); DeleteFileA("login.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_FRAME_BY_NAME, FakeByName), Stub(RVA_CONTROL_CLICK, FakeClick), Stub(RVA_EDIT_SET_TEXT, FakeSetText);
    g_getUi = FakeGetUi;
    static BYTE uiObj[0x10]; *(DWORD *)uiObj = 0x1234; g_uiVtable = 0x1234;
    *(DWORD *)mainBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[1]), *(DWORD *)logonBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[0]);
    *(DWORD *)accBox = (DWORD)(img + RVA_EDIT_VT[1]), *(DWORD *)pwBox = (DWORD)(img + RVA_EDIT_VT[0]);   // a plain CEditBox (as in game) and a glue one

    // off: nothing
    menuUp = true;
    LoginPass();
    CHECK(!clicks && sh.blState == 0 && g_blStep == 0, "off: nothing clicked");
    // on, at the main menu: not at once (its animation), a second later Battle.net is clicked, once
    sh.blOn = 1;
    LoginPass();
    bool notYet = !clicks;
    *(DWORD *)(mainBtn + FRAME_HIDDEN) = 2;                    // hidden by its parent: not clicked
    g_blAt -= 2000; LoginPass();
    bool hiddenNot = !clicks;
    *(DWORD *)(mainBtn + FRAME_HIDDEN) = 0;
    LoginPass();
    LoginPass();
    CHECK(notYet && hiddenNot && clicks == 1 && clicked[0] == mainBtn && sh.blState == 1 && g_blStep == 1, "the main menu: Battle.net clicked a second after it showed, once (not while hidden)");
    // connecting: nothing until the login screen's three frames are shown; then the companion is asked
    menuUp = false;
    LoginPass();
    loginUp = true, *(DWORD *)(pwBox + FRAME_HIDDEN) = 1;
    LoginPass();
    bool waitPw = g_blStep == 1;
    *(DWORD *)(pwBox + FRAME_HIDDEN) = 0;
    LoginPass();
    CHECK(waitPw && g_blStep == 2 && sh.blState == 2 && clicks == 1, "the login screen (account, password, Logon all shown): the companion asked (blState 2)");
    // nothing typed until the companion's account comes (blSeq)
    LoginPass();
    bool waitAcc = !sets && clicks == 1;
    strcpy_s(sh.blAccount, "Ruzai"), strcpy_s(sh.blPassword, "s3cret!");
    InterlockedIncrement(&sh.blSeq);
    LoginPass();
    bool wiped = true;
    for (char c : sh.blPassword)
        wiped &= c == 0;
    CHECK(waitAcc && sets == 2 && !strcmp(setAcc, "Ruzai") && !strcmp(setPw, "s3cret!") && clicks == 2 && clicked[1] == logonBtn && wiped
          && sh.blState == 3 && sh.blDone == sh.blSeq && g_blStep == 9, "the account typed in, the password too and wiped here, Logon clicked");
    // done for this game start: back at the main menu later, nothing again
    menuUp = true, loginUp = false; g_blAt = 0;
    LoginPass(); LoginPass();
    CHECK(clicks == 2, "once per game start: the main menu again later, not clicked");

    // a new start: an empty password from the companion leaves it to you; a game running stops it
    g_blStep = 0, g_blAt = 0, sh.blState = 0, menuUp = false, loginUp = true;
    LoginPass();
    strcpy_s(sh.blAccount, "Ruzai"), sh.blPassword[0] = 0, InterlockedIncrement(&sh.blSeq);
    LoginPass();
    CHECK(sh.blState == 4 && clicks == 2 && sets == 2, "no password set in the companion: left to you (nothing typed)");
    g_blStep = 0, sh.blState = 0, inGameUi = uiObj;
    LoginPass();
    CHECK(sh.blState == 4 && g_blStep == 9, "a game running: not now");
    inGameUi = nullptr;
    // the login screen comes and the companion never answers: given up after 15 s
    g_blStep = 0, sh.blState = 0;
    LoginPass();
    g_blAt -= 16000; LoginPass();
    CHECK(sh.blState == 4 && g_blStep == 9, "no account from the companion in 15 s: left to you");
    // a frame of another class under the button's name: left alone
    g_blStep = 0, g_blAt = 0, sh.blState = 0, loginUp = false, menuUp = true;
    *(DWORD *)mainBtn = (DWORD)(img + 0xa00000);
    LoginPass(); g_blAt = 1; LoginPass();
    CHECK(clicks == 2 && g_blStep == 0, "the Battle.net button isn't a glue button: not clicked");
    *(DWORD *)mainBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[1]);
    // turned off while waiting: given up, the password wiped
    g_blStep = 1, strcpy_s(sh.blPassword, "x"), sh.blOn = 0;
    LoginPass();
    CHECK(sh.blState == 4 && !sh.blPassword[0], "turned off on the way: left to you, the password wiped");
    char logText[8192] = "";
    FILE *lf;
    if (!fopen_s(&lf, "login.log", "rb"))
        logText[fread(logText, 1, sizeof(logText) - 1, lf)] = 0, fclose(lf);
    CHECK(strstr(logText, "battle.net login: Battle.net clicked") && strstr(logText, "account 'Ruzai' typed in, Logon clicked") && !strstr(logText, "s3cret"),
          "the log: the steps, the account name, never the password");
    Verdict();
    return g_fails;
}
