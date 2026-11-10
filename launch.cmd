@echo off
rem ================================================================
rem  DSH Deskpet launcher -- double click to place the little whale
rem  (single instance is enforced by pet.ps1 itself)
rem ================================================================
set "HERE=%~dp0"
start "" /b powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%HERE%pet.ps1"
exit /b 0
