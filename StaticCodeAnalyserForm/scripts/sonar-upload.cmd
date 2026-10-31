@echo off
rem Startet sonar-upload.ps1 aus der cmd-Shell. Parameter werden durchgereicht.
rem Probelauf ohne Upload: sonar-upload.cmd -DryRun
rem -DisableDelphi: das Java-Delphi-Plugin auf dem Server soll nicht mitlaufen.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sonar-upload.ps1" -DisableDelphi %*
exit /b %ERRORLEVEL%
