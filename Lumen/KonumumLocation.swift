import CoreLocation
import Foundation

/// When In Use only. Discovery uses a one-shot ping; approach starts with an active order
/// and stops at the door or on Teslim Aldım. Never requests Always.
@MainActor
final class KonumumLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = KonumumLocation()
    static let samsun = CLLocationCoordinate2D(latitude: 41.2867, longitude: 36.3300)

    @Published private(set) var lastCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastSpeedMps: Double = 0
    var onLocationUpdate: ((CLLocationCoordinate2D, Double) -> Void)?

    var pin: CLLocationCoordinate2D { lastCoordinate ?? Self.samsun }

    private let manager = CLLocationManager()
    private var wantsUpdates = false
    private var wantsPing = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func pingForDistance() {
        wantsPing = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            wantsPing = false
        }
    }

    func prepareForOrder() {
        wantsUpdates = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startIfAllowed()
        default:
            wantsUpdates = false
        }
    }

    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
    }

    func distanceKm(latitude: Double, longitude: Double) -> Double {
        let from = pin
        let radius = 6371.0
        let dLat = (latitude - from.latitude) * .pi / 180
        let dLng = (longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(from.latitude * .pi / 180) * cos(latitude * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    func distanceLabel(latitude: Double, longitude: Double) -> String {
        let km = distanceKm(latitude: latitude, longitude: longitude)
        if km < 1 { return "\(Int((km * 1000).rounded())) m" }
        return String(format: "%.1f km", km)
    }

    func distanceMeters(latitude: Double, longitude: Double) -> Int {
        guard let current = lastCoordinate else {
            return Int((distanceKm(latitude: latitude, longitude: longitude) * 1000).rounded())
        }
        let fromLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let toLoc = CLLocation(latitude: latitude, longitude: longitude)
        return max(0, Int(fromLoc.distance(from: toLoc).rounded()))
    }

    private func startIfAllowed() {
        guard wantsUpdates else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.wantsPing,
               manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
            self.startIfAllowed()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coordinate = loc.coordinate
        let speed = loc.speed >= 0 ? loc.speed : 0
        Task { @MainActor in
            self.lastCoordinate = coordinate
            self.lastSpeedMps = speed
            self.wantsPing = false
            self.onLocationUpdate?(coordinate, speed)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.wantsPing = false
        }
    }
}
