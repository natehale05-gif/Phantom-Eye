package com.phantomeye.phantom_eye

import com.phantomeye.phantom_eye.carapp.NavBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine and bridges navigation state from Dart
 * (`lib/src/platform/android_auto_bridge.dart`) into [NavBridge], which
 * feeds the Android Auto `CarAppService` (see `carapp/`). See
 * `carapp/NavBridge.kt` for why this can be a simple in-process channel
 * rather than cross-process IPC.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.phantomeye.phantom_eye/android_auto"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateNavState" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as Map<String, Any?>
                        @Suppress("UNCHECKED_CAST")
                        val routePoints = (args["route"] as? List<List<Double>>)?.map {
                            doubleArrayOf(it[0], it[1])
                        } ?: emptyList()
                        val maneuverArgs = args["maneuver"] as? Map<String, Any?>
                        val maneuver = maneuverArgs?.let {
                            NavBridge.ManeuverInfo(
                                instruction = it["instruction"] as? String ?: "",
                                distanceToManeuverMeters = (it["distanceMeters"] as? Double) ?: 0.0,
                                streetName = it["streetName"] as? String,
                            )
                        }
                        NavBridge.update(
                            NavBridge.NavState(
                                isNavigating = args["isNavigating"] as? Boolean ?: false,
                                puckLat = args["puckLat"] as? Double ?: 0.0,
                                puckLng = args["puckLng"] as? Double ?: 0.0,
                                puckBearingDeg = args["puckBearingDeg"] as? Double ?: 0.0,
                                routeLatLngs = routePoints,
                                distanceRemainingMeters = args["distanceRemainingMeters"] as? Double ?: 0.0,
                                durationRemainingSeconds = args["durationRemainingSeconds"] as? Double ?: 0.0,
                                etaEpochMillis = (args["etaEpochMillis"] as? Long)
                                    ?: (args["etaEpochMillis"] as? Int)?.toLong() ?: 0L,
                                currentManeuver = maneuver,
                                hasArrived = args["hasArrived"] as? Boolean ?: false,
                            )
                        )
                        result.success(null)
                    }
                    "stopNavigation" -> {
                        NavBridge.stopNavigation()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
