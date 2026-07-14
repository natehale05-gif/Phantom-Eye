package com.phantomeye.phantom_eye.carapp

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class PhantomEyeSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return PhantomEyeScreen(carContext)
    }
}
