import Foundation

/// Calendar-day helpers. Days are local-time days that start at local midnight.
enum DayMath {
    /// `"yyyy-MM-dd"` in the calendar's time zone. Keys sort chronologically as strings.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(forKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Splits usage measured between two readings across the days it spans.
    ///
    /// Counters only tell us how much was used *between* readings, not when.
    /// If the readings straddle midnight (say 22:00 and 07:00), the bytes are
    /// shared in proportion to the time on each side: 2 h before midnight and
    /// 7 h after puts 2/9 on yesterday and 7/9 on today. That's an estimate, but
    /// a fairer one than giving it all to either day.
    ///
    /// Returns `(dayKey, bytes)` pairs, oldest first, summing exactly to `bytes`.
    static func split(bytes: Int64, from start: Date, to end: Date,
                      calendar: Calendar = .current) -> [(key: String, bytes: Int64)] {
        guard bytes > 0 else { return [] }
        let endKey = key(for: end, calendar: calendar)
        // Clock went backwards, or both readings are on the same day.
        guard start < end, key(for: start, calendar: calendar) != endKey else {
            return [(endKey, bytes)]
        }

        let total = end.timeIntervalSince(start)
        var result: [(key: String, bytes: Int64)] = []
        var assigned: Int64 = 0
        var segmentStart = start
        while segmentStart < end {
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: segmentStart))!
            let segmentEnd = min(nextMidnight, end)
            let segmentKey = key(for: segmentStart, calendar: calendar)
            if segmentEnd >= end {
                // Last segment takes the remainder so rounding never loses a byte.
                result.append((segmentKey, bytes - assigned))
            } else {
                let share = Int64((Double(bytes) * segmentEnd.timeIntervalSince(segmentStart) / total).rounded(.down))
                result.append((segmentKey, share))
                assigned += share
            }
            segmentStart = segmentEnd
        }
        return result.filter { $0.bytes > 0 }
    }
}
