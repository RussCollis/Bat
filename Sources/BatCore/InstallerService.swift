import Foundation

/// Options configuring the installation.
public struct InstallationOptions: Sendable {
    public var installDir: String
    public var installMan: Bool
    public var installCompletions: Bool
    public var force: Bool
    public var dryRun: Bool

    public init(
        installDir: String? = nil,
        system: Bool = false,
        installMan: Bool = true,
        installCompletions: Bool = true,
        force: Bool = false,
        dryRun: Bool = false
    ) {
        if let dir = installDir, !dir.isEmpty {
            self.installDir = (dir as NSString).expandingTildeInPath
        } else if system {
            self.installDir = "/usr/local/bin"
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.installDir = (home as NSString).appendingPathComponent(".local/bin")
        }
        self.installMan = installMan
        self.installCompletions = installCompletions
        self.force = force
        self.dryRun = dryRun
    }
}

/// The outcome of an installation run.
public struct InstallationResult: Sendable {
    public let binaryPath: String
    public let installedVersion: String
    public let manPagePath: String?
    public let completionsPaths: [String]
    public let isPathConfigured: Bool
}

/// Status report about current bat installations on the system.
public struct StatusReport: Sendable {
    public let installedBinaryPath: String?
    public let installedVersion: String?
    public let latestAvailableVersion: String?
    public let isUpdateAvailable: Bool
    public let isPathConfigured: Bool
}

/// Main service responsible for downloading, extracting, installing, and removing bat.
public struct InstallerService: Sendable {
    private var fileManager: FileManager { FileManager.default }

    public init() {}

    /// Performs the installation of sharkdp/bat.
    public func install(
        version: String? = nil,
        options: InstallationOptions,
        logger: @Sendable (String) -> Void = { _ in }
    ) async throws -> InstallationResult {
        let arch = try SystemArchitecture.current()
        logger("Detected platform: macOS (\(arch.displayName))")

        logger("Resolving release metadata from sharkdp/bat...")
        let release = try await GitHubRelease.resolve(version: version, architecture: arch)
        logger("Target release: \(release.tag) (asset: \(release.assetName))")

        let binaryDestination = (options.installDir as NSString).appendingPathComponent("bat")

        // Check if existing binary is present
        if fileManager.fileExists(atPath: binaryDestination) && !options.force {
            if let existingVersion = try? ShellUtils.runProcess(executable: binaryDestination, arguments: ["--version"]) {
                logger("Found existing installation: \(existingVersion) at \(ShellUtils.displayPath(binaryDestination))")
            }
            if !options.dryRun {
                logger("Replacing existing binary (pass --force to suppress this notice).")
            }
        }

        if options.dryRun {
            logger("\n[DRY RUN] Would perform the following actions:")
            logger("  1. Download: \(release.downloadURL)")
            logger("  2. Install binary to: \(ShellUtils.displayPath(binaryDestination))")
            if options.installMan {
                let manDir = manDirectory(for: options.installDir)
                logger("  3. Install manpage to: \(ShellUtils.displayPath((manDir as NSString).appendingPathComponent("man1/bat.1")))")
            }
            if options.installCompletions {
                logger("  4. Install shell completions (zsh, bash, fish)")
            }
            let pathInEnv = ShellUtils.isDirectoryInPATH(options.installDir)
            return InstallationResult(
                binaryPath: binaryDestination,
                installedVersion: release.version,
                manPagePath: options.installMan ? (manDirectory(for: options.installDir) as NSString).appendingPathComponent("man1/bat.1") : nil,
                completionsPaths: [],
                isPathConfigured: pathInEnv
            )
        }

        // Create temporary directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("bat-install-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Download archive
        logger("Downloading \(release.assetName)...")
        let archiveLocalURL = tempDir.appendingPathComponent(release.assetName)
        let (downloadedURL, downloadResponse) = try await URLSession.shared.download(from: release.downloadURL)

        guard let httpResponse = downloadResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw InstallerError.downloadFailed("Download returned HTTP status \((downloadResponse as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        try fileManager.moveItem(at: downloadedURL, to: archiveLocalURL)

        // Extract archive
        logger("Extracting archive...")
        let extractDir = tempDir.appendingPathComponent("extracted")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        try ShellUtils.runProcess(
            executable: "/usr/bin/tar",
            arguments: ["-xzf", archiveLocalURL.path, "-C", extractDir.path]
        )

        // Find the extracted root folder (e.g. bat-v0.26.1-aarch64-apple-darwin)
        guard let extractedContents = try? fileManager.contentsOfDirectory(atPath: extractDir.path),
              let innerFolder = extractedContents.first(where: { $0.hasPrefix("bat-") }) else {
            throw InstallerError.extractionFailed("Failed to find extracted release directory in tarball.")
        }

        let releaseDir = extractDir.appendingPathComponent(innerFolder)
        let sourceBinary = releaseDir.appendingPathComponent("bat")

        guard fileManager.fileExists(atPath: sourceBinary.path) else {
            throw InstallerError.binaryNotFoundInArchive
        }

        // Ensure target directory exists
        try fileManager.createDirectory(atPath: options.installDir, withIntermediateDirectories: true)

        // If target file exists, remove it first
        if fileManager.fileExists(atPath: binaryDestination) {
            try fileManager.removeItem(atPath: binaryDestination)
        }

        // Copy binary
        logger("Installing binary to \(ShellUtils.displayPath(binaryDestination))...")
        try fileManager.copyItem(atPath: sourceBinary.path, toPath: binaryDestination)

        // Make executable (chmod 755)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryDestination)

        // Remove com.apple.quarantine attribute
        ShellUtils.removeQuarantineAttribute(at: binaryDestination)

        // Verify the binary works
        logger("Verifying binary...")
        let verifiedOutput = try ShellUtils.runProcess(executable: binaryDestination, arguments: ["--version"])
        logger("Verified: \(verifiedOutput)")

        // Install man page
        var installedManPath: String?
        if options.installMan {
            let sourceMan = releaseDir.appendingPathComponent("bat.1")
            if fileManager.fileExists(atPath: sourceMan.path) {
                let manBase = manDirectory(for: options.installDir)
                let man1Dir = (manBase as NSString).appendingPathComponent("man1")
                try? fileManager.createDirectory(atPath: man1Dir, withIntermediateDirectories: true)
                let destMan = (man1Dir as NSString).appendingPathComponent("bat.1")
                if fileManager.fileExists(atPath: destMan) {
                    try? fileManager.removeItem(atPath: destMan)
                }
                if (try? fileManager.copyItem(atPath: sourceMan.path, toPath: destMan)) != nil {
                    installedManPath = destMan
                    logger("Installed man page to \(ShellUtils.displayPath(destMan))")
                }
            }
        }

        // Install shell completions
        var installedCompletions: [String] = []
        if options.installCompletions {
            let autocompleteDir = releaseDir.appendingPathComponent("autocomplete")
            let completions = installShellCompletions(from: autocompleteDir, logger: logger)
            installedCompletions.append(contentsOf: completions)
        }

        let isPathInEnv = ShellUtils.isDirectoryInPATH(options.installDir)

        return InstallationResult(
            binaryPath: binaryDestination,
            installedVersion: release.version,
            manPagePath: installedManPath,
            completionsPaths: installedCompletions,
            isPathConfigured: isPathInEnv
        )
    }

    /// Checks the status of bat on the host system.
    public func status() async throws -> StatusReport {
        let binaryPath = findInstalledBinary()
        var currentVersion: String?

        if let path = binaryPath {
            if let output = try? ShellUtils.runProcess(executable: path, arguments: ["--version"]) {
                currentVersion = output
            }
        }

        let latestTag = try? await GitHubRelease.fetchLatestReleaseTag()
        let cleanLatest = latestTag?.hasPrefix("v") == true ? String(latestTag!.dropFirst()) : latestTag

        var isUpdateAvailable = false
        if let current = currentVersion, let latest = cleanLatest {
            // Check if current version output contains the latest version number
            if !current.contains(latest) {
                isUpdateAvailable = true
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let localBin = (home as NSString).appendingPathComponent(".local/bin")
        let isPathInEnv = ShellUtils.isDirectoryInPATH(localBin) || (binaryPath != nil && ShellUtils.isDirectoryInPATH((binaryPath! as NSString).deletingLastPathComponent))

        return StatusReport(
            installedBinaryPath: binaryPath,
            installedVersion: currentVersion,
            latestAvailableVersion: cleanLatest,
            isUpdateAvailable: isUpdateAvailable,
            isPathConfigured: isPathInEnv
        )
    }

    /// Uninstalls bat, its man page, and completions.
    public func uninstall(
        installDir: String? = nil,
        system: Bool = false,
        logger: @Sendable (String) -> Void = { _ in }
    ) throws {
        let targetDir: String
        if let dir = installDir, !dir.isEmpty {
            targetDir = (dir as NSString).expandingTildeInPath
        } else if system {
            targetDir = "/usr/local/bin"
        } else {
            let home = fileManager.homeDirectoryForCurrentUser.path
            targetDir = (home as NSString).appendingPathComponent(".local/bin")
        }

        let binaryPath = (targetDir as NSString).appendingPathComponent("bat")
        if fileManager.fileExists(atPath: binaryPath) {
            try fileManager.removeItem(atPath: binaryPath)
            logger("Removed binary: \(ShellUtils.displayPath(binaryPath))")
        } else {
            logger("Binary not found at \(ShellUtils.displayPath(binaryPath))")
        }

        // Clean man page
        let manBase = manDirectory(for: targetDir)
        let man1File = (manBase as NSString).appendingPathComponent("man1/bat.1")
        if fileManager.fileExists(atPath: man1File) {
            try? fileManager.removeItem(atPath: man1File)
            logger("Removed manpage: \(ShellUtils.displayPath(man1File))")
        }

        // Clean completions
        let home = fileManager.homeDirectoryForCurrentUser.path
        let possibleCompletions = [
            (home as NSString).appendingPathComponent(".zfunc/_bat"),
            (home as NSString).appendingPathComponent(".config/fish/completions/bat.fish"),
            (home as NSString).appendingPathComponent(".local/share/bash-completion/completions/bat")
        ]

        for path in possibleCompletions {
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
                logger("Removed completion: \(ShellUtils.displayPath(path))")
            }
        }
    }

    // MARK: - Private Helpers

    private func manDirectory(for installDir: String) -> String {
        if installDir == "/usr/local/bin" {
            return "/usr/local/share/man"
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".local/share/man")
    }

    private func findInstalledBinary() -> String? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            (home as NSString).appendingPathComponent(".local/bin/bat"),
            "/usr/local/bin/bat",
            "/opt/homebrew/bin/bat"
        ]

        for path in candidates {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Check via `which bat`
        if let whichPath = try? ShellUtils.runProcess(executable: "/usr/bin/which", arguments: ["bat"]),
           !whichPath.isEmpty && fileManager.fileExists(atPath: whichPath) {
            return whichPath
        }

        return nil
    }

    private func installShellCompletions(
        from autocompleteDir: URL,
        logger: @Sendable (String) -> Void
    ) -> [String] {
        var installed: [String] = []
        let home = fileManager.homeDirectoryForCurrentUser.path

        // ZSH: ~/.zfunc/_bat
        let zshSource = autocompleteDir.appendingPathComponent("bat.zsh")
        if fileManager.fileExists(atPath: zshSource.path) {
            let zfuncDir = (home as NSString).appendingPathComponent(".zfunc")
            let zshDest = (zfuncDir as NSString).appendingPathComponent("_bat")
            try? fileManager.createDirectory(atPath: zfuncDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: zshDest) {
                try? fileManager.removeItem(atPath: zshDest)
            }
            if (try? fileManager.copyItem(atPath: zshSource.path, toPath: zshDest)) != nil {
                installed.append(zshDest)
                logger("Installed zsh completion to \(ShellUtils.displayPath(zshDest))")
            }
        }

        // Fish: ~/.config/fish/completions/bat.fish
        let fishSource = autocompleteDir.appendingPathComponent("bat.fish")
        if fileManager.fileExists(atPath: fishSource.path) {
            let fishDir = (home as NSString).appendingPathComponent(".config/fish/completions")
            let fishDest = (fishDir as NSString).appendingPathComponent("bat.fish")
            try? fileManager.createDirectory(atPath: fishDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fishDest) {
                try? fileManager.removeItem(atPath: fishDest)
            }
            if (try? fileManager.copyItem(atPath: fishSource.path, toPath: fishDest)) != nil {
                installed.append(fishDest)
                logger("Installed fish completion to \(ShellUtils.displayPath(fishDest))")
            }
        }

        // Bash: ~/.local/share/bash-completion/completions/bat
        let bashSource = autocompleteDir.appendingPathComponent("bat.bash")
        if fileManager.fileExists(atPath: bashSource.path) {
            let bashDir = (home as NSString).appendingPathComponent(".local/share/bash-completion/completions")
            let bashDest = (bashDir as NSString).appendingPathComponent("bat")
            try? fileManager.createDirectory(atPath: bashDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: bashDest) {
                try? fileManager.removeItem(atPath: bashDest)
            }
            if (try? fileManager.copyItem(atPath: bashSource.path, toPath: bashDest)) != nil {
                installed.append(bashDest)
                logger("Installed bash completion to \(ShellUtils.displayPath(bashDest))")
            }
        }

        return installed
    }
}
