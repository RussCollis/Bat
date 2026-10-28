import ArgumentParser
import BatCore
import Foundation

@main
struct BatInstaller: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bat-installer",
        abstract: "Native standalone macOS installer for sharkdp/bat (no Homebrew required).",
        discussion: """
        Downloads official precompiled binary assets for sharkdp/bat from GitHub,
        installs them to your user or system PATH, configures man pages and shell completions,
        and removes Gatekeeper quarantine attributes.
        """,
        version: "1.0.0",
        subcommands: [Install.self, Status.self, Uninstall.self, Pkg.self],
        defaultSubcommand: Install.self
    )
}

// MARK: - Install Subcommand

extension BatInstaller {
    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download and install bat directly from official GitHub releases."
        )

        @Option(name: [.short, .customLong("tag")], help: "Specify a release version tag (e.g. 'v0.26.1' or '0.26.1'). Defaults to latest.")
        var version: String?

        @Option(name: [.customLong("dir")], help: "Directory where the bat binary will be installed (default: ~/.local/bin).")
        var installDir: String?

        @Flag(name: .long, help: "Install system-wide to /usr/local/bin (requires write permissions).")
        var system: Bool = false

        @Flag(name: .long, help: "Skip installing the manpage (bat.1).")
        var noMan: Bool = false

        @Flag(name: .long, help: "Skip installing shell completions (zsh, bash, fish).")
        var noCompletions: Bool = false

        @Flag(name: [.short, .long], help: "Force overwrite of existing files.")
        var force: Bool = false

        @Flag(name: .long, help: "Perform a dry-run without downloading or writing files.")
        var dryRun: Bool = false

        func run() async throws {
            print("🦇 bat Standalone Installer")
            print("============================")

            let options = InstallationOptions(
                installDir: installDir,
                system: system,
                installMan: !noMan,
                installCompletions: !noCompletions,
                force: force,
                dryRun: dryRun
            )

            let service = InstallerService()
            do {
                let result = try await service.install(version: version, options: options) { msg in
                    print("  → \(msg)")
                }

                if dryRun {
                    print("\n✅ Dry run completed successfully. No changes were made.")
                    return
                }

                print("\n🎉 bat \(result.installedVersion) installed successfully!")
                print("   Binary: \(ShellUtils.displayPath(result.binaryPath))")
                if let man = result.manPagePath {
                    print("   Manpage: \(ShellUtils.displayPath(man))")
                }
                if !result.completionsPaths.isEmpty {
                    print("   Shell completions installed for:")
                    for path in result.completionsPaths {
                        print("     • \(ShellUtils.displayPath(path))")
                    }
                }

                if !result.isPathConfigured {
                    print("\n⚠️  Notice: \(ShellUtils.displayPath(options.installDir)) is not currently in your $PATH.")
                    print("   To run 'bat' from anywhere, add this to your shell profile (~/.zshrc):")
                    print("     export PATH=\"\(ShellUtils.displayPath(options.installDir)):$PATH\"")
                    print("   Then restart your terminal or run: source ~/.zshrc")
                } else {
                    print("\n🚀 Ready to go! Try running:")
                    print("   bat --help")
                }
            } catch {
                print("\n❌ Installation failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Status Subcommand

extension BatInstaller {
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check current bat installation status and check for updates."
        )

        func run() async throws {
            print("🦇 bat Installation Status")
            print("===========================")

            let service = InstallerService()
            print("Checking local system and GitHub releases...")
            let report = try await service.status()

            if let path = report.installedBinaryPath {
                print("  • Installed binary: \(ShellUtils.displayPath(path))")
                if let version = report.installedVersion {
                    print("  • Installed version: \(version)")
                }
            } else {
                print("  • Installed binary: None found in standard paths")
            }

            if let latest = report.latestAvailableVersion {
                print("  • Latest available release: v\(latest)")
            }

            if report.isUpdateAvailable {
                print("\n✨ An update is available! Run 'bat-installer install' to upgrade.")
            } else if report.installedBinaryPath != nil {
                print("\n✅ You have the latest version of bat installed.")
            }

            if !report.isPathConfigured && report.installedBinaryPath != nil {
                print("⚠️  Warning: The directory containing bat is not in your current $PATH.")
            }
        }
    }
}

// MARK: - Uninstall Subcommand

extension BatInstaller {
    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove bat binary, man pages, and shell completions."
        )

        @Option(name: [.customLong("dir")], help: "Directory where bat is installed (default: ~/.local/bin).")
        var installDir: String?

        @Flag(name: .long, help: "Uninstall from /usr/local/bin.")
        var system: Bool = false

        func run() async throws {
            print("🦇 bat Uninstaller")
            print("===================")

            let service = InstallerService()
            do {
                try service.uninstall(installDir: installDir, system: system) { msg in
                    print("  → \(msg)")
                }
                print("\n✅ bat uninstallation complete.")
            } catch {
                print("\n❌ Uninstallation failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Pkg Subcommand

extension BatInstaller {
    struct Pkg: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build a standalone macOS Universal .pkg installer for bat."
        )

        @Option(name: [.short, .customLong("tag")], help: "Specify a release version tag (e.g. 'v0.26.1' or '0.26.1'). Defaults to latest.")
        var version: String?

        @Option(name: [.short, .long], help: "Output directory for the generated .pkg file (default: current directory).")
        var outputDir: String = "."

        @Option(name: .long, help: "Developer ID Installer identity for code signing.")
        var sign: String?

        func run() async throws {
            print("🦇 bat macOS .pkg Builder")
            print("=========================")

            let options = PackageBuilderOptions(
                version: version,
                outputDir: outputDir,
                signIdentity: sign
            )

            let builder = PackageBuilder()
            do {
                let pkgURL = try await builder.build(options: options) { msg in
                    print("  → \(msg)")
                }
                print("\n🎉 Package built successfully:")
                print("   \(ShellUtils.displayPath(pkgURL.path))")
            } catch {
                print("\n❌ Package build failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
