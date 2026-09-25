@echo off
rem z [keywords] - jump to the best matching directory from zoxide (TerminalCustumization, cmd.exe)
if "%~1"=="" ( cd /d "%USERPROFILE%" & goto :eof )
if "%~2"=="" if exist "%~1\" ( cd /d "%~1" & goto :eof )
set "_tc_z="
for /f "usebackq delims=" %%i in (`zoxide query --exclude "%CD%" -- %*`) do set "_tc_z=%%i"
if defined _tc_z ( cd /d "%_tc_z%" ) else ( echo zoxide: no match found 1>&2 )
set "_tc_z="
