@echo off
:: Lance setup.ps1 en mode Administrateur (necessaire pour la tache planifiee)

:: Verifier si on est deja administrateur
net session >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :run

:: Pas admin → relancer en admin automatiquement
echo  Demande des droits administrateur...
powershell.exe -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c \"%~f0\"' -Verb RunAs -Wait"
exit /b

:run
echo.
echo  ==========================================
echo   GitHub Actions Runner - Setup DevHub
echo   (Administrateur)
echo  ==========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  ERREUR : Le script s'est termine avec le code %ERRORLEVEL%
    echo  Lisez le message ci-dessus.
)

echo.
pause
