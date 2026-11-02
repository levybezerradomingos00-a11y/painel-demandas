@echo off
chcp 65001 >nul
echo.
echo  Instalando o Painel de Demandas...
echo.
set "ORIGEM=%~dp0"
set "DEST=%LOCALAPPDATA%\PainelDemandas\app"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "VBS=%LOCALAPPDATA%\PainelDemandas\Painel de Demandas.vbs"

if not exist "%ORIGEM%abrir-painel.ps1" (echo  Extraia o .zip inteiro antes de rodar o instalador. & pause & exit /b 1)

rem fecha um painel que ja esteja aberto (para atualizar)
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*abrir-painel.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>nul

rem copia o app para a pasta de programas do usuario
if not exist "%DEST%\lib" mkdir "%DEST%\lib"
if not exist "%LOCALAPPDATA%\PainelDemandas" mkdir "%LOCALAPPDATA%\PainelDemandas"
copy /Y "%ORIGEM%index.html" "%DEST%\" >nul
copy /Y "%ORIGEM%abrir-painel.ps1" "%DEST%\" >nul
copy /Y "%ORIGEM%obras.html" "%DEST%\" >nul
copy /Y "%ORIGEM%versao.json" "%DEST%\" >nul
rem codigo do quadro de RT compartilhado (fica so neste computador)
if exist "%ORIGEM%quadro.txt" if not exist "%LOCALAPPDATA%\PainelDemandas\quadro.txt" copy /Y "%ORIGEM%quadro.txt" "%LOCALAPPDATA%\PainelDemandas\quadro.txt" >nul
copy /Y "%ORIGEM%lib\*.dll" "%DEST%\lib\" >nul
if not exist "%DEST%\abrir-painel.ps1" (echo  Nao foi possivel copiar os arquivos. & pause & exit /b 1)

rem arquivos baixados da internet vem "bloqueados"; sem isso o Windows recusa as bibliotecas
powershell -NoProfile -Command "Get-ChildItem -Recurse '%DEST%' | Unblock-File"

rem lancador que abre o painel sem janela preta de console
> "%VBS%" echo CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%DEST%\abrir-painel.ps1""", 0, False
if not exist "%VBS%" (echo  Nao foi possivel criar o lancador. & pause & exit /b 1)

copy /Y "%VBS%" "%STARTUP%\Painel de Demandas.vbs" >nul
copy /Y "%VBS%" "%USERPROFILE%\Desktop\Painel de Demandas.vbs" >nul 2>nul

echo  Pronto! O painel vai abrir agora e sempre que o Windows ligar.
echo  Atalho na area de trabalho: "Painel de Demandas".
echo  Win + Espaco esconde e mostra o painel. Win + F abre o Quadro de RT.
echo.
wscript "%VBS%"
timeout /t 6 >nul
