// Battle.net login at game start (LoginPass), against a fake game image: the main menu's
// Battle.net button clicked once it's shown (a second after it came up), the login screen
// waited for, the companion asked (blState 2), the account and password typed in with the
// edit box setter, Logon clicked, the password wiped; nothing in a game, nothing when off,
// frames of other classes left alone, no second try.
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img;
static BYTE mainBtn[0x200], logonBtn[0x200], accBox[0x300], pwBox[0x300], other[0x200], screen[0x300], decoyLogon[0x200];
static bool menuUp, loginUp, chatUp, joinUp;
static BYTE chatPanel[0x400], customBtn[0x200], joinPanel[0x300], gameBox[0x300], gameList[0x300], joinBtn[0x200];
static BYTE *clicked[8];
static int clicks, sets;
static char setAcc[64], setPw[64];
static BYTE *inGameUi;
static BYTE *__fastcall FakeByName(const char *name, int ctx) {
    if (ctx)
        return nullptr;
    if (!strcmp(name, "BattleNetButton"))
        return menuUp ? mainBtn : nullptr;
    if (!strcmp(name, "BattleNetChatPanel"))
        return chatUp ? chatPanel : nullptr;
    if (!strcmp(name, "BattleNetCustomJoinPanel"))
        return joinUp ? joinPanel : nullptr;
    if (!strcmp(name, "BattleNetMainFrame"))
        return loginUp ? screen : nullptr;
    if (!strcmp(name, "LogonButton"))
        return decoyLogon;                      // another screen's button of that name (the fourth in-game test)
    if (!strcmp(name, "AccountName"))
        return loginUp ? accBox : nullptr;
    if (!strcmp(name, "Password"))
        return loginUp ? pwBox : nullptr;
    return nullptr;
}
static int __fastcall FakeClick(BYTE *c, int, int button) { if (clicks < 8) clicked[clicks] = c; clicks++; return button; }
// the game's setter keeps its own copy, pointed to by [box+0x1e4]
static void __fastcall FakeSetText(BYTE *box, int, const char *t, int) {
    sets++;
    static char setGame[64];
    char *own = box == accBox ? setAcc : box == gameBox ? setGame : setPw;
    strcpy_s(own, 64, t);
    *(char **)(box + EDIT_TEXT) = own;
}
static void *__fastcall FakeGetUi(int, int) { return inGameUi; }
static int altJ;
static bool inFront = true;
static void FakeAltJ() { altJ++; }
static bool FakeInFront() { return inFront; }
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }

int main() {
    strcpy_s(g_logPath, "login.log"); DeleteFileA("login.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_FRAME_BY_NAME, FakeByName), Stub(RVA_CONTROL_CLICK, FakeClick), Stub(RVA_EDIT_SET_TEXT, FakeSetText);
    g_getUi = FakeGetUi, g_pressAltJ = FakeAltJ, g_gameInFront = FakeInFront;       // never a real key
    static BYTE uiObj[0x10]; *(DWORD *)uiObj = 0x1234; g_uiVtable = 0x1234;
    *(DWORD *)mainBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[1]), *(DWORD *)logonBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[0]);
    *(DWORD *)screen = (DWORD)(img + RVA_BNET_MAIN_VT), *(DWORD *)decoyLogon = (DWORD)(img + RVA_GLUE_BUTTON_VT[0]);
    *(BYTE **)(screen + BNET_ACCOUNT) = accBox, *(BYTE **)(screen + BNET_PASSWORD) = pwBox, *(BYTE **)(screen + BNET_LOGON) = logonBtn;
    *(DWORD *)(decoyLogon + CONTROL_STATE) = CONTROL_ENABLED;
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
    bool waitEnabled = g_blStep == 1;                           // shown, but Logon still disabled (connecting)
    *(DWORD *)(logonBtn + CONTROL_STATE) = *(DWORD *)(accBox + CONTROL_STATE) = *(DWORD *)(pwBox + CONTROL_STATE) = CONTROL_ENABLED;
    LoginPass();
    bool waitSettle = g_blStep == 1;                            // enabled, not yet for a second
    Sleep(1100);
    LoginPass();
    CHECK(waitPw && waitEnabled && waitSettle && g_blStep == 2 && sh.blState == 2 && clicks == 1,
          "the login screen: not while a frame is hidden or Logon disabled, nor before it's been ready for 1 s; then the companion asked (blState 2)");
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
          && sh.blState == 3 && sh.blDone == sh.blSeq && g_blStep == 9, "the account typed in, the password too and wiped here, the login screen's own Logon clicked (not the one found by name)");
    // done for this game start: back at the main menu later, nothing again
    menuUp = true, loginUp = false; g_blAt = 0;
    LoginPass(); LoginPass();
    CHECK(clicks == 2, "once per game start: the main menu again later, not clicked");

    // a new start: an empty password from the companion leaves it to you; a game running stops it
    g_blStep = 0, g_blAt = 0, sh.blState = 0, menuUp = false, loginUp = true;
    LoginPass(); Sleep(1100); LoginPass();
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
    // after the login, the custom games (layout 25): Custom Game clicked once the chat panel is ready, then the game name typed and Join
    *(DWORD *)chatPanel = (DWORD)(img + RVA_CHAT_PANEL_VT), *(BYTE **)(chatPanel + CHAT_CUSTOM_BUTTON) = customBtn;
    *(DWORD *)customBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[1]), *(DWORD *)(customBtn + CONTROL_STATE) = CONTROL_ENABLED;
    *(DWORD *)joinPanel = (DWORD)(img + RVA_JOIN_PANEL_VT), *(BYTE **)(joinPanel + JOIN_NAME) = gameBox, *(BYTE **)(joinPanel + JOIN_LIST) = gameList, *(BYTE **)(joinPanel + JOIN_BUTTON) = joinBtn;
    *(DWORD *)gameBox = (DWORD)(img + RVA_EDIT_VT[0]), *(DWORD *)(gameBox + CONTROL_STATE) = CONTROL_ENABLED;
    *(DWORD *)gameList = (DWORD)(img + RVA_LISTBOX_WAR3_VT), *(DWORD *)joinBtn = (DWORD)(img + RVA_GLUE_BUTTON_VT[0]), *(DWORD *)(joinBtn + CONTROL_STATE) = CONTROL_ENABLED;
    auto loginAgain = [&]() {                                  // a fresh start up to Logon, with the custom games asked for
        g_blStep = 2, g_blAt = GetTickCount(), sh.blState = 2, sh.blOn = 1, menuUp = false, loginUp = true, chatUp = joinUp = false;
        strcpy_s(sh.blAccount, "Ruzai"), strcpy_s(sh.blPassword, "s3cret!"), InterlockedIncrement(&sh.blSeq);
        LoginPass(); Sleep(1100); LoginPass();                   // the login screen ready for a second, then typed and Logon
    };
    sh.blAfter = 1, strcpy_s(sh.blGame, "TWRPG 1.0");
    int c0 = clicks;
    loginAgain();
    bool toChat = g_blStep == 10 && clicks == c0 + 1;
    loginUp = false, chatUp = true;
    LoginPass();
    bool waitChat = g_blStep == 10 && clicks == c0 + 1;            // ready, not yet for a second
    Sleep(1100); LoginPass();
    bool customClicked = g_blStep == 11 && clicks == c0 + 2 && clicked[(c0 + 1) % 8] == customBtn;
    chatUp = false, joinUp = true, inFront = false;
    LoginPass(); Sleep(1100); LoginPass();
    bool typedWaits = g_blStep == 12 && altJ == 0 && !strcmp(*(const char **)(gameBox + EDIT_TEXT), "TWRPG 1.0");
    inFront = true; LoginPass();
    CHECK(toChat && waitChat && customClicked && typedWaits && g_blStep == 9 && sh.blState == 7 && altJ == 1 && clicks == c0 + 2,
          "logged in: Custom Game clicked once the chat panel was ready a second, 'TWRPG 1.0' typed in, Alt+J once the game is in front (no click on the panel's +0x214)");
    // not in front for 10 s: the name stays typed in, Join left to you
    loginAgain(); loginUp = false, chatUp = true; LoginPass(); Sleep(1100); LoginPass();
    chatUp = false, joinUp = true, inFront = false; LoginPass(); Sleep(1100); LoginPass(); g_blAt -= 11000; LoginPass();
    CHECK(sh.blState == 8 && altJ == 1 && g_blStep == 9, "the game not in front for 10 s: no key sent, Join left to you");
    inFront = true;
    // a game selected in the list: Join would join it, so not clicked: the list left to you; no name set: the list stays open
    c0 = clicks; loginAgain(); loginUp = false, chatUp = true; LoginPass(); Sleep(1100); LoginPass();
    chatUp = false, joinUp = true, *(BYTE **)(gameList + LIST_SELECTED) = other; LoginPass(); Sleep(1100); LoginPass();
    bool selected = sh.blState == 8 && clicks == c0 + 2;
    *(BYTE **)(gameList + LIST_SELECTED) = nullptr, sh.blGame[0] = 0;
    c0 = clicks; loginAgain(); loginUp = false, chatUp = true; LoginPass(); Sleep(1100); LoginPass();
    chatUp = false, joinUp = true; LoginPass(); Sleep(1100); LoginPass();
    CHECK(selected && sh.blState == 6 && clicks == c0 + 2 && g_blStep == 9, "a game selected in the list: Join not clicked (left to you); no name set: the custom games list stays open (blState 6)");
    // no chat panel in 30 s (not logged in): left to you
    sh.blAfter = 1; loginAgain(); loginUp = false; LoginPass(); g_blAt -= 31000; LoginPass();
    CHECK(sh.blState == 8 && g_blStep == 9, "no chat panel within 30 s of Logon: the custom games left to you");
    sh.blAfter = 0;
    char logText[8192] = "";
    FILE *lf;
    if (!fopen_s(&lf, "login.log", "rb"))
        logText[fread(logText, 1, sizeof(logText) - 1, lf)] = 0, fclose(lf);
    CHECK(strstr(logText, "battle.net login: Battle.net clicked") && strstr(logText, "account 'Ruzai' typed in, Logon clicked") && !strstr(logText, "s3cret")
          && strstr(logText, "the boxes now hold account 'Ruzai', a password of 7 characters (the same as the companion's 7)")
          && strstr(logText, "the account name's bytes: 52 75 7A 61 69 (5)")
          && strstr(logText, "logged in: Custom Game clicked") && strstr(logText, "joining 'TWRPG 1.0' (the name box holds 'TWRPG 1.0'); the panel's +0x214 is") && strstr(logText, "Alt+J pressed (the game's Join shortcut) for 'TWRPG 1.0'")
          && strstr(logText, "after Logon: the login screen not shown, the chat room not shown, the main menu not shown; the account box empty"),
          "the log: the steps, what the boxes hold (the account, the password's length only), the menus after Logon, never the password");
    Verdict();
    return g_fails;
}
