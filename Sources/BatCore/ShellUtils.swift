import Foundation

/// Utility helper for executing system commands and interacting with the shell environment.
public enum ShellUtils: Sendable {

    /// Executes an external process and returns its standard output.
    @discardableResult
    public static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory = currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw InstallerError.fileOperationFailed("Failed to execute \(executable): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let combined = (stdoutString + "\n" + stderrString).trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.fileOperationFailed("Command '\(executable) \(arguments.joined(separator: " "))' failed (exit code \(process.terminationStatus)): \(combined)")
        }

        return stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes macOS Gatekeeper quarantine attribute from a file if present.
    public static func removeQuarantineAttribute(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    /// Checks if a given directory path is present in the current process's PATH environment variable.
    public static func isDirectoryInPATH(_ directoryPath: String) -> Bool {
        let normalizedTarget = (directoryPath as NSString).standardizingPath
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
            return false
        }
        let paths = pathEnv.split(separator: ":").map { (String($0) as NSString).standardizingPath }
        return paths.contains(normalizedTarget)
    }

    /// Returns a string with the user's home directory replaced with '~' for friendly display.
    public static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
