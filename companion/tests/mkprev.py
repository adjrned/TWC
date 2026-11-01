# python -I tests/mkprev.py <extra.ahk> [top|end] [--check <name>]
# Writes companion\_preview.ahk: tw-companion.ahk with a temp ini (%TEMP%\twc-preview.ini,
# never the real one), no elevation, and the extra code at the top (right after the ini)
# or at the end. With --check, a prelude goes first: OnError and TwcCheck(ok, msg) /
# TwcCheckDone() write the results to %TEMP%\twc-check-<name>.txt and exit.
import os, sys

here = os.path.dirname(os.path.abspath(__file__))
companion = os.path.dirname(here)
args = [a for a in sys.argv[1:]]
check = None
if '--check' in args:
    i = args.index('--check')
    check = args[i + 1]
    del args[i:i + 2]
extra_path = args[0]
where = args[1] if len(args) > 1 else 'end'

bs = chr(92)
src = open(os.path.join(companion, 'tw-companion.ahk'), encoding='utf-8-sig').read().replace('\r\n', '\n')
ini = ('iniFile := A_Temp "' + bs + 'twc-preview.ini"\n'
       'try FileDelete(iniFile)\n'
       'IniWrite(1, iniFile, "Game", "module")\n'
       'IniWrite(0, iniFile, "Settings", "hideOnStart")\n')
prelude = ''
if check:
    out = 'A_Temp "' + bs + 'twc-check-' + check + '.txt"'
    prelude = ('global twcCheckOut := "", twcCheckFails := 0\n'
               'try FileDelete(' + out + ')\n'
               'OnError(TwcCheckError)\n'
               'TwcCheckError(e, mode) {\n'
               '    FileAppend("FAIL  ERROR: " e.Message " | " e.What " | " e.Extra "`n" e.Stack "`n", ' + out + ')\n'
               '    ExitApp(1)\n'
               '}\n'
               'TwcCheck(ok, msg) {\n'
               '    global twcCheckOut, twcCheckFails\n'
               '    twcCheckOut .= (ok ? "ok    " : "FAIL  ") msg "`n", twcCheckFails += !ok\n'
               '}\n'
               'TwcCheckDone() {\n'
               '    FileAppend(twcCheckOut (twcCheckFails ? twcCheckFails " FAILED" : "all passed") "`n", ' + out + ')\n'
               '    ExitApp(twcCheckFails)\n'
               '}\n')
extra = open(extra_path, encoding='utf-8-sig').read().replace('\r\n', '\n')
anchor = '#Include lib' + bs + 'Common.ahk'
src = src.replace(anchor, anchor + '\n' + ini + prelude + (extra if where == 'top' else ''), 1)
i = src.index('if !A_IsAdmin {')
j = src.index('ExitApp\n}', i) + len('ExitApp\n}')
src = src[:i] + src[j:]
if where != 'top':
    src += '\n' + extra
open(os.path.join(companion, '_preview.ahk'), 'w', encoding='utf-8-sig').write(src)
