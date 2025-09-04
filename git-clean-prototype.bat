@echo off
REM ===============================
REM Cleanup temporary Godot/system files
REM ===============================

REM Remove Godot cache and temp files
del /s /q "%USERPROFILE%\.godot\*.log"
del /s /q "%USERPROFILE%\.godot\*.import"
del /s /q "%USERPROFILE%\.godot\*.tmp"
del /s /q "%USERPROFILE%\.godot\*.swap"

REM Remove local .import folder in project
if exist ".import" rmdir /s /q ".import"

REM Git add & commit cleanup
git add .
git commit -m "Cleanup: remove temporary Godot/system files"
git push origin prototype

echo ===============================
echo Cleanup and push completed!
pause
