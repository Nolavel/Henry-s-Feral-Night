@echo off
chcp 65001 >nul

echo ===============================
echo Умная очистка временных файлов Godot
echo ===============================

:: === Удаляем папку с локальными настройками Godot ===
if exist ".godot" (
    rmdir /s /q ".godot"
    echo Папка .godot удалена
)

:: === Удаляем временные файлы ===
for /r %%i in (*.tmp *.log) do (
    del /f /q "%%i"
    echo Удалён файл: %%i
)

:: === Удаляем временные .import, но оставляем файлы моделей/текстур/звука ===
for /r %%i in (*.import) do (
    findstr /i ".glb .fbx .png .jpg .wav .ogg" "%%i" >nul
    if errorlevel 1 (
        del /f /q "%%i"
        echo Удалён временный .import: %%i
    )
)

:: === Git: добавляем изменения и коммитим ===
git add -u
git add .gitignore
git commit -m "Smart cleanup: remove temporary Godot/system files"

:: === Git: пушим на ветку prototype ===
git push origin prototype

echo ===============================
echo Очистка и пуш завершены!
echo ===============================
pause
