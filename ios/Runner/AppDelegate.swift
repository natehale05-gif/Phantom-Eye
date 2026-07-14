import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.phantomeye.phantom_eye/carplay",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleCarPlayCall(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Forwards nav ticks from Dart (`lib/src/platform/carplay_bridge.dart`)
  /// into `NavBridge`, which `CarPlaySceneDelegate` observes. See
  /// `ios/Runner/CarPlay/README.md` for the CarPlay entitlement this
  /// ultimately requires.
  private func handleCarPlayCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateNavState":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Expected a map", details: nil))
        return
      }
      let routeRaw = args["route"] as? [[Double]] ?? []
      let route = routeRaw.map { (lat: $0[0], lng: $0[1]) }
      var maneuver: ManeuverInfo?
      if let maneuverArgs = args["maneuver"] as? [String: Any] {
        maneuver = ManeuverInfo(
          instruction: maneuverArgs["instruction"] as? String ?? "",
          distanceToManeuverMeters: maneuverArgs["distanceMeters"] as? Double ?? 0,
          streetName: maneuverArgs["streetName"] as? String
        )
      }
      NavBridge.shared.update(
        NavState(
          isNavigating: args["isNavigating"] as? Bool ?? false,
          puckLat: args["puckLat"] as? Double ?? 0,
          puckLng: args["puckLng"] as? Double ?? 0,
          puckBearingDeg: args["puckBearingDeg"] as? Double ?? 0,
          routeLatLngs: route,
          distanceRemainingMeters: args["distanceRemainingMeters"] as? Double ?? 0,
          durationRemainingSeconds: args["durationRemainingSeconds"] as? Double ?? 0,
          etaEpochMillis: args["etaEpochMillis"] as? Double ?? 0,
          currentManeuver: maneuver,
          hasArrived: args["hasArrived"] as? Bool ?? false
        )
      )
      result(nil)
    case "stopNavigation":
      NavBridge.shared.stopNavigation()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
