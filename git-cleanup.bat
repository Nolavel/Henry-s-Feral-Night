@echo off
:: === Чистка временных файлов из Git (Godot 4) ===

:: Обновляем .gitignore (если у тебя он уже правильный — шаг можно пропустить)
echo # Godot-specific>.gitignore
echo .godot/>>.gitignore
echo .import/>>.gitignore
echo .export/>>.gitignore
echo mono/>>.gitignore
echo data_*/>>.gitignore
echo.>>.gitignore
echo # OS garbage>>.gitignore
echo .DS_Store>>.gitignore
echo Thumbs.db>>.gitignore
echo.>>.gitignore
echo # Build & IDE>>.gitignore
echo bin/>>.gitignore
echo obj/>>.gitignore
echo .vs/>>.gitignore
echo .vscode/>>.gitignore
echo .idea/>>.gitignore
echo.>>.gitignore
echo # Android/iOS export>>.gitignore
echo /android/>>.gitignore
echo /ios/>>.gitignore
echo.>>.gitignore
echo # Logs>>.gitignore
echo *.log>>.gitignore
echo *.tmp>>.gitignore
echo *.bak>>.gitignore

:: Убираем временные файлы из индекса Git (не из диска!)
git rm -r --cached .godot .import .export mono data_* bin obj .vs .vscode .idea android ios *.log *.tmp *.bak

:: Добавляем обновленный .gitignore
git add .gitignore

:: Коммитим
git commit -m "Cleanup: remove temporary Godot/system files from repo"

:: Пушим (по умолчанию в ветку prototype, можно заменить на main)
git push origin prototype

echo.
echo === Чистка завершена! ===
pause
