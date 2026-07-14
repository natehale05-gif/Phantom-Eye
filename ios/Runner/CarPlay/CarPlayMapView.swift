import UIKit

/// Hand-drawn route + puck for the CarPlay window, mirroring the Android
/// Auto `PhantomEyeScreen`'s Canvas rendering. Rendering the full MapLibre
/// iOS SDK into the CarPlay-managed `CPWindow` is possible (it's just
/// another `UIView`) but is a materially bigger lift — a second live
/// MapLibre GL context outside Flutter's engine, its own style/tile
/// loading, and careful lifecycle handling — so this build ships the
/// lighter-weight custom draw instead, same tradeoff made on Android Auto.
final class CarPlayMapView: UIView {
    private var state = NavState()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        NavBridge.shared.addListener { [weak self] newState in
            DispatchQueue.main.async {
                self?.state = newState
                self?.setNeedsDisplay()
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1).cgColor)
        ctx.fill(rect)

        let route = state.routeLatLngs
        guard !route.isEmpty else {
            drawIdleMessage(in: rect)
            return
        }

        var minLat = route[0].lat, maxLat = route[0].lat
        var minLng = route[0].lng, maxLng = route[0].lng
        for p in route {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLng = min(minLng, p.lng); maxLng = max(maxLng, p.lng)
        }
        let latSpan = max(maxLat - minLat, 0.0005)
        let lngSpan = max(maxLng - minLng, 0.0005)
        let pad: CGFloat = 32

        func project(_ lat: Double, _ lng: Double) -> CGPoint {
            let x = pad + CGFloat((lng - minLng) / lngSpan) * (rect.width - 2 * pad)
            let y = pad + CGFloat(1 - (lat - minLat) / latSpan) * (rect.height - 2 * pad)
            return CGPoint(x: x, y: y)
        }

        let path = UIBezierPath()
        for (i, p) in route.enumerated() {
            let point = project(p.lat, p.lng)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1).setStroke()
        path.lineWidth = 6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        let puck = project(state.puckLat, state.puckLng)
        let puckPath = UIBezierPath(arcCenter: puck, radius: 9, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill()
        puckPath.fill()

        let headingRad = state.puckBearingDeg * .pi / 180
        let tip = CGPoint(x: puck.x + CGFloat(sin(headingRad)) * 18, y: puck.y - CGFloat(cos(headingRad)) * 18)
        let chevron = UIBezierPath(arcCenter: tip, radius: 4, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor(red: 1.0, green: 0.48, blue: 0.10, alpha: 1).setFill()
        chevron.fill()
    }

    private func drawIdleMessage(in rect: CGRect) {
        let text = "Start navigation on your phone"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(white: 0.65, alpha: 1),
            .font: UIFont.systemFont(ofSize: 20, weight: .medium),
        ]
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: origin, withAttributes: attrs)
    }
}
