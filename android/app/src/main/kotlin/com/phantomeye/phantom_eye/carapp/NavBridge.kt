package com.phantomeye.phantom_eye.carapp

/**
 * In-process bridge between the Flutter navigation engine (running inside
 * [com.phantomeye.phantom_eye.MainActivity]'s Flutter engine) and the
 * Android Auto [PhantomEyeScreen].
 *
 * Android Auto's `CarAppService` runs in the *same process* as the rest of
 * the app by default (we didn't declare `android:process` on the service),
 * so a plain singleton + listener callback is sufficient — no need for a
 * cross-process IPC mechanism. [MainActivity] forwards nav ticks from Dart
 * into this object via a `MethodChannel`; [PhantomEyeScreen] subscribes and
 * calls `invalidate()` on every update so the host re-pulls the template
 * (and, for the map surface, redraws the route/puck).
 */
object NavBridge {

    data class ManeuverInfo(
        val instruction: String,
        val distanceToManeuverMeters: Double,
        val streetName: String?,
    )

    data class NavState(
        val isNavigating: Boolean,
        val puckLat: Double,
        val puckLng: Double,
        val puckBearingDeg: Double,
        val routeLatLngs: List<DoubleArray>, // [lat, lng] pairs
        val distanceRemainingMeters: Double,
        val durationRemainingSeconds: Double,
        val etaEpochMillis: Long,
        val currentManeuver: ManeuverInfo?,
        val hasArrived: Boolean,
    )

    @Volatile
    var state: NavState = NavState(
        isNavigating = false,
        puckLat = 0.0,
        puckLng = 0.0,
        puckBearingDeg = 0.0,
        routeLatLngs = emptyList(),
        distanceRemainingMeters = 0.0,
        durationRemainingSeconds = 0.0,
        etaEpochMillis = 0L,
        currentManeuver = null,
        hasArrived = false,
    )
        private set

    private val listeners = mutableListOf<(NavState) -> Unit>()

    fun update(newState: NavState) {
        state = newState
        listeners.forEach { it(newState) }
    }

    fun stopNavigation() {
        update(state.copy(isNavigating = false))
    }

    fun addListener(listener: (NavState) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (NavState) -> Unit) {
        listeners.remove(listener)
    }
}
