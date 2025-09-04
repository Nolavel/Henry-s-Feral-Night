@echo off
:: ===============================
:: Git cleanup + commit + push (prototype only)
:: ===============================

echo.
echo === Removing cached files (respecting .gitignore) ===
git rm -r --cached .

echo.
echo === Adding all files ===
git add .

echo.
echo === Commit changes ===
git commit -m "Cleanup: removed temp files, updated .gitignore and README"

echo.
echo === Pushing to branch: prototype ===
git push origin prototype

echo.
echo === Done! Press any key to exit ===
pause >nul
