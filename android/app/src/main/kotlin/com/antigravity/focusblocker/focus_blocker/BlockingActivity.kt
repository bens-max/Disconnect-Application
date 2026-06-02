package com.antigravity.focusblocker.focus_blocker

import android.app.ActivityManager
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView
import android.widget.Button
import android.widget.LinearLayout
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import java.text.SimpleDateFormat
import java.util.*

/**
 * Blocking Activity shown when a blocked app is opened.
 * This activity prevents users from accessing the blocked app.
 */
class BlockingActivity : AppCompatActivity() {
    
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var timerTextView: TextView
    private lateinit var messageTextView: TextView
    private lateinit var blockedAppTextView: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var blockEndTime = 0L
    private var blockedAppName = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Set up the activity window
        requestWindowFeature(android.view.Window.FEATURE_NO_TITLE)
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        sharedPreferences = getSharedPreferences("com.antigravity.focusblocker.focus_blocker", MODE_PRIVATE)
        
        // Get data from intent
        blockEndTime = intent.getLongExtra("end_time", 0L)
        blockedAppName = intent.getStringExtra("package_name") ?: "this app"

        // Create the UI
        createUI()
        
        // Start timer updates
        updateTimer()
    }

    /**
     * Creates the UI for the blocking screen
     */
    private fun createUI() {
        val rootLayout = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1a1a2e"))
        }

        // Title
        val titleTextView = TextView(this).apply {
            text = "Focus Blocking Active"
            textSize = 28f
            setTextColor(Color.parseColor("#bb86fc"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(32, 64, 32, 32)
            }
        }
        rootLayout.addView(titleTextView)

        // Blocked app name
        blockedAppTextView = TextView(this).apply {
            text = "App: $blockedAppName"
            textSize = 18f
            setTextColor(Color.parseColor("#b0bec5"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(32, 16, 32, 16)
            }
        }
        rootLayout.addView(blockedAppTextView)

        // Message
        messageTextView = TextView(this).apply {
            text = "This app is blocked during your focus session.\nYou'll be redirected back shortly."
            textSize = 16f
            setTextColor(Color.parseColor("#e0e0e0"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(32, 32, 32, 32)
            }
        }
        rootLayout.addView(messageTextView)

        // Timer
        timerTextView = TextView(this).apply {
            text = "Time remaining: 00:00:00"
            textSize = 32f
            setTextColor(Color.parseColor("#03dac6"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(32, 64, 32, 64)
            }
        }
        rootLayout.addView(timerTextView)

        // Go back button
        val backButton = Button(this).apply {
            text = "Return to Home"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#bb86fc"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(32, 32, 32, 32)
            }
            setOnClickListener {
                goHome()
            }
        }
        rootLayout.addView(backButton)

        setContentView(rootLayout)
    }

    /**
     * Updates the timer display
     */
    private fun updateTimer() {
        val now = System.currentTimeMillis()
        
        if (now >= blockEndTime) {
            // Blocking time is up, close this activity
            finish()
            return
        }

        val timeLeft = blockEndTime - now
        val hours = timeLeft / 3600000
        val minutes = (timeLeft % 3600000) / 60000
        val seconds = (timeLeft % 60000) / 1000

        timerTextView.text = String.format(
            Locale.getDefault(),
            "Time remaining: %02d:%02d:%02d",
            hours, minutes, seconds
        )

        // Schedule next update in 500ms
        handler.postDelayed({ updateTimer() }, 500)
    }

    /**
     * Sends the user back to home screen
     */
    private fun goHome() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
        finish()
    }

    /**
     * Override back button
     */
    override fun onBackPressed() {
        // Prevent back button from closing this activity
        goHome()
    }

    /**
     * Override home button (won't work on all devices, but we try)
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_HOME -> {
                goHome()
                true
            }
            KeyEvent.KEYCODE_BACK -> {
                goHome()
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    override fun onResume() {
        super.onResume()
        // The activity is already coming to the foreground in onResume.
        // Any logic to force it to stay on top should be handled by the AccessibilityService
        // or by re-launching the activity with appropriate flags.
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
