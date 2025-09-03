@echo off
:: === Auto-commit and push to GitHub ===

:: Generate commit message with date and time
for /f "tokens=1-3 delims=. " %%a in ('date /t') do set DATE=%%c-%%b-%%a
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIME=%%a-%%b

set MESSAGE=Auto-commit on %DATE%_%TIME%

echo =====================================
echo Adding changes...
git add .

echo =====================================
echo Creating commit: "%MESSAGE%"
git commit -m "%MESSAGE%"

echo =====================================
echo Pushing to GitHub (branch prototype)...
git push origin prototype

echo =====================================
echo Done!
pause
