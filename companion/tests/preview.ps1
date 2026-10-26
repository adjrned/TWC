# preview.ps1 <extra.ahk> <out.png>: runs the companion with extra code at the top (a temp ini,
# no elevation; see mkprev.py) and saves a picture of the window whose hwnd the extra code
# writes to %TEMP%\twc-prev2.log (FileAppend(someGui.Hwnd, A_Temp "\twc-prev2.log")). The
# extra code ends the preview itself (SetTimer(() => ExitApp(), -30000)). Errors: %TEMP%\twc-preverr.log
# if the extra code has OnError writing there. The preview is checked with /validate first.
param([Parameter(Mandatory)][string]$extra, [Parameter(Mandatory)][string]$out)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$companion = Split-Path -Parent $here
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
Remove-Item "$env:TEMP\twc-prev2.log", "$env:TEMP\twc-preverr.log" -ErrorAction SilentlyContinue
python -I "$here\mkprev.py" $extra top
try {
    $v = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/validate', '_preview.ahk' -WorkingDirectory $companion -Wait -PassThru -RedirectStandardError "$env:TEMP\twc-prevval.txt"
    if ($v.ExitCode -ne 0) { Get-Content "$env:TEMP\twc-prevval.txt"; exit 1 }
    $p = Start-Process $ahk -ArgumentList '_preview.ahk' -WorkingDirectory $companion -PassThru
    & "$here\shot.ps1" "$env:TEMP\twc-prev2.log" $out
    $p.WaitForExit(60000) | Out-Null
} finally {
    Remove-Item "$companion\_preview.ahk" -ErrorAction SilentlyContinue
}
if (Test-Path "$env:TEMP\twc-preverr.log") { Get-Content "$env:TEMP\twc-preverr.log" }
