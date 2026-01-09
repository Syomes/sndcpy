@echo off
setlocal enabledelayedexpansion

REM sndcpy - Audio forwarding from Android to PC via ADB
REM Enhanced version with automatic permission granting
REM Enhanced with ANSI color output for ERROR/WARNING messages

REM Colors
for /F %%A in ('echo prompt $E ^| cmd') do set "ESC=%%A"

set "RED=%ESC%[31m"
set "YELLOW=%ESC%[33m"
set "RESET=%ESC%[0m"

set ADB=adb
set SERIAL=
set APK_NAME=sndcpy.apk
set TAG=sndcpy-AudioForwardService

color 07

echo sndcpy - Audio forwarding from Android to PC via ADB
echo.
echo Usage: sndcpy [options]
echo Options:
echo   -s, --serial SERIAL   Use specific device
echo   -h, --help           Show this help message
echo.

REM Parse command line options
:parse_args
if "%~1"=="" (
  goto :main
)
if /i "%~1"=="-s" (
  set "SERIAL=%~2"
  shift
  shift
  call :parse_args %*
  goto :main
)
if /i "%~1"=="--serial" (
  set "SERIAL=%~2"
  shift
  shift
  call :parse_args %*
  goto :main
)
if /i "%~1"=="-h" (
  echo sndcpy - Audio forwarding from Android to PC via ADB
  echo.
  echo Usage: sndcpy [options]
  echo Options:
  echo   -s, --serial SERIAL   Use specific device
  echo   -h, --help           Show this help message
  echo.
  exit /b 0
)
if /i "%~1"=="--help" (
  echo sndcpy - Audio forwarding from Android to PC via ADB
  echo.
  echo Usage: sndcpy [options]
  echo Options:
  echo   -s, --serial SERIAL   Use specific device
  echo   -h, --help           Show this help message
  echo.
  exit /b 0
)
if /i "%~1"=="--" (
  shift
  call :parse_args %*
  goto :main
)
echo %RED%ERROR: Unknown option: %~1%RESET%
exit /b 1

:main
echo Checking ADB connection...
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% devices | findstr "device$" >nul
) else (
    %ADB% devices | findstr "device$" >nul
)
if errorlevel 1 (
    if not "%SERIAL%"=="" (
        echo %RED%ERROR: Device %SERIAL% is not connected or not in device state%RESET%
    ) else (
        echo %RED%ERROR: No device connected or not in device state%RESET%
    )
    pause
    exit /b 1
)

echo Checking if sndcpy app is already installed...
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% shell pm list packages | findstr "com.syome.sndcpy" >nul
) else (
    %ADB% shell pm list packages | findstr "com.syome.sndcpy" >nul
)
if %errorlevel%==0 (
    echo SUCCESS: sndcpy app already installed, skipping installation.
) else (
    echo Installing sndcpy app...
    if not "%SERIAL%"=="" (
        %ADB% -s %SERIAL% install -r "%APK_NAME%"
    ) else (
        %ADB% install -r "%APK_NAME%"
    )
    if errorlevel 1 (
        echo %RED%ERROR: Failed to install %APK_NAME%%RESET%
        pause
        exit /b 1
    )
)

echo Granting audio projection permission...
REM Grant the PROJECT_MEDIA permission to allow audio capture without popup
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% shell appops set com.syome.sndcpy PROJECT_MEDIA allow
) else (
    %ADB% shell appops set com.syome.sndcpy PROJECT_MEDIA allow
)
if errorlevel 1 (
    echo %YELLOW%WARNING: Could not grant PROJECT_MEDIA permission - this may cause a popup on newer Android versions%RESET%
)

echo Starting sndcpy app...
REM Start the main activity which will request media projection permission
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% shell am force-stop com.syome.sndcpy
    %ADB% -s %SERIAL% shell am start -n com.syome.sndcpy/.MainActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
) else (
    %ADB% shell am force-stop com.syome.sndcpy
    %ADB% shell am start -n com.syome.sndcpy/.MainActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
)

echo Setting up port forwarding...
REM Forward the local socket to TCP port for easier access
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% forward tcp:28200 localabstract:sndcpy
) else (
    %ADB% forward tcp:28200 localabstract:sndcpy
)

echo Starting audio playback...
echo Please accept the screen recording permission on your device when prompted.
echo After accepting, the audio will be forwarded to your PC.
echo.

echo To stop, press Ctrl+C
echo.

REM Wait for app to be ready before starting nc
echo Waiting for app

:check_logcat
REM Clear previous logcat entries first
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% logcat -c
) else (
    %ADB% logcat -c
)

REM Wait for a moment to allow clearing
ping -n 2 127.0.0.1 >nul

:check_logcat_loop
REM Get logs containing the TAG
if not "%SERIAL%"=="" (
    %ADB% -s %SERIAL% logcat -d -b all -s %TAG% | findstr /C:"Waiting for client to connect..." >nul
) else (
    %ADB% logcat -d -b all -s %TAG% | findstr /C:"Waiting for client to connect..." >nul
)

if not errorlevel 1 (
    echo App Launched
    echo Waiting 1 second for socket to be ready...
    ping -n 2 127.0.0.1 >nul
    goto start_audio
)

REM Sleep for 1 second
ping -n 2 127.0.0.1 >nul

goto check_logcat_loop

:start_audio
REM Use ncat to receive audio and play with available players
where ncat >nul 2>&1
if errorlevel 1 (
    echo %RED%ERROR: ncat is not found. Please install nmap.%RESET%
    pause
    exit /b 1
)

REM Try to find a media player
where sox >nul 2>&1
if not errorlevel 1 (
    echo Found sox, starting audio forwarding...
    ncat localhost 28200 | sox -t raw -r 44100 -e signed-integer -b 16 -c 2 - -t waveaudio default
    goto :end
)

REM If no player found, show error
echo %RED%ERROR: No audio player found. Please install mpv.%RESET%
echo You can also manually connect to localhost:28200 to receive the audio stream.
goto :end

:end
echo sndcpy finished
pause
