@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Tools\PrepareExchangeJob.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild Tools\PrepareExchangeJob.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /v:minimal /nologo