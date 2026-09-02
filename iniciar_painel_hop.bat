@echo off
title Steal An Egg - Real-Time Server Hopper
cd /d "%~dp0"
echo =======================================================
echo  INICIANDO PAINEL HOPPER EM TEMPO REAL (STEAL AN EGG)
echo =======================================================
echo.
echo Abrindo servidor local em http://localhost:5000 ...
python server_hop_web.py
pause
