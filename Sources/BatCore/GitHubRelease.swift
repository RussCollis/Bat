import Foundation

/// Delegate to intercept HTTP redirection and capture the target location.
private final class RedirectCaptureDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var redirectedURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        self.redirectedURL = request.url
        // Return nil to stop automatic redirection and inspect the response directly
        return nil
    }
}

/// Represents a GitHub release of sharkdp/bat.
public struct GitHubRelease: Sendable {
    public let repository: String
    public let tag: String
    public let version: String
    public let architecture: SystemArchitecture
    public let assetName: String
    public let downloadURL: URL

    public init(
        repository: String = "sharkdp/bat",
        tag: String,
        architecture: SystemArchitecture
    ) throws {
        self.repository = repository
        self.tag = tag.hasPrefix("v") ? tag : "v\(tag)"
        self.version = self.tag.hasPrefix("v") ? String(self.tag.dropFirst()) : self.tag
        self.architecture = architecture
        self.assetName = "bat-\(self.tag)-\(architecture.archiveArch)-apple-darwin.tar.gz"

        let urlString = "https://github.com/\(repository)/releases/download/\(self.tag)/\(self.assetName)"
        guard let url = URL(string: urlString) else {
            throw InstallerError.invalidURL(urlString)
        }
        self.downloadURL = url
    }

    /// Resolves the release for either a requested version string or the latest available version.
    public static func resolve(
        version: String? = nil,
        architecture: SystemArchitecture,
        repository: String = "sharkdp/bat"
    ) async throws -> GitHubRelease {
        let selectedTag: String
        if let version = version, !version.trimmingCharacters(in: .whitespaces).isEmpty {
            let trimmed = version.trimmingCharacters(in: .whitespaces)
            selectedTag = trimmed.hasPrefix("v") ? trimmed : "v\(trimmed)"
        } else {
            selectedTag = try await fetchLatestReleaseTag(repository: repository)
        }

        return try GitHubRelease(repository: repository, tag: selectedTag, architecture: architecture)
    }

    /// Fetches the latest release tag for the repository, trying GitHub API and falling back to HTTP redirect.
    public static func fetchLatestReleaseTag(repository: String = "sharkdp/bat") async throws -> String {
        // Attempt 1: GitHub API
        if let apiTag = try? await fetchLatestTagViaAPI(repository: repository) {
            return apiTag
        }

        // Attempt 2: Follow HTTP redirect of /releases/latest
        if let redirectTag = try? await fetchLatestTagViaRedirect(repository: repository) {
            return redirectTag
        }

        throw InstallerError.releaseNotFound(
            "Could not determine the latest release tag for \(repository). You can specify a version explicitly using --version (e.g. --version v0.26.1)."
        )
    }

    private static func fetchLatestTagViaAPI(repository: String) async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw InstallerError.invalidURL("API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("bat-installer", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw InstallerError.apiError("GitHub API returned non-success response")
        }

        struct ReleaseJSON: Decodable {
            let tag_name: String
        }

        let decoded = try JSONDecoder().decode(ReleaseJSON.self, from: data)
        return decoded.tag_name
    }

    private static func fetchLatestTagViaRedirect(repository: String) async throws -> String {
        guard let url = URL(string: "https://github.com/\(repository)/releases/latest") else {
            throw InstallerError.invalidURL("Latest redirect URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("bat-installer", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let delegate = RedirectCaptureDelegate()
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let (_, response) = try await session.data(for: request)

        // Check if delegate captured redirection URL
        if let targetURL = delegate.redirectedURL {
            let lastComponent = targetURL.lastPathComponent
            if !lastComponent.isEmpty && lastComponent != "latest" {
                return lastComponent
            }
        }

        // Check HTTP Location header
        if let httpResponse = response as? HTTPURLResponse,
           let location = httpResponse.allHeaderFields["Location"] as? String,
           let locationURL = URL(string: location) {
            let lastComponent = locationURL.lastPathComponent
            if !lastComponent.isEmpty && lastComponent != "latest" {
                return lastComponent
            }
        }

        throw InstallerError.releaseNotFound("Redirect inspection failed for \(url)")
    }
}
