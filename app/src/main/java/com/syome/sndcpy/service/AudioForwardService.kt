package com.syome.sndcpy.service

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.projection.MediaProjectionManager
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.net.LocalServerSocket
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat

class AudioForwardService : Service() {

    private var recorder: AudioRecord? = null
    private var projection: MediaProjection? = null
    private var serverSocket: LocalServerSocket? = null
    private val CHANNEL_ID = "AudioForwardServiceChannel"
    private val NOTIFICATION_ID = 1

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Audio Forward Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "For audio forwarding"
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun startForegroundService() {
        createNotificationChannel()
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Audio Forward Service")
            .setContentText("Forwarding audio...")
            .setSmallIcon(android.R.drawable.ic_notification_overlay)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    @RequiresPermission(Manifest.permission.RECORD_AUDIO)
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundService()
        
        // Get MediaProjection
        val mgr = getSystemService(MediaProjectionManager::class.java)
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_OK) ?: Activity.RESULT_OK
        val data = intent?.getParcelableExtra<Intent>("data")
        projection = mgr.getMediaProjection(resultCode, data!!)

        Thread {
            try {
                serverSocket = LocalServerSocket("sndcpy")
                Log.d("AudioForwardService", "LocalServerSocket created")
                
                // Setup AudioPlaybackCapture
                val config = AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .addMatchingUsage(AudioAttributes.USAGE_ASSISTANT)
                    .build()

                val format = AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(44100)
                    .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                    .build()

                val minBufferSize = AudioRecord.getMinBufferSize(44100, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
                val actualBufferSize = if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
                    1024
                } else {
                    minBufferSize.coerceAtMost(2048)
                }

                recorder = AudioRecord.Builder()
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(actualBufferSize)
                    .setAudioPlaybackCaptureConfig(config)
                    .build()

                if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                    Log.e("AudioForwardService", "AudioRecord initialization failed")
                    stopSelf()
                    return@Thread
                } else {
                    Log.d("AudioForwardService", "Initialize AudioRecord using MediaProjection succeeded")
                }

                // Wait for client to connect
                Log.d("AudioForwardService", "Waiting for client to connect...")
                val client = serverSocket!!.accept()
                Log.d("AudioForwardService", "Client connected")
                
                val os = client.outputStream
                val buffer = ByteArray(512)

                // Start recording
                recorder?.startRecording()
                Log.d("AudioForwardService", "Start recording")

                var totalBytesSent = 0
                var lastLogTime = System.currentTimeMillis()
                while (true) {
                    val read = recorder?.read(buffer, 0, buffer.size)
                    if (read != null && read > 0) {
                        os.write(buffer, 0, read)
                        
                        // Reflush every 10 packets
                        if (totalBytesSent % (512 * 10) == 0) {
                            os.flush()
                        }
                        
                        totalBytesSent += read
                        val currentTime = System.currentTimeMillis()
                    } else if (read == AudioRecord.ERROR_INVALID_OPERATION) {
                        Log.e("AudioForwardService", "AudioRecord reading error: ERROR_INVALID_OPERATION")
                        break
                    } else if (read == AudioRecord.ERROR_BAD_VALUE) {
                        Log.e("AudioForwardService", "AudioRecord reading error: ERROR_BAD_VALUE")
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e("AudioForwardService", "Handling audio failed: ${e.message}")
                e.printStackTrace()
            }
        }.start()

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            recorder?.release()
            projection?.stop()
            serverSocket?.close()
        } catch (e: Exception) {
            Log.e("AudioForwardService", "Release sources failed: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}