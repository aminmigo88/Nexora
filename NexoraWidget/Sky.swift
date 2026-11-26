import Foundation

/// Where the sun and moon are worked out: the spot saved in More → Widget, else a guess from the time zone.
struct SkySpot: Equatable {
    var latitude: Double
    var longitude: Double

    init(settings: ConnectionSettings) {
        if let latitude = settings.homeLatitude, let longitude = settings.homeLongitude {
            self.latitude = latitude
            self.longitude = longitude
        } else {
            let zone = TimeZone.current
            let standardOffset = Double(zone.secondsFromGMT()) - zone.daylightSavingTimeOffset()
            latitude = 37
            longitude = standardOffset / 3600 * 15
        }
    }
}

/// One day's sunrise and sunset, and the moon phase in degrees (0 new, 90 first quarter, 180 full, 270 last quarter).
struct SkyDay: Codable {
    var day: String
    var latitude: Double
    var longitude: Double
    var sunrise: Date?
    var sunset: Date?
    var moonDegrees: Double

    func isDay(at date: Date) -> Bool {
        guard let sunrise, let sunset else { return false }
        return date >= sunrise && date < sunset
    }

    /// 0 new … 0.5 full … 1 new
    var moonPhase: Double {
        moonDegrees / 360
    }
}

/// Sunrise, sunset and moon phase from MET Norway's free Sunrise 3.0 service, once a day.
/// When it can't be reached, the phone works them out itself.
enum SkyService {
    private static let cacheKey = "skyDay"

    static func day(for date: Date, at spot: SkySpot) async -> SkyDay {
        let key = dayKey(date)
        if let cached = cached(),
           cached.day == key,
           abs(cached.latitude - spot.latitude) < 0.01,
           abs(cached.longitude - spot.longitude) < 0.01 {
            return cached
        }

        var result = SkyMath.day(for: date, spot: spot)
        result.day = key
        let offset = offsetText(for: date)
        async let sunJSON = fetch("sun", spot: spot, day: key, offset: offset)
        async let moonJSON = fetch("moon", spot: spot, day: key, offset: offset)
        let sun = await sunJSON
        let moon = await moonJSON

        var fromInternet = 0
        if let properties = sun?["properties"] as? [String: Any] {
            if let text = (properties["sunrise"] as? [String: Any])?["time"] as? String, let time = parseTime(text) {
                result.sunrise = time
                fromInternet += 1
            }
            if let text = (properties["sunset"] as? [String: Any])?["time"] as? String, let time = parseTime(text) {
                result.sunset = time
                fromInternet += 1
            }
        }
        if let properties = moon?["properties"] as? [String: Any], let degrees = properties["moonphase"] as? Double {
            result.moonDegrees = degrees
            fromInternet += 1
        }
        // Keep only a full answer from MET Norway, so a failed day is asked again on the next refresh.
        if fromInternet == 3 {
            save(result)
        }
        return result
    }

    private static func fetch(_ kind: String, spot: SkySpot, day: String, offset: String) async -> [String: Any]? {
        let text = "https://api.met.no/weatherapi/sunrise/3.0/" + kind
            + String(format: "?lat=%.4f&lon=%.4f", spot.latitude, spot.longitude)
            + "&date=" + day + "&offset=" + offset
        guard let url = URL(string: text) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        // MET Norway asks every app to say who it is.
        request.setValue("Nexora/1.4 github.com/aminmigo88/Nexora", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { return nil }
        return object
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "+01:00" written as "%2B01:00", since a bare "+" in a URL query reads as a space.
    private static func offsetText(for date: Date) -> String {
        let seconds = TimeZone.current.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "%2B"
        let minutes = abs(seconds) / 60
        return sign + String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// MET Norway writes times like "2026-11-26T07:12+01:00".
    private static func parseTime(_ text: String) -> Date? {
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        if let date = short.date(from: text) {
            return date
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func cached() -> SkyDay? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(SkyDay.self, from: data)
    }

    private static func save(_ day: SkyDay) {
        guard let data = try? JSONEncoder().encode(day) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

/// The phone's own sums, used when MET Norway can't be reached.
enum SkyMath {
    static func day(for date: Date, spot: SkySpot) -> SkyDay {
        let times = sunTimes(on: date, latitude: spot.latitude, longitude: spot.longitude)
        return SkyDay(day: "", latitude: spot.latitude, longitude: spot.longitude,
                      sunrise: times.sunrise, sunset: times.sunset, moonDegrees: moonDegrees(at: date))
    }

    /// NOAA's sunrise equation; within a few minutes of MET Norway.
    static func sunTimes(on date: Date, latitude: Double, longitude: Double) -> (sunrise: Date?, sunset: Date?) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var midnight = DateComponents()
        midnight.year = parts.year
        midnight.month = parts.month
        midnight.day = parts.day
        guard let dayStartUTC = utc.date(from: midnight) else { return (nil, nil) }

        let dayOfYear = Double(utc.ordinality(of: .day, in: .year, for: dayStartUTC) ?? 1)
        let g = 2 * Double.pi / 365 * (dayOfYear - 1)
        var eq = 0.000075
        eq += 0.001868 * cos(g)
        eq -= 0.032077 * sin(g)
        eq -= 0.014615 * cos(2 * g)
        eq -= 0.040849 * sin(2 * g)
        let equationOfTime = 229.18 * eq

        var declination = 0.006918
        declination -= 0.399912 * cos(g)
        declination += 0.070257 * sin(g)
        declination -= 0.006758 * cos(2 * g)
        declination += 0.000907 * sin(2 * g)
        declination -= 0.002697 * cos(3 * g)
        declination += 0.00148 * sin(3 * g)

        let lat = latitude * Double.pi / 180
        let zenith = 90.833 * Double.pi / 180
        let cosHourAngle = cos(zenith) / (cos(lat) * cos(declination)) - tan(lat) * tan(declination)
        guard cosHourAngle > -1, cosHourAngle < 1 else { return (nil, nil) }
        let hourAngle = acos(cosHourAngle) * 180 / Double.pi

        let sunriseMinutes = 720 - 4 * (longitude + hourAngle) - equationOfTime
        let sunsetMinutes = 720 - 4 * (longitude - hourAngle) - equationOfTime
        return (dayStartUTC.addingTimeInterval(sunriseMinutes * 60), dayStartUTC.addingTimeInterval(sunsetMinutes * 60))
    }

    /// Where the moon is in its 29.53-day cycle, from a known new moon (6 January 2000, 18:14 UTC).
    static func moonDegrees(at date: Date) -> Double {
        let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)
        let cycle = 29.530588853 * 86_400
        var fraction = date.timeIntervalSince(knownNewMoon).truncatingRemainder(dividingBy: cycle) / cycle
        if fraction < 0 {
            fraction += 1
        }
        return fraction * 360
    }
}
