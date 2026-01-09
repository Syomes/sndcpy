# sndcpy
> Minimum demo primarily adapt to my devices, implementation was inspired by [sndcpy](https://github.com/rom1v/sndcpy).

## Features
- Real-time transmission(<100ms, Windows is higher but <500ms) of Android device audio to computer
- Capture system audio using MediaProjection API
- Transmit audio data via local Socket
- Foreground service ensures stable operation
- Supports 44.1kHz 16-bit stereo audio

## Technical Principle
1. Request screen recording permission on app startup (for audio capture)
2. Use `MediaProjection` and `AudioPlaybackCaptureConfig` to capture system audio
3. Send audio data to computer via local Socket (`LocalServerSocket`)
4. Computer forwards Socket data via ADB and plays audio

## Permissions
- [RECORD_AUDIO](https://developer.android.com/reference/android/Manifest.permission#RECORD_AUDIO) - Audio recording permission
- [FOREGROUND_SERVICE](https://developer.android.com/reference/android/Manifest.permission#FOREGROUND_SERVICE) - Foreground service permission
- [FOREGROUND_SERVICE_MEDIA_PROJECTION](https://developer.android.com/reference/android/Manifest.permission#FOREGROUND_SERVICE_MEDIA_PROJECTION) - Media projection foreground service permission
- [POST_NOTIFICATIONS](https://developer.android.com/reference/android/Manifest.permission#POST_NOTIFICATIONS) - Post notifications permission
- [INTERNET](https://developer.android.com/reference/android/Manifest.permission#INTERNET) - Internet access permission (for Socket communication)

## Requirements
- **Android 10+** (API level 29+)
- Developer options enabled
- ADB connected

## Usage
1. Ensure `adb`, `nmap` are installed
2. Install APK to Android device
3. Run ADB port forwarding command on computer:
   ```bash
   adb forward tcp:28200 localabstract:sndcpy
   ```
4. Launch Android app and authorize screen recording permission
5. Audio will be forwarded to computer via Socket, recommended command to play audio:
```bash
# GNU/Linux and MacOS
ncat localhost 28200 | play -t raw -r 44100 -e signed -b 16 -c 2 -

# Windows
ncat localhost 28200 | sox -t raw -r 44100 -e signed-integer -b 16 -c 2 - -t waveaudio default
```

---

Out of Box: Run script(`sndcpy` for GNU/Linux and MacOS and `sndcpy.bat` for Windows) in the release directory.

## Notes
- First run requires screen recording permission authorization
- App runs as foreground service, notification will be shown in status bar
- Audio data is transmitted via local Socket, requires companion computer program
- Only supports system audio capture, does not include microphone input

## [License](./LICENSE)
