import Foundation

struct AppBuildInfo: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let source_commit: String?

    static func current(info: [String: Any]? = Bundle.main.infoDictionary) -> Self {
        Self(version: info?["CFBundleShortVersionString"] as? String ?? "development",
             build: info?["CFBundleVersion"] as? String ?? "unversioned",
             source_commit: info?["RWSourceCommit"] as? String)
    }

    var display: String { "\(version) (build \(build))" }
}
