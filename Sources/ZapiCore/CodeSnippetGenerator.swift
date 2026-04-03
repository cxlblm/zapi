import Foundation

public enum CodeSnippetFormat: String, CaseIterable, Identifiable, Sendable {
    case curl = "cURL"
    case swiftURLSession = "Swift URLSession"
    case javascriptFetch = "JavaScript fetch"

    public var id: String { rawValue }
}

public struct CodeSnippetGenerator: Sendable {
    private let curlExporter: CurlExporter

    public init(curlExporter: CurlExporter = CurlExporter()) {
        self.curlExporter = curlExporter
    }

    public func generate(
        format: CodeSnippetFormat,
        snapshot: ResolvedRequestSnapshot,
        followRedirects: Bool
    ) -> String {
        switch format {
        case .curl:
            return curlExporter.export(snapshot: snapshot, followRedirects: followRedirects)
        case .swiftURLSession:
            return generateSwiftURLSession(snapshot: snapshot)
        case .javascriptFetch:
            return generateJavaScriptFetch(snapshot: snapshot)
        }
    }

    private func generateSwiftURLSession(snapshot: ResolvedRequestSnapshot) -> String {
        var lines = [
            "import Foundation",
            "",
            "let url = URL(string: \(swiftStringLiteral(snapshot.url)))!",
            "var request = URLRequest(url: url)",
            "request.httpMethod = \(swiftStringLiteral(snapshot.method.rawValue))"
        ]

        for header in snapshot.headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            lines.append("request.setValue(\(swiftStringLiteral(header.value)), forHTTPHeaderField: \(swiftStringLiteral(header.key)))")
        }

        if let bodyPreview = snapshot.bodyPreview, !bodyPreview.isEmpty {
            lines.append("request.httpBody = Data(\(swiftStringLiteral(bodyPreview)).utf8)")
        }

        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("print(String(decoding: data, as: UTF8.self))")
        lines.append("print(response)")

        return lines.joined(separator: "\n")
    }

    private func generateJavaScriptFetch(snapshot: ResolvedRequestSnapshot) -> String {
        var lines = [
            "const response = await fetch(\(javaScriptStringLiteral(snapshot.url)), {",
            "  method: \(javaScriptStringLiteral(snapshot.method.rawValue)),"
        ]

        if snapshot.headers.isEmpty {
            lines.append("  headers: {},")
        } else {
            lines.append("  headers: {")
            for header in snapshot.headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
                lines.append("    \(javaScriptObjectKey(header.key)): \(javaScriptStringLiteral(header.value)),")
            }
            lines.append("  },")
        }

        if let bodyPreview = snapshot.bodyPreview, !bodyPreview.isEmpty {
            lines.append("  body: \(javaScriptStringLiteral(bodyPreview)),")
        }

        lines.append("});")
        lines.append("")
        lines.append("const text = await response.text();")
        lines.append("console.log(text);")

        return lines.joined(separator: "\n")
    }

    private func swiftStringLiteral(_ value: String) -> String {
        "\"" + escapedString(value) + "\""
    }

    private func javaScriptStringLiteral(_ value: String) -> String {
        "\"" + escapedString(value) + "\""
    }

    private func javaScriptObjectKey(_ value: String) -> String {
        let identifierPattern = #"^[A-Za-z_$][A-Za-z0-9_$]*$"#
        if value.range(of: identifierPattern, options: .regularExpression) != nil {
            return value
        }

        return javaScriptStringLiteral(value)
    }

    private func escapedString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
