package com.example.simpleapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        val textView = findViewById<TextView>(R.id.textView)
        textView.text = "Hello from AI APK Builder!\n\nThis app was built automatically using GitHub Actions.\n\nCompatible with Android 12-16"
    }
}
