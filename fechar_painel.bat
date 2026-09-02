@echo off
title Encerrar Painel Web Hopper
echo ===================================================
echo   ENCERRANDO PAINEL WEB HOPPER
echo ===================================================
echo.
powershell -Command "Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }"
echo [OK] O servidor do painel foi encerrado com sucesso!
timeout /t 3 >nul
