@echo off
:: === Авто-коммит и пуш в GitHub ===

:: Формируем дату и время для коммита
for /f "tokens=1-3 delims=. " %%a in ('date /t') do set DATE=%%c-%%b-%%a
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIME=%%a-%%b

set MESSAGE=Auto-commit on %DATE%_%TIME%

echo =====================================
echo Добавляем изменения...
git add .

echo =====================================
echo Создаём коммит: "%MESSAGE%"
git commit -m "%MESSAGE%"

echo =====================================
echo Отправляем на GitHub (ветка master)...
git push origin master

echo =====================================
echo Готово!
pause
