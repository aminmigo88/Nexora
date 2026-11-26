import CoreLocation
import Foundation

/// Gets the iPhone's location once, for the widget's sunrise, sunset and moon.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return "Location is off for Nexora. Turn it on in Settings → Privacy & Security → Location Services."
            case .unavailable: return "Couldn't get your location. Try again outside or near a window."
            }
        }
    }

    private let manager = CLLocationManager()
    private var waiter: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async throws -> CLLocation {
        if waiter != nil {
            throw Failure.unavailable
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            waiter = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(Failure.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func authorizationChanged() {
        guard waiter != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(Failure.denied))
        default:
            break
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(Failure.unavailable))
        }
    }
}
