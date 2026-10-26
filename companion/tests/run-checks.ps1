# run-checks.ps1 [name]: the companion's own checks, no Warcraft III needed (the game module's
# are native\tests\run-tests.bat). Each prints its lines; the exit code is the failures.
#   /validate      tw-companion.ahk loads
#   checks\*.ahk   each runs inside the companion (temp ini, no elevation; mkprev.py --check):
#                  startup, pages (every page / WC3 tab), module (a stand-in module), quickcast
#   chatpaste      the chat paste, standalone, keys stubbed, the clipboard kept
# run-checks.ps1 pages   runs one check
param([string]$only = '')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$companion = Split-Path -Parent $here
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
$failed = 0

function Show-Result($name, $file, $code) {
    if (Test-Path $file) { Get-Content $file | ForEach-Object { "  $_" } }
    else { "  FAIL  no result (it didn't finish: a load error, or it hung)" }
    if ($code -ne 0 -or -not (Test-Path $file)) { $script:failed++ }
}

if ($only -eq '' -or $only -eq 'validate') {
    "== /validate"
    $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/validate', 'tw-companion.ahk' -WorkingDirectory $companion -Wait -PassThru -RedirectStandardError "$env:TEMP\twc-val.txt"
    if ($v.ExitCode -eq 0) { "  ok    tw-companion.ahk" } else { Get-Content "$env:TEMP\twc-val.txt" | ForEach-Object { "  FAIL  $_" }; $failed++ }
}

foreach ($f in Get-ChildItem "$here\checks\*.ahk") {
    $name = $f.BaseName
    if ($only -ne '' -and $only -ne $name) { continue }
    "== $name"
    $res = "$env:TEMP\twc-check-$name.txt"
    Remove-Item $res -ErrorAction SilentlyContinue
    python -I "$here\mkprev.py" $f.FullName top --check $name
    try {
        $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/validate', '_preview.ahk' -WorkingDirectory $companion -Wait -PassThru -RedirectStandardError "$env:TEMP\twc-val.txt"
        if ($v.ExitCode -ne 0) { Get-Content "$env:TEMP\twc-val.txt" | ForEach-Object { "  FAIL  $_" }; $failed++; continue }
        $p = Start-Process $ahk -ArgumentList '_preview.ahk' -WorkingDirectory $companion -PassThru
        if (-not $p.WaitForExit(90000)) { $p.Kill(); "  FAIL  still running after 90 s: stopped" }
        Show-Result $name $res $p.ExitCode
    } finally {
        Remove-Item "$companion\_preview.ahk" -ErrorAction SilentlyContinue
    }
}

if ($only -eq '' -or $only -eq 'chatpaste') {
    "== chatpaste"
    $t = "$env:TEMP\twc-chatpaste.ahk"
    python -I "$here\chatpaste.py" $t
    $p = Start-Process $ahk -ArgumentList $t -Wait -PassThru
    Show-Result 'chatpaste' "$env:TEMP\twc-check-chatpaste.txt" $p.ExitCode
}

""
if ($failed -eq 0) { "ALL CHECKS PASSED" } else { "$failed CHECK(S) FAILED" }
exit $failed
