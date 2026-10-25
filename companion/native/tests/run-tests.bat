@echo off
rem Builds and runs the game module's tests (32-bit, MSVC), each against a
rem fake game image: no Warcraft III needed. Each test prints a line per
rem check and returns its failures; this adds them up.
rem   run-tests.bat           all of them
rem   run-tests.bat display   one (test_display.cpp)
setlocal enabledelayedexpansion
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio C++ tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars32.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist obj mkdir obj
set FAILED=0
set "ONLY=%~1"
for %%f in (test_*.cpp) do (
    set "NAME=%%~nf"
    if "!ONLY!"=="" (set RUN=1) else (if /i "!NAME!"=="test_!ONLY!" (set RUN=1) else (set RUN=0))
    if !RUN!==1 (
        echo.
        echo == !NAME!
        cl /nologo /O2 /EHsc /MT /W3 /Foobj\ /Feobj\!NAME!.exe %%f >obj\!NAME!.build.txt 2>&1
        if errorlevel 1 (
            echo   BUILD FAILED, see obj\!NAME!.build.txt
            set /a FAILED+=1
        ) else (
            pushd obj
            .\!NAME!.exe
            set /a FAILED+=!errorlevel!
            if /i "!NAME!"=="test_latency" (
                .\!NAME!.exe refuse
                set /a FAILED+=!errorlevel!
            )
            popd
        )
    )
)
echo.
if !FAILED!==0 (echo ALL TESTS PASSED) else (echo !FAILED! FAILURE^(S^))
exit /b !FAILED!
