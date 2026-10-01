@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild AIArtToPSD.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild AIArtToPSD.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild Tests\VisibilitySmoke.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild Tests\VisibilitySmoke.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild Tests\ExchangeUiSmoke.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo
if errorlevel 1 exit /b 1
msbuild Tests\ExchangeUiSmoke.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /v:minimal /nologo