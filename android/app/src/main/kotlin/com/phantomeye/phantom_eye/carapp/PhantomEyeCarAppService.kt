package com.phantomeye.phantom_eye.carapp

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.validation.HostValidator

/**
 * Entry point the Android Auto / Android Automotive host binds to.
 *
 * Declared in `AndroidManifest.xml` with the
 * `androidx.car.app.category.NAVIGATION` category — see that file for the
 * required permissions (`androidx.car.app.NAVIGATION_TEMPLATES`,
 * `androidx.car.app.ACCESS_SURFACE`) and the `automotive_app_desc.xml`
 * metadata this needs to also run on Android Automotive OS.
 */
class PhantomEyeCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // TODO(production): ALLOW_ALL_HOSTS_VALIDATOR accepts any host,
        // which is fine for local testing against the Desktop Head Unit but
        // should be replaced with an allowlist (or
        // `HostValidator.Builder(applicationContext).addAllowedHosts(...)`)
        // before a production release, per Android's car-app security
        // guidance.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(sessionInfo: SessionInfo): Session {
        return PhantomEyeSession()
    }
}
