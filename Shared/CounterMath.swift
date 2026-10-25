import Foundation

/// Turns two successive raw counter readings into "bytes used in between".
///
/// The raw counters can't be trusted as a running total, for two reasons:
///
/// 1. **Wrap-around.** Each counter is a UInt32, so after 4,294,967,296 bytes
///    (4 GiB) it rolls over to 0 and keeps counting. On a ~2.4 GB/day budget
///    that happens about every two days.
/// 2. **Reboot reset.** All counters restart from 0 when the phone boots.
///
/// In both cases the new reading is *lower* than the previous one. To tell them
/// apart we use, in order:
///
/// - **Boot time** (`kern.boottime`). If it changed since the last reading, the
///   phone rebooted, and the current value is everything used since boot.
/// - **Where the old value was.** With the same boot time, a decrease is almost
///   always a wrap. A wrap is only plausible if the counter was in the upper half
///   (≥ 2 GiB) of its range: from a lower value it would need more than 2 GiB of
///   traffic between two readings. A drop from the lower half is treated as the
///   interface resetting its counters (e.g. the cellular context was torn down and
///   recreated), which counts the same way as a reboot.
///
/// Known limit: if 4 GiB or more passes on one counter between two readings, a
/// whole wrap is invisible and that usage is lost. Frequent readings (app
/// foreground, background refresh, widget reloads) keep the gap small.
enum CounterMath {
    /// 2^32: the value at which a UInt32 counter wraps to 0.
    static let wrapModulus: Int64 = 1 << 32

    /// Below this previous value, a decrease is treated as a reset, not a wrap.
    static let wrapPlausibilityFloor: UInt32 = 1 << 31

    /// Bytes used on one counter between `previous` and `current`.
    ///
    /// - Parameters:
    ///   - previous: The last stored reading, or nil if this counter (interface)
    ///     didn't exist at the last reading.
    ///   - current: The reading now.
    ///   - rebooted: True if the boot time changed since `previous` was taken.
    static func delta(previous: UInt32?, current: UInt32, rebooted: Bool) -> Int64 {
        // Rebooted: every counter restarted at 0, so the current value is exactly
        // what has been used since boot. Traffic between the last reading and the
        // shutdown is unrecoverable.
        if rebooted { return Int64(current) }

        // New interface since the last reading: its counter started at 0 when it
        // appeared, so everything on it is new.
        guard let previous else { return Int64(current) }

        // Normal case: the counter only went up.
        if current >= previous { return Int64(current) - Int64(previous) }

        // The counter went down without a reboot.
        if previous >= wrapPlausibilityFloor {
            // Wrap-around: it counted from `previous` up to 2^32, rolled over to 0,
            // then counted up to `current`.
            //   e.g. previous = 4,294,000,000, current = 1,000,000
            //   delta = (4,294,967,296 − 4,294,000,000) + 1,000,000 = 1,967,296
            return (wrapModulus - Int64(previous)) + Int64(current)
        }
        // Interface reset: counting restarted from 0.
        return Int64(current)
    }

    /// Sums `delta` over every counter in the current reading.
    /// Counters that disappeared since the last reading contribute nothing.
    static func totalDelta(previous: [String: UInt32], current: [String: UInt32], rebooted: Bool) -> Int64 {
        current.reduce(Int64(0)) { sum, entry in
            sum + delta(previous: previous[entry.key], current: entry.value, rebooted: rebooted)
        }
    }

    /// Reboot detection from two independent signals:
    ///
    /// - System uptime (monotonic, time since boot) went *down*: only a reboot
    ///   can do that.
    /// - Boot time moved by more than a minute. `kern.boottime` is derived from
    ///   the wall clock, so network time sync nudges it by a few seconds. The
    ///   60 s tolerance ignores that, and no real reboot cycle is that fast.
    ///
    /// A false positive would re-count everything since boot, so this errs on
    /// the side of "not rebooted"; the decrease heuristic in `delta` still
    /// catches a reset that slips through.
    static func didReboot(lastBoot: Date?, currentBoot: Date?,
                          lastUptime: TimeInterval?, currentUptime: TimeInterval) -> Bool {
        if let lastUptime, currentUptime < lastUptime { return true }
        guard let lastBoot, let currentBoot else { return false }
        return abs(currentBoot.timeIntervalSince(lastBoot)) > 60
    }
}
