import Foundation

/// Errors that can occur during the installation process.
public enum InstallerError: LocalizedError, Sendable, Equatable {
    case unsupportedOS(String)
    case unsupportedArchitecture(String)
    case invalidURL(String)
    case apiError(String)
    case releaseNotFound(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case fileOperationFailed(String)
    case verificationFailed(String)
    case binaryNotFoundInArchive
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedOS(let os):
            return "Unsupported operating system: \(os). This installer only supports macOS."
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch). Supported architectures: Apple Silicon (arm64) and Intel (x86_64)."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .apiError(let msg):
            return "GitHub API request failed: \(msg)"
        case .releaseNotFound(let msg):
            return "Release not found: \(msg)"
        case .downloadFailed(let msg):
            return "Failed to download asset: \(msg)"
        case .extractionFailed(let msg):
            return "Failed to extract tarball archive: \(msg)"
        case .fileOperationFailed(let msg):
            return "File operation error: \(msg)"
        case .verificationFailed(let msg):
            return "Installation verification failed: \(msg)"
        case .binaryNotFoundInArchive:
            return "Could not find 'bat' executable within the extracted release archive."
        case .userCancelled:
            return "Operation cancelled by user."
        }
    }
}
