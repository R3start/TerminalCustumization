@echo off
rem zi [keywords] - pick a directory from zoxide with fzf (TerminalCustumization, cmd.exe)
set "_tc_z="
for /f "usebackq delims=" %%i in (`zoxide query --interactive -- %*`) do set "_tc_z=%%i"
if defined _tc_z cd /d "%_tc_z%"
set "_tc_z="
