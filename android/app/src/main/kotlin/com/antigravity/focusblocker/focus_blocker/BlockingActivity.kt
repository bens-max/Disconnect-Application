package com.antigravity.focusblocker.focus_blocker

import android.content.SharedPreferences
import android.os.Bundle
import android.view.KeyEvent
import android.app.Activity
import android.widget.TextView
import android.widget.LinearLayout
import android.graphics.Color
import android.view.WindowManager

/**
 * Blocking Activity shown when a blocked app is opened.
 * This activity prevents users from accessing the blocked app.
 */
class BlockingActivity : Activity() {
    
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var messageTextView: TextView
    private lateinit var blockedAppTextView: TextView
    private var blockedAppName = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Set up the activity window
        requestWindowFeature(android.view.Window.FEATURE_NO_TITLE)
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        sharedPreferences = getSharedPreferences("com.antigravity.focusblocker.focus_blocker", MODE_PRIVATE)
        
        // Get data from intent
        blockedAppName = intent.getStringExtra("package_name") ?: "this app"

        // Create the UI
        createUI()
        
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

        setContentView(rootLayout)
    }

    /**
     * Override back button
     */
    override fun onBackPressed() {
        // Keep the blocking screen visible until the timer expires.
    }

    /**
     * Override home button (won't work on all devices, but we try)
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_HOME, KeyEvent.KEYCODE_BACK -> true
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
        super.onDestroy()
    }
}
