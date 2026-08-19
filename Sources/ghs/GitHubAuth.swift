import Foundation

/// Resolves an API token from whatever the machine already has.
///
/// Note on SSH: GitHub SSH keys authenticate git transport only — the REST and
/// GraphQL APIs reject them outright. So "use the credentials already on this
/// system" means borrowing the GitHub CLI's OAuth token, which is what `gh auth
/// token` prints. That keeps setup at zero for anyone who already uses `gh`.
enum GitHubAuth {
    enum Source: String {
        case ghCLI = "GitHub CLI (gh)"
        case environment = "GH_TOKEN environment variable"
        case keychain = "Personal access token (Keychain)"
    }

    struct Credential {
        let token: String
        let source: Source
    }

    static func resolve() -> Credential? {
        if let token = ghCLIToken() { return Credential(token: token, source: .ghCLI) }
        for key in ["GH_TOKEN", "GITHUB_TOKEN"] {
            if let t = ProcessInfo.processInfo.environment[key], !t.isEmpty {
                return Credential(token: t, source: .environment)
            }
        }
        if let token = Keychain.read() { return Credential(token: token, source: .keychain) }
        return nil
    }

    /// A GUI app inherits a bare PATH from launchd, so probe the usual install
    /// locations rather than relying on the shell finding `gh`.
    private static let ghCandidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    private static func ghCLIToken() -> String? {
        guard let gh = ghCandidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

extension GitHubAuth.Source {
    /// Short form for the popover footer, where space is tight.
    var shortLabel: String {
        switch self {
        case .ghCLI: return "GitHub CLI"
        case .environment: return "environment"
        case .keychain: return "Keychain"
        }
    }
}
