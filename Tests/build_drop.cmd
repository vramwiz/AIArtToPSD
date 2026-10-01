@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1
for %%C in (Debug Release) do (
  msbuild AIArtToPSD.dproj /t:Rebuild /p:Config=%%C /p:Platform=Win64 /v:minimal /nologo
  if errorlevel 1 exit /b 1
  msbuild Tests\DropFileSmoke.dproj /t:Rebuild /p:Config=%%C /p:Platform=Win64 /v:minimal /nologo
  if errorlevel 1 exit /b 1
)
