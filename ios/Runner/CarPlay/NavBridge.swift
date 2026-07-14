import Foundation

/// In-process bridge between the Flutter navigation engine and the CarPlay
/// scene — mirrors `android/app/src/main/kotlin/.../carapp/NavBridge.kt`
/// exactly. `AppDelegate` forwards nav ticks from Dart via a
/// `FlutterMethodChannel`; `CarPlaySceneDelegate`/`CarPlayMapViewController`
/// subscribe and redraw whenever the state changes.
struct ManeuverInfo {
    let instruction: String
    let distanceToManeuverMeters: Double
    let streetName: String?
}

struct NavState {
    var isNavigating: Bool = false
    var puckLat: Double = 0
    var puckLng: Double = 0
    var puckBearingDeg: Double = 0
    var routeLatLngs: [(lat: Double, lng: Double)] = []
    var distanceRemainingMeters: Double = 0
    var durationRemainingSeconds: Double = 0
    var etaEpochMillis: Double = 0
    var currentManeuver: ManeuverInfo?
    var hasArrived: Bool = false
}

final class NavBridge {
    static let shared = NavBridge()

    private(set) var state = NavState()
    private var listeners: [(NavState) -> Void] = []

    private init() {}

    func update(_ newState: NavState) {
        state = newState
        listeners.forEach { $0(newState) }
    }

    func stopNavigation() {
        var next = state
        next.isNavigating = false
        update(next)
    }

    func addListener(_ listener: @escaping (NavState) -> Void) {
        listeners.append(listener)
    }
}
