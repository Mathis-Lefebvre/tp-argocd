@echo off
:: Lance setup.ps1 avec les bons paramètres PowerShell
:: Double-cliquer sur ce fichier pour installer le runner GitHub Actions

echo.
echo  ==========================================
echo   GitHub Actions Runner - Setup DevHub
echo  ==========================================
echo.

:: Lancer PowerShell en contournant la politique d'exécution
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

:: Si une erreur survient, garder la fenêtre ouverte pour lire le message
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  ERREUR : Le script s'est termine avec le code %ERRORLEVEL%
    echo  Lisez le message ci-dessus pour comprendre le probleme.
)

echo.
pause
