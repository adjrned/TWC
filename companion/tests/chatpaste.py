# python -I tests/chatpaste.py <out.ahk>: a standalone test of the chat paste (lib\Common.ahk's
# ChatInsert / SetClipboardAfterChat, copied out as they are) with SendInput stubbed: no key is
# ever sent. It saves the clipboard first and puts it back at the end and on any error.
# Results: %TEMP%\twc-check-chatpaste.txt
import os, sys

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(os.path.dirname(here), 'lib', 'Common.ahk'), encoding='utf-8-sig').read().replace('\r\n', '\n')
i = src.index('global gChatClip := 0')
j = src.index('wc3ChatReforged(text) {')
fn = src[i:j].replace('SendInput(', 'FakeSend(')
bs = chr(92)
out = 'A_Temp "' + bs + 'twc-check-chatpaste.txt"'
test = '''#Requires AutoHotkey v2.0
#NoTrayIcon
keep := ClipboardAll()
try FileDelete(''' + out + ''')
OnError((e, m) => (A_Clipboard := keep, FileAppend("FAIL  ERROR: " e.Message "`n", ''' + out + '''), ExitApp(1)))
ChatPasteOn() => paste
paste := 1, sent := [], res := "", fails := 0
FakeSend(k) {
    global sent
    sent.Push(k " [" A_Clipboard "]")
}
Chk(ok, msg) {
    global res, fails
    res .= (ok ? "ok    " : "FAIL  ") msg "`n", fails += !ok
}
''' + fn + '''
A_Clipboard := "before"
ChatInsert("-save sniper#4")
Chk(sent.Length = 1 && sent[1] = "^v [-save sniper#4]", "pasted with Ctrl+V while the line is on the clipboard")
ChatInsert("-recall")
Chk(sent.Length = 2 && sent[2] = "^v [-recall]", "a second line right after: pasted too")
Sleep(700)
Chk(A_Clipboard = "before", "500 ms after the last paste: the clipboard from before the first")
ChatInsert("-save sniper#5")
SetClipboardAfterChat("sniper#5")
Chk(A_Clipboard = "-save sniper#5", "while pasting, the line stays on the clipboard")
Sleep(700)
Chk(A_Clipboard = "sniper#5", "then the clipboard is what -sn asked for, not the old one")
paste := 0
A_Clipboard := "before"
ChatInsert("-save sniper#6")
SetClipboardAfterChat("sniper#6")
Chk(sent[sent.Length] = "{Text}-save sniper#6 [before]" && A_Clipboard = "sniper#6", "paste off: typed, and -sn's name on the clipboard at once")
A_Clipboard := keep
FileAppend(res (fails ? fails " FAILED" : "all passed") "`n", ''' + out + ''')
ExitApp(fails)
'''
open(sys.argv[1], 'w', encoding='utf-8-sig').write(test)
