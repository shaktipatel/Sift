import Foundation

public enum NetFareStatistics {
    public static func median(_ values: [Double]) -> Double? {
        let clean = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !clean.isEmpty else { return nil }
        let middle = clean.count / 2
        if clean.count.isMultiple(of: 2) {
            return (clean[middle - 1] + clean[middle]) / 2
        }
        return clean[middle]
    }

    public static func trimmedMedian(_ values: [Double]) -> Double? {
        let clean = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard clean.count > 4, let center = median(clean) else { return median(clean) }

        // Use a median-absolute-deviation fence instead of always trimming both
        // ends. This preserves a legitimate low/high sample while rejecting a
        // single pathological reading on either side of the distribution.
        let deviations = clean.map { abs($0 - center) }
        guard let mad = median(deviations), mad > 0 else {
            return median(clean.filter { $0 == center }) ?? center
        }
        let fence = 3.5 * mad
        let inliers = clean.filter { abs($0 - center) <= fence }
        return median(inliers) ?? center
    }

    public static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        return median(values.map { abs($0 - center) })
    }

    public static func throughputMbps(bytes: Int64, seconds: Double) -> Double? {
        guard bytes > 0, seconds.isFinite, seconds > 0 else { return nil }
        let megabits = Double(bytes) * 8 / 1_000_000
        let value = megabits / seconds
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    public static func consistencyPercent(_ values: [Double]) -> Double? {
        guard let center = trimmedMedian(values), center > 0,
              let deviation = medianAbsoluteDeviation(values) else { return nil }
        let percent = 100 * (1 - min(1, deviation / center))
        return min(100, max(0, percent))
    }

    public static func jitterMilliseconds(_ values: [Double]) -> Double? {
        let clean = values.filter { $0.isFinite && $0 >= 0 }
        guard clean.count > 1 else { return nil }
        let differences = zip(clean.dropFirst(), clean).map { abs($0 - $1) }
        return median(differences)
    }
}
