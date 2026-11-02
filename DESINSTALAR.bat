@echo off
chcp 65001 >nul
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*abrir-painel.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>nul
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Painel de Demandas.vbs" >nul 2>nul
del "%USERPROFILE%\Desktop\Painel de Demandas.vbs" >nul 2>nul
del "%LOCALAPPDATA%\PainelDemandas\Painel de Demandas.vbs" >nul 2>nul
rmdir /S /Q "%LOCALAPPDATA%\PainelDemandas\app" >nul 2>nul
echo.
echo  Painel de Demandas removido e a faixa da tela liberada.
echo  (As demandas ficaram guardadas, caso instale de novo.)
echo.
pause
