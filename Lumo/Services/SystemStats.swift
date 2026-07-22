import Foundation
import Darwin

/// Statistiques système du Mac (CPU / RAM) pour les afficher sur la matrice.
enum SystemStats {

    /// Pourcentage de RAM utilisée (instantané).
    static func memoryUsagePercent() -> Int {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // sysconf plutôt que la globale `vm_page_size` (variable mutable côté Darwin).
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return 0 }
        return min(100, Int(Double(used) / Double(total) * 100))
    }

    /// Relevé précédent, gardé pour calculer un delta. Isolé sur le main actor :
    /// les seuls appelants (stations d'affichage et d'alertes) y vivent déjà.
    @MainActor private static var previousCPU: host_cpu_load_info?

    /// Pourcentage d'utilisation CPU (différence entre deux relevés ; appeler ~2× à 0,5 s d'écart).
    @MainActor static func cpuUsagePercent() -> Int {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previousCPU = info }
        guard let prev = previousCPU else { return 0 }

        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, Int((user + system + nice) / total * 100))
    }
}
