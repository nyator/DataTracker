import Darwin
import Foundation

/// Reads the kernel's raw byte counters for the cellular interfaces.
///
/// iOS exposes one `pdp_ip<N>` interface per cellular data context (pdp_ip0 is
/// normally internet; others can appear for MMS, visual voicemail, eSIM lines…).
/// The AF_LINK entry of each interface carries a `struct if_data` whose
/// `ifi_ibytes` / `ifi_obytes` fields are **UInt32** — they count bytes
/// received/sent since boot and wrap back to 0 after 4 GiB.
///
/// These are raw readings only. `CounterMath` turns successive readings into
/// usage, handling wrap-around and reboots.
enum CellularCounters {
    /// One entry per counter, e.g. `"pdp_ip0.rx": 123456`, `"pdp_ip0.tx": 7890`.
    ///
    /// Inbound and outbound are kept as separate keys rather than summed, on
    /// purpose: each 32-bit counter wraps independently. If we summed them first,
    /// one counter wrapping would look like the *sum* going down, and we could
    /// no longer tell a wrap from a reset.
    static func read() -> [String: UInt32] {
        var result: [String: UInt32] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }

        var cursor = head
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next

            guard let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }

            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("pdp_ip") else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name + ".rx"] = stats.ifi_ibytes
            result[name + ".tx"] = stats.ifi_obytes
        }
        return result
    }

    /// When the device last booted (`kern.boottime`). Counters restart from 0
    /// at boot, so a changed boot time is a definite reboot signal.
    static func bootTime() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
