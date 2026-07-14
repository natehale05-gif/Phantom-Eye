import CarPlay
import MapKit
import UIKit

/// CarPlay entry point. Requires the `com.apple.developer.carplay-maps`
/// entitlement (Apple grants this per-app via the developer portal — see
/// `ios/Runner/CarPlay/README.md`) because it implements
/// `templateApplicationScene(_:didConnect:to:)`, the variant that hands you
/// the `CPWindow` for custom map drawing (only navigation-entitled apps get
/// this; everyone else only gets an interface controller, no window).
///
/// ⚠️ Written without the ability to compile against the CarPlay SDK (this
/// build ran on Linux with no Xcode). Treat this as a strong first draft:
/// open the project in Xcode, add these files to the Runner target, and
/// fix whatever the compiler flags before relying on it.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var mapView: CarPlayMapView?
    private var navigationSession: CPNavigationSession?
    private var isNavigatingOnCar = false

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carWindow = window

        let mapView = CarPlayMapView(frame: window.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.mapView = mapView

        let rootViewController = UIViewController()
        rootViewController.view = mapView
        window.rootViewController = rootViewController

        let mapTemplate = CPMapTemplate()
        let recenterButton = CPMapButton { _ in
            // Recentering is handled entirely by the phone-side Flutter map;
            // this is a no-op placeholder for a "your car screen is just a
            // mirror" experience. Wire this to a real recenter call if the
            // custom-drawn map ever gains its own pan/zoom state.
        }
        recenterButton.image = UIImage(systemName: "location.fill")
        mapTemplate.mapButtons = [recenterButton]

        interfaceController.setRootTemplate(mapTemplate, animated: true) { _, _ in }

        NavBridge.shared.addListener { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateChange(state, mapTemplate: mapTemplate)
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        navigationSession = nil
        self.interfaceController = nil
        self.carWindow = nil
        self.mapView = nil
    }

    private func handleStateChange(_ state: NavState, mapTemplate: CPMapTemplate) {
        if state.isNavigating && !isNavigatingOnCar {
            let trip = CPTrip(
                origin: MKMapItemStub.current,
                destination: MKMapItemStub.current,
                routeChoices: [CPRouteChoice(summaryVariants: ["Phantom Eye route"], additionalInformationVariants: [], selectionSummaryVariants: [])]
            )
            navigationSession = mapTemplate.startNavigationSession(for: trip)
            isNavigatingOnCar = true
        } else if !state.isNavigating && isNavigatingOnCar {
            navigationSession?.finishTrip()
            navigationSession = nil
            isNavigatingOnCar = false
        }

        guard let session = navigationSession, state.isNavigating else { return }
        let estimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: max(state.distanceRemainingMeters, 0), unit: UnitLength.meters),
            timeRemaining: max(state.durationRemainingSeconds, 0)
        )
        session.updateEstimates(estimates, for: session.upcomingManeuvers.first ?? CPManeuver())
    }
}

/// `CPTrip` requires `MKMapItem` origin/destination even though this build
/// only needs the travel-estimate side of the navigation session (the
/// actual route geometry is drawn by `CarPlayMapView`, not by CarPlay's own
/// map). A fixed placeholder item avoids pulling in MapKit's geocoding just
/// to satisfy the type — replace with real `MKMapItem`s built from the
/// route's origin/destination coordinates if upcoming-maneuver banners ever
/// need to reflect real place names.
private enum MKMapItemStub {
    static var current: MKMapItem { MKMapItem() }
}
