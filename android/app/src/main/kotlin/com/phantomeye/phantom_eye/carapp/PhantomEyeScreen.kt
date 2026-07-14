package com.phantomeye.phantom_eye.carapp

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Distance
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.navigation.model.Trip
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Renders Phantom Eye's turn-by-turn state on the car screen using
 * [NavigationTemplate], with a hand-rolled Canvas map (route line + puck)
 * drawn into the [android.view.Surface] the host provides — pulling in the
 * full MapLibre native renderer for the car surface is a much larger
 * undertaking (it would mean running a second MapLibre GL context outside
 * Flutter's own engine) that's out of scope for this pass; a lightweight
 * custom-drawn route + puck is what most third-party nav apps show on the
 * cluster/car display anyway, since [NF-9] limits car-screen maps to
 * "tiles + optional route", not full turn-by-turn styling.
 */
class PhantomEyeScreen(carContext: CarContext) : Screen(carContext), SurfaceCallback {

    private var surfaceContainer: SurfaceContainer? = null
    private var visibleArea: Rect? = null
    private var navigationStarted = false

    private val navListener: (NavBridge.NavState) -> Unit = { invalidate() }

    init {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(this)
        NavBridge.addListener(navListener)
    }

    override fun onGetTemplate(): Template {
        val state = NavBridge.state
        val navigationManager = carContext.getCarService(NavigationManager::class.java)

        if (state.isNavigating && !navigationStarted) {
            navigationManager.navigationStarted()
            navigationStarted = true
        } else if (!state.isNavigating && navigationStarted) {
            navigationManager.navigationEnded()
            navigationStarted = false
        }

        val builder = NavigationTemplate.Builder()
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Recenter")
                            .setOnClickListener { invalidate() }
                            .build()
                    )
                    .build()
            )

        if (state.isNavigating && state.currentManeuver != null) {
            val step = Step.Builder(state.currentManeuver.instruction)
                .build()
            builder.setNavigationInfo(
                RoutingInfo.Builder()
                    .setCurrentStep(step, Distance.create(max(state.currentManeuver.distanceToManeuverMeters, 0.0), Distance.UNIT_METERS))
                    .build()
            )
            val etaMillis = if (state.etaEpochMillis > 0) state.etaEpochMillis else System.currentTimeMillis()
            val etaZoned = ZonedDateTime.ofInstant(Instant.ofEpochMilli(etaMillis), ZoneId.systemDefault())
            val travelEstimate = TravelEstimate.Builder(
                Distance.create(max(state.distanceRemainingMeters, 0.0), Distance.UNIT_METERS),
                etaZoned,
            ).setRemainingTimeSeconds(max(state.durationRemainingSeconds.toLong(), 0L)).build()
            builder.setDestinationTravelEstimate(travelEstimate)

            navigationManager.updateTrip(
                Trip.Builder()
                    .addStep(step, travelEstimate)
                    .build()
            )
        }

        return builder.build()
    }

    // --- SurfaceCallback: hand-drawn route/puck on the host-provided surface ---

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = surfaceContainer
        renderFrame()
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = visibleArea
        renderFrame()
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = null
    }

    private fun renderFrame() {
        val container = surfaceContainer ?: return
        val surface = container.surface ?: return
        if (!surface.isValid) return

        val canvas: Canvas = surface.lockCanvas(null) ?: return
        try {
            canvas.drawColor(Color.parseColor("#0D0F14"))
            val bounds = visibleArea ?: Rect(0, 0, container.width, container.height)
            drawRouteAndPuck(canvas, bounds)
        } finally {
            surface.unlockCanvasAndPost(canvas)
        }
    }

    private fun drawRouteAndPuck(canvas: Canvas, bounds: Rect) {
        val state = NavBridge.state
        val route = state.routeLatLngs
        if (route.isEmpty()) {
            drawIdleMessage(canvas, bounds)
            return
        }

        var minLat = route[0][0]; var maxLat = route[0][0]
        var minLng = route[0][1]; var maxLng = route[0][1]
        for (p in route) {
            minLat = min(minLat, p[0]); maxLat = max(maxLat, p[0])
            minLng = min(minLng, p[1]); maxLng = max(maxLng, p[1])
        }
        val latSpan = max(maxLat - minLat, 0.0005)
        val lngSpan = max(maxLng - minLng, 0.0005)
        val pad = 40f

        fun project(lat: Double, lng: Double): Pair<Float, Float> {
            val x = bounds.left + pad + ((lng - minLng) / lngSpan).toFloat() * (bounds.width() - 2 * pad)
            // Screen y grows downward; north (higher lat) should be up.
            val y = bounds.top + pad + (1f - ((lat - minLat) / latSpan).toFloat()) * (bounds.height() - 2 * pad)
            return x to y
        }

        val routePaint = Paint().apply {
            color = Color.parseColor("#0A84FF")
            strokeWidth = 10f
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            isAntiAlias = true
        }
        val path = android.graphics.Path()
        route.forEachIndexed { i, p ->
            val (x, y) = project(p[0], p[1])
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        canvas.drawPath(path, routePaint)

        val (puckX, puckY) = project(state.puckLat, state.puckLng)
        val puckPaint = Paint().apply {
            color = Color.WHITE
            isAntiAlias = true
        }
        canvas.drawCircle(puckX, puckY, 16f, puckPaint)

        // Heading chevron.
        val headingRad = Math.toRadians(state.puckBearingDeg)
        val tipX = puckX + (sin(headingRad) * 26).toFloat()
        val tipY = puckY - (cos(headingRad) * 26).toFloat()
        val chevronPaint = Paint().apply {
            color = Color.parseColor("#FF7A1A")
            isAntiAlias = true
        }
        canvas.drawCircle(tipX, tipY, 6f, chevronPaint)
    }

    private fun drawIdleMessage(canvas: Canvas, bounds: Rect) {
        val paint = Paint().apply {
            color = Color.parseColor("#9AA0AC")
            textSize = 34f
            isAntiAlias = true
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(
            "Start navigation on your phone",
            bounds.centerX().toFloat(),
            bounds.centerY().toFloat(),
            paint,
        )
    }
}
