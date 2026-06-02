import Foundation
import Darwin

/// Utilitaires réseau : détection de l'IP locale et du sous-réseau pour le scan.
enum NetworkUtils {

    /// Première adresse IPv4 d'une interface active (Wi-Fi/Ethernet : en0/en1).
    static func localIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = pointer {
            defer { pointer = ptr.pointee.ifa_next }
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr,
                  (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostBuffer, socklen_t(hostBuffer.count),
                        nil, 0, NI_NUMERICHOST)
            address = String(cString: hostBuffer)
            break
        }
        return address
    }

    /// "192.168.1.41" -> "192.168.1"
    static func subnetBase(from ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }
}
