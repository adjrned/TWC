# Builds the TW Companion download: a compiled TW Companion.exe (no AutoHotkey
# install needed) plus the files it loads at run time, zipped as
#   companion\dist\TWC-Companion-<version>.zip
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File companion\build\build.ps1
# First run downloads Ahk2Exe (the official AutoHotkey compiler) into build\.tools.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$build = $PSScriptRoot
$src = Split-Path -Parent $build
$tools = Join-Path $build ".tools"
$dist = Join-Path $src "dist"
New-Item -ItemType Directory -Force $tools, $dist | Out-Null

# AutoHotkey v2 64-bit: the compiled exe is this interpreter with the script inside
$ahk = @("$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
         "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
         (Join-Path $tools "ahk\AutoHotkey64.exe")) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) {
    Write-Host "Downloading AutoHotkey v2..."
    $zip = Join-Path $tools "ahk-v2.zip"
    Invoke-WebRequest "https://www.autohotkey.com/download/ahk-v2.zip" -OutFile $zip
    Expand-Archive $zip (Join-Path $tools "ahk") -Force
    $ahk = Join-Path $tools "ahk\AutoHotkey64.exe"
}

# Ahk2Exe, from its GitHub releases
$a2e = Join-Path $tools "Ahk2Exe\Ahk2Exe.exe"
if (-not (Test-Path $a2e)) {
    Write-Host "Downloading Ahk2Exe..."
    $rel = Invoke-RestMethod "https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    $zip = Join-Path $tools $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip
    Expand-Archive $zip (Join-Path $tools "Ahk2Exe") -Force
}

$main = Join-Path $src "tw-companion.ahk"
$version = [regex]::Match((Get-Content $main -Raw), 'global version := "([^"]+)"').Groups[1].Value
if (-not $version) { throw "No 'global version := ...' in tw-companion.ahk" }

# stage: dist\TW Companion\...
$stage = Join-Path $dist "TW Companion"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage, "$stage\assets", "$stage\lib\WebView2\64bit" | Out-Null

Write-Host "Compiling TW Companion $version..."
$exe = Join-Path $stage "TW Companion.exe"
$p = Start-Process $a2e -ArgumentList "/in `"$main`" /out `"$exe`" /base `"$ahk`" /silent verbose" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0 -or -not (Test-Path $exe)) { throw "Ahk2Exe failed (exit $($p.ExitCode))" }

# what the exe loads from its folder
Copy-Item "$src\assets\bg.png", "$src\assets\Cinzel.ttf", "$src\assets\Cinzel-OFL.txt" "$stage\assets"
Copy-Item "$src\lib\WebView2\64bit\WebView2Loader.dll" "$stage\lib\WebView2\64bit"
Copy-Item "$src\lib\WebView2\LICENSE-Microsoft.txt", "$src\lib\WebView2\LICENSE-thqby.txt" "$stage\lib\WebView2"
Copy-Item (Join-Path $build "README.txt") $stage
(Get-Content "$stage\README.txt" -Raw).Replace("{VERSION}", $version) | Set-Content "$stage\README.txt" -NoNewline

# the installer: build\installer.ahk next to the staged folder (its FileInstall
# paths are relative to dist\), with the version filled in
$inst = Join-Path $dist "installer.ahk"
(Get-Content (Join-Path $build "installer.ahk") -Raw).Replace("{VERSION}", $version) | Set-Content $inst -Encoding UTF8 -NoNewline
$setup = Join-Path $dist "TWC-Companion-Setup-$version.exe"
Write-Host "Compiling the installer..."
$p = Start-Process $a2e -ArgumentList "/in `"$inst`" /out `"$setup`" /base `"$ahk`" /silent verbose" -Wait -PassThru -NoNewWindow
Remove-Item $inst
if ($p.ExitCode -ne 0 -or -not (Test-Path $setup)) { throw "Ahk2Exe failed on the installer (exit $($p.ExitCode))" }
Write-Host "Built $setup"

$zipOut = Join-Path $dist "TWC-Companion-$version.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
Compress-Archive -Path $stage -DestinationPath $zipOut
Write-Host "Built $zipOut"
