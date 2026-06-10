@echo OFF
REM ============================================================
REM  start_tests.bat
REM  Lance les deux serveurs Node.js de test StreetPhare
REM  (principal sur 3000 + secondaire sur 3001) en parallele,
REM  chacun dans sa propre fenetre cmd.
REM
REM  Usage : double-cliquer sur le fichier, OU depuis un terminal :
REM     test_servers\start_tests.bat
REM
REM  Pour arreter : fermer les deux fenetres, OU Ctrl+C dans
REM  chacune d'elles.
REM ============================================================

setlocal
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

REM -- Verifications prealables --
where node >nul 2>nul
if errorlevel 1 (
    echo [ERREUR] Node.js introuvable dans le PATH.
    echo           Installez-le depuis https://nodejs.org/
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%node_modules\express" (
    echo [*] Installation des dependances (express)...
    call npm install --no-audit --no-fund --loglevel=error
    if errorlevel 1 (
        echo [ERREUR] npm install a echoue.
        pause
        exit /b 1
    )
)

echo.
echo ============================================
echo   StreetPhare - serveurs de test locaux
echo ============================================
echo  - Serveur PRINCIPAL   : http://localhost:3000
echo  - Serveur SECONDAIRE  : http://localhost:3001
echo.
echo  (deux fenetres cmd vont s'ouvrir)
echo  (Ctrl+C dans chacune pour arreter)
echo ============================================
echo.

REM Ouvre le serveur principal dans une nouvelle fenetre
start "StreetPhare-PRIMARY-3000" cmd /k "set PORT=3000&& set ROLE=primary&& set NEXT_BACKUP_URL=http://localhost:3001&& node server_primary.js"

REM Petite pause pour eviter une collision de logs
timeout /t 1 /nobreak >nul

REM Ouvre le serveur secondaire dans une nouvelle fenetre
start "StreetPhare-SECONDARY-3001" cmd /k "set PORT=3001&& set ROLE=secondary&& set NEXT_BACKUP_URL=http://localhost:3002&& node server_secondary.js"

echo [OK] Les deux serveurs sont lances.
echo     Vous pouvez maintenant lancer l'app Flutter en mode debug.
echo     Le FailoverManager basculera automatiquement vers :3001
echo     si vous tuez le processus du serveur :3000.
echo.
endlocal
exit /b 0
