import Foundation

/// Day or night for the outdoor card (sun or moon). Uses the phone's time zone for longitude and a
/// mid latitude, so it needs no location permission; it can be off by about half an hour.
enum Sun {
    static func isDay(_ date: Date, latitude: Double = 37) -> Bool {
        let zone = TimeZone.current
        let offsetSeconds = zone.secondsFromGMT(for: date)
        let standardOffset = Double(offsetSeconds) - zone.daylightSavingTimeOffset(for: date)
        let longitude = standardOffset / 3600 * 15

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? zone
        let dayOfYear = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let parts = utc.dateComponents([.hour, .minute], from: date)
        let hourUTC = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60

        let g = 2 * Double.pi / 365 * (dayOfYear - 1 + (hourUTC - 12) / 24)
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
        if cosHourAngle >= 1 { return false }
        if cosHourAngle <= -1 { return true }
        let hourAngle = acos(cosHourAngle) * 180 / Double.pi

        let offsetMinutes = Double(offsetSeconds) / 60
        let sunrise = 720 - 4 * (longitude + hourAngle) - equationOfTime + offsetMinutes
        let sunset = 720 - 4 * (longitude - hourAngle) - equationOfTime + offsetMinutes
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let now = local.dateComponents([.hour, .minute], from: date)
        let minutes = Double(now.hour ?? 12) * 60 + Double(now.minute ?? 0)
        return minutes >= sunrise && minutes <= sunset
    }
}
