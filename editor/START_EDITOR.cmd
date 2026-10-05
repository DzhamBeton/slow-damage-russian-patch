@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
    py -3 server.py translations\translation.jsonl
    pause
    exit /b
)
where python >nul 2>nul
if %errorlevel%==0 (
    python server.py translations\translation.jsonl
    pause
    exit /b
)
echo Install Python 3.10 or later and enable "Add Python to PATH".
echo https://www.python.org/downloads/
pause
