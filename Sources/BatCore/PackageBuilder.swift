import Foundation

/// Options configuring the generation of a macOS .pkg installer.
public struct PackageBuilderOptions: Sendable {
    public var version: String?
    public var outputDir: String
    public var signIdentity: String?

    public init(version: String? = nil, outputDir: String = ".", signIdentity: String? = nil) {
        self.version = version
        self.outputDir = (outputDir as NSString).expandingTildeInPath
        self.signIdentity = signIdentity
    }
}

/// Service that generates a Universal macOS .pkg installer for sharkdp/bat.
public struct PackageBuilder: Sendable {
    private var fileManager: FileManager { FileManager.default }

    public init() {}

    /// Builds a Universal 2 macOS .pkg installer containing sharkdp/bat.
    @discardableResult
    public func build(
        options: PackageBuilderOptions,
        logger: @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        logger("Resolving release version...")
        let latestTag = try await GitHubRelease.fetchLatestReleaseTag()
        let resolvedTag: String
        if let v = options.version, !v.trimmingCharacters(in: .whitespaces).isEmpty {
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            resolvedTag = trimmed.hasPrefix("v") ? trimmed : "v\(trimmed)"
        } else {
            resolvedTag = latestTag
        }

        let rawVersion = resolvedTag.hasPrefix("v") ? String(resolvedTag.dropFirst()) : resolvedTag
        logger("Building package for bat \(resolvedTag)...")

        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("bat-pkg-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let arm64Asset = "bat-\(resolvedTag)-aarch64-apple-darwin.tar.gz"
        let x86_64Asset = "bat-\(resolvedTag)-x86_64-apple-darwin.tar.gz"

        let arm64URL = URL(string: "https://github.com/sharkdp/bat/releases/download/\(resolvedTag)/\(arm64Asset)")!
        let x86_64URL = URL(string: "https://github.com/sharkdp/bat/releases/download/\(resolvedTag)/\(x86_64Asset)")!

        logger("Downloading Apple Silicon (arm64) archive...")
        let (arm64Downloaded, _) = try await URLSession.shared.download(from: arm64URL)
        let arm64Local = tempDir.appendingPathComponent(arm64Asset)
        try fileManager.moveItem(at: arm64Downloaded, to: arm64Local)

        logger("Downloading Intel (x86_64) archive...")
        let (x86_64Downloaded, _) = try await URLSession.shared.download(from: x86_64URL)
        let x86_64Local = tempDir.appendingPathComponent(x86_64Asset)
        try fileManager.moveItem(at: x86_64Downloaded, to: x86_64Local)

        // Extract both
        logger("Extracting release archives...")
        let arm64Extract = tempDir.appendingPathComponent("arm64")
        let x86_64Extract = tempDir.appendingPathComponent("x86_64")
        try fileManager.createDirectory(at: arm64Extract, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: x86_64Extract, withIntermediateDirectories: true)

        try ShellUtils.runProcess(executable: "/usr/bin/tar", arguments: ["-xzf", arm64Local.path, "-C", arm64Extract.path])
        try ShellUtils.runProcess(executable: "/usr/bin/tar", arguments: ["-xzf", x86_64Local.path, "-C", x86_64Extract.path])

        guard let arm64DirName = try? fileManager.contentsOfDirectory(atPath: arm64Extract.path).first(where: { $0.hasPrefix("bat-") }),
              let x86_64DirName = try? fileManager.contentsOfDirectory(atPath: x86_64Extract.path).first(where: { $0.hasPrefix("bat-") }) else {
            throw InstallerError.extractionFailed("Could not locate extracted folders in release archives.")
        }

        let arm64Dir = arm64Extract.appendingPathComponent(arm64DirName)
        let x86_64Dir = x86_64Extract.appendingPathComponent(x86_64DirName)

        // Setup Payload hierarchy
        let payloadDir = tempDir.appendingPathComponent("payload")
        let binDir = payloadDir.appendingPathComponent("usr/local/bin")
        let manDir = payloadDir.appendingPathComponent("usr/local/share/man/man1")
        let zshCompDir = payloadDir.appendingPathComponent("usr/local/share/zsh/site-functions")
        let fishCompDir = payloadDir.appendingPathComponent("usr/local/share/fish/vendor_completions.d")
        let bashCompDir = payloadDir.appendingPathComponent("usr/local/etc/bash_completion.d")

        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: manDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: zshCompDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fishCompDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bashCompDir, withIntermediateDirectories: true)

        // Lipo Universal 2 binary
        logger("Creating Universal 2 binary with lipo...")
        let universalBat = binDir.appendingPathComponent("bat")
        try ShellUtils.runProcess(
            executable: "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64Dir.appendingPathComponent("bat").path,
                x86_64Dir.appendingPathComponent("bat").path,
                "-output",
                universalBat.path
            ]
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: universalBat.path)

        // Man page
        let sourceMan = arm64Dir.appendingPathComponent("bat.1")
        if fileManager.fileExists(atPath: sourceMan.path) {
            try? fileManager.copyItem(at: sourceMan, to: manDir.appendingPathComponent("bat.1"))
        }

        // Completions
        let zshSource = arm64Dir.appendingPathComponent("autocomplete/bat.zsh")
        if fileManager.fileExists(atPath: zshSource.path) {
            try? fileManager.copyItem(at: zshSource, to: zshCompDir.appendingPathComponent("_bat"))
        }
        let fishSource = arm64Dir.appendingPathComponent("autocomplete/bat.fish")
        if fileManager.fileExists(atPath: fishSource.path) {
            try? fileManager.copyItem(at: fishSource, to: fishCompDir.appendingPathComponent("bat.fish"))
        }
        let bashSource = arm64Dir.appendingPathComponent("autocomplete/bat.bash")
        if fileManager.fileExists(atPath: bashSource.path) {
            try? fileManager.copyItem(at: bashSource, to: bashCompDir.appendingPathComponent("bat"))
        }

        // Postinstall script
        let scriptsDir = tempDir.appendingPathComponent("scripts")
        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let postinstallPath = scriptsDir.appendingPathComponent("postinstall")
        let postinstallContent = """
        #!/bin/sh
        chown -R root:admin /usr/local/bin/bat
        chmod 755 /usr/local/bin/bat
        xattr -d com.apple.quarantine /usr/local/bin/bat 2>/dev/null || true
        exit 0
        """
        try postinstallContent.write(to: postinstallPath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postinstallPath.path)

        // Resources
        let resourcesDir = tempDir.appendingPathComponent("resources")
        try fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        let licenseSource = arm64Dir.appendingPathComponent("LICENSE-MIT")
        if fileManager.fileExists(atPath: licenseSource.path) {
            try? fileManager.copyItem(at: licenseSource, to: resourcesDir.appendingPathComponent("LICENSE.txt"))
        }

        let welcomeHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 13px; line-height: 1.6;">
        <h2>bat v\(rawVersion)</h2>
        <p>A cat clone with syntax highlighting and Git integration.</p>
        <p>Installs native Universal 2 (Apple Silicon & Intel) binary to <code>/usr/local/bin/bat</code> without Homebrew.</p>
        </body>
        </html>
        """
        try welcomeHTML.write(to: resourcesDir.appendingPathComponent("welcome.html"), atomically: true, encoding: .utf8)

        // Build component pkg
        logger("Running pkgbuild...")
        let componentPkg = tempDir.appendingPathComponent("bat-component.pkg")
        try ShellUtils.runProcess(
            executable: "/usr/bin/pkgbuild",
            arguments: [
                "--root", payloadDir.path,
                "--scripts", scriptsDir.path,
                "--identifier", "io.github.sharkdp.bat",
                "--version", rawVersion,
                "--install-location", "/",
                componentPkg.path
            ]
        )

        // Distribution XML
        let distXMLPath = tempDir.appendingPathComponent("Distribution.xml")
        let distXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <installer-gui-script minSpecVersion="2">
            <title>bat \(resolvedTag)</title>
            <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
            <welcome file="welcome.html" mime-type="text/html"/>
            <license file="LICENSE.txt" mime-type="text/plain"/>
            <choices-outline>
                <line choice="default">
                    <line choice="io.github.sharkdp.bat"/>
                </line>
            </choices-outline>
            <choice id="default"/>
            <choice id="io.github.sharkdp.bat" visible="false">
                <pkg-ref id="io.github.sharkdp.bat"/>
            </choice>
            <pkg-ref id="io.github.sharkdp.bat" version="\(rawVersion)" onConclusion="none">bat-component.pkg</pkg-ref>
        </installer-gui-script>
        """
        try distXML.write(to: distXMLPath, atomically: true, encoding: .utf8)

        // Output pkg destination
        let outputPkgName = "bat-\(rawVersion)-universal.pkg"
        let outputPkgURL = URL(fileURLWithPath: options.outputDir).appendingPathComponent(outputPkgName)
        try fileManager.createDirectory(atPath: options.outputDir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: outputPkgURL.path) {
            try? fileManager.removeItem(at: outputPkgURL)
        }

        logger("Synthesizing final distribution with productbuild...")
        var productArgs = [
            "--distribution", distXMLPath.path,
            "--package-path", tempDir.path,
            "--resources", resourcesDir.path
        ]
        if let identity = options.signIdentity, !identity.isEmpty {
            productArgs.append(contentsOf: ["--sign", identity])
        }
        productArgs.append(outputPkgURL.path)

        try ShellUtils.runProcess(executable: "/usr/bin/productbuild", arguments: productArgs)

        logger("Finished creating package: \(outputPkgURL.path)")
        return outputPkgURL
    }
}
