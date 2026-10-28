import Foundation

/// Represents the CPU architecture of the host machine.
public enum SystemArchitecture: String, Sendable, CaseIterable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"

    /// The architecture identifier used in sharkdp/bat GitHub release asset filenames.
    public var archiveArch: String {
        switch self {
        case .arm64:
            return "aarch64"
        case .x86_64:
            return "x86_64"
        }
    }

    /// User-friendly name.
    public var displayName: String {
        switch self {
        case .arm64:
            return "Apple Silicon (arm64)"
        case .x86_64:
            return "Intel (x86_64)"
        }
    }

    /// Detects the host architecture.
    public static func current() throws -> SystemArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
        if machine == "arm64" || machine == "aarch64" {
            return .arm64
        } else if machine == "x86_64" {
            return .x86_64
        } else {
            throw InstallerError.unsupportedArchitecture(machine)
        }
        #endif
    }
}
