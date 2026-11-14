import Foundation
import Darwin

/// عدّاد خام (32-bit) لواجهة شبكة واحدة كما يعطيه النظام.
struct IfBytes: Codable, Equatable {
    var rx: UInt32
    var tx: UInt32
}

typealias Snapshot = [String: IfBytes]

/// قراءة عدّادات الشبكة من النظام عبر getifaddrs.
/// en0      = واي فاي
/// pdp_ip*  = بيانات الجوال (شبكة الشركة)
enum NetworkCounters {

    static func read() -> Snapshot {
        var result: Snapshot = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            cursor = ifa.ifa_next

            guard let addr = ifa.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = ifa.ifa_data else { continue }

            let name = String(cString: ifa.ifa_name)
            guard name == "en0" || name.hasPrefix("pdp_ip") else { continue }

            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            result[name] = IfBytes(rx: data.ifi_ibytes, tx: data.ifi_obytes)
        }
        return result
    }

    /// الفرق بين قراءتين مع مراعاة أن العدّاد 32-bit ويلف بعد 4GB.
    static func delta(_ new: UInt32, _ old: UInt32) -> UInt64 {
        if new >= old { return UInt64(new - old) }
        return UInt64(UInt32.max - old) + UInt64(new) + 1
    }

    /// وقت آخر إعادة تشغيل للجهاز (لاكتشاف أن العدّادات اتصفّرت).
    static func bootTime() -> TimeInterval {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(tv.tv_sec)
    }
}

enum ByteFormat {
    static func string(_ bytes: Double) -> String {
        let mb = bytes / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", bytes / 1024)
    }
}
