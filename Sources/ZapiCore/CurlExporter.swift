import Foundation

public struct CurlExporter: Sendable {
    public init() {}

    public func export(
        snapshot: ResolvedRequestSnapshot,
        followRedirects: Bool
    ) -> String {
        var parts = ["curl"]

        if followRedirects {
            parts.append("--location")
        }

        parts.append("--request")
        parts.append(shellEscape(snapshot.method.rawValue))

        parts.append("--url")
        parts.append(shellEscape(snapshot.url))

        for header in snapshot.headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            parts.append("--header")
            parts.append(shellEscape("\(header.key): \(header.value)"))
        }

        if let bodyPreview = snapshot.bodyPreview, !bodyPreview.isEmpty {
            parts.append("--data-raw")
            parts.append(shellEscape(bodyPreview))
        }

        return parts.joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
