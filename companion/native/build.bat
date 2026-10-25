@echo off
rem Builds twc-game.dll and twc-inject.exe (32-bit) into this folder.
rem Needs Visual Studio (Build Tools) with the C++ x86 tools; found with vswhere.
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio C++ tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars32.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist obj mkdir obj
cl /nologo /O2 /EHsc /MT /W3 /LD /Foobj\ twc-game.cpp /link /OUT:twc-game.dll /IMPLIB:obj\twc-game.lib || exit /b 1
cl /nologo /O2 /EHsc /MT /W3 /Foobj\ twc-inject.cpp /link /OUT:twc-inject.exe || exit /b 1
echo built twc-game.dll and twc-inject.exe
