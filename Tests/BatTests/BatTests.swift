import Foundation
import Testing
@testable import BatCore

@Suite("Bat Installer Tests")
struct BatInstallerTests {

    @Test("System architecture detection returns valid platform")
    func testArchitectureDetection() throws {
        let arch = try SystemArchitecture.current()
        #expect(arch == .arm64 || arch == .x86_64)

        #expect(SystemArchitecture.arm64.archiveArch == "aarch64")
        #expect(SystemArchitecture.x86_64.archiveArch == "x86_64")
        #expect(!arch.displayName.isEmpty)
    }

    @Test("GitHub release URL and asset name construction")
    func testReleaseURLConstruction() throws {
        let releaseWithV = try GitHubRelease(tag: "v0.26.1", architecture: .arm64)
        #expect(releaseWithV.tag == "v0.26.1")
        #expect(releaseWithV.version == "0.26.1")
        #expect(releaseWithV.assetName == "bat-v0.26.1-aarch64-apple-darwin.tar.gz")
        #expect(releaseWithV.downloadURL.absoluteString == "https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-aarch64-apple-darwin.tar.gz")

        // Without leading 'v'
        let releaseWithoutV = try GitHubRelease(tag: "0.26.1", architecture: .x86_64)
        #expect(releaseWithoutV.tag == "v0.26.1")
        #expect(releaseWithoutV.version == "0.26.1")
        #expect(releaseWithoutV.assetName == "bat-v0.26.1-x86_64-apple-darwin.tar.gz")
        #expect(releaseWithoutV.downloadURL.absoluteString == "https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-apple-darwin.tar.gz")
    }

    @Test("Installation options path defaults and expansion")
    func testInstallationOptions() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Default user options
        let defaultOptions = InstallationOptions()
        #expect(defaultOptions.installDir == (home as NSString).appendingPathComponent(".local/bin"))
        #expect(defaultOptions.installMan == true)
        #expect(defaultOptions.installCompletions == true)
        #expect(defaultOptions.dryRun == false)

        // System option
        let systemOptions = InstallationOptions(system: true)
        #expect(systemOptions.installDir == "/usr/local/bin")

        // Custom path with tilde
        let customOptions = InstallationOptions(installDir: "~/custom/bin")
        #expect(customOptions.installDir == (home as NSString).appendingPathComponent("custom/bin"))
    }

    @Test("ShellUtils path display formatting")
    func testPathDisplay() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let localPath = (home as NSString).appendingPathComponent(".local/bin")
        let displayed = ShellUtils.displayPath(localPath)
        #expect(displayed == "~/.local/bin")

        let systemPath = "/usr/local/bin"
        #expect(ShellUtils.displayPath(systemPath) == "/usr/local/bin")
    }
}
