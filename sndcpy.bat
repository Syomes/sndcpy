@echo off
setlocal enabledelayedexpansion

REM sndcpy - Audio forwarding from Android to PC via ADB
REM Enhanced version with automatic permission granting

set ADB=%ADB:adb%
set SERIAL=
set APK_NAME=sndcpy.apk

echo Checking ADB connection...
%ADB% devices | findstr "device$" >nul
if errorlevel 1 (
    if not "%SERIAL%"=="" (
        echo ERROR: Device %SERIAL% is not connected or not in device state
    ) else (
        echo ERROR: No device connected or not in device state
    )
    pause
    exit /b 1
)

echo Checking if sndcpy app is already installed...
%ADB% %SERIAL% shell pm list packages | findstr "com.syome.sndcpy" >nul
if %errorlevel%==0 (
    echo SUCCESS: sndcpy app already installed, skipping installation.
) else (
    echo Installing sndcpy app...
    %ADB% %SERIAL% install -r "%APK_NAME%" || (
        echo ERROR: Failed to install %APK_NAME%
        pause
        exit /b 1
    )
)

echo Granting audio projection permission...
REM Grant the PROJECT_MEDIA permission to allow audio capture without popup
%ADB% %SERIAL% shell appops set com.syome.sndcpy PROJECT_MEDIA allow || (
    echo WARNING: Could not grant PROJECT_MEDIA permission - this may cause a popup on newer Android versions
)

echo Starting sndcpy app...
REM Start the main activity which will request media projection permission
%ADB% %SERIAL% shell am start -n com.syome.sndcpy/.MainActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER

echo Setting up port forwarding...
REM Forward the local socket to TCP port for easier access
%ADB% %SERIAL% forward tcp:28200 localabstract:sndcpy

echo Starting audio playback...
echo Please accept the screen recording permission on your device when prompted.
echo After accepting, the audio will be forwarded to your PC.
echo.
echo To stop, close this window.
echo.

REM Wait for app to be ready before starting nc
echo Waiting for app...

REM Clear previous logcat entries
%ADB% %SERIAL% logcat -c

set MAX_WAIT_TIME=60
set WAITED=0

:check_logcat
if !WAITED! geq !MAX_WAIT_TIME! (
    echo.
    echo WARNING: Timeout waiting for sndcpy service. The service may not be ready, but continuing anyway...
    goto start_audio
)

REM Check for the specific log message indicating the service is ready
%ADB% %SERIAL% logcat -d | findstr /C:"Waiting for client to connect..." >nul
if errorlevel 1 (
    if !WAITED! geq 10 (
        REM Show progress every 10 seconds to avoid too much output
        if !WAITED! %% 10 equ 0 (
            set /a PROGRESS=!WAITED!/10
            echo Waiting for sndcpy service to be ready... (!PROGRESS!0s)
        )
    )
    timeout /t 1 /nobreak >nul
    set /a WAITED+=1
    goto check_logcat
) else (
    echo.
    echo SUCCESS: sndcpy service is ready!
)

:start_audio
REM Use netcat to receive audio and play with ffplay if available, otherwise save to file
where netcat >nul 2>&1
if errorlevel 1 (
    echo ERROR: netcat is not found. Please install netcat.
    pause
    exit /b 1
)

REM Try to find a media player
where ffplay >nul 2>&1
if not errorlevel 1 (
    echo Found ffplay, starting audio forwarding...
    netcat localhost 28200 | ffplay -f s16le -ar 44100 -ac 2 -nodisp -autoexit -
    goto :end
)

where omxplayer >nul 2>&1
if not errorlevel 1 (
    echo Found omxplayer, starting audio forwarding...
    netcat localhost 28200 | omxplayer --pcm -o local --
    goto :end
)

REM If no player found, save to raw file
echo WARNING: No audio player found. Saving raw audio to sndcpy_output.raw
netcat localhost 28200 > sndcpy_output.raw

:end
echo sndcpy finished
pause