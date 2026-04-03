import Foundation

public struct EnvironmentResolver: Sendable {
    private static let tokenPattern = #"\{\{\s*([a-zA-Z0-9._-]+)\s*\}\}"#

    public init() {}

    public func resolve(_ template: String, variables: [String: String]) -> String {
        guard
            let regex = try? NSRegularExpression(pattern: Self.tokenPattern, options: [])
        else {
            return template
        }

        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = regex.matches(in: template, options: [], range: range)

        guard !matches.isEmpty else {
            return template
        }

        var resolved = template

        for match in matches.reversed() {
            guard
                match.numberOfRanges >= 2,
                let tokenRange = Range(match.range(at: 0), in: resolved),
                let keyRange = Range(match.range(at: 1), in: template)
            else {
                continue
            }

            let key = String(template[keyRange])
            let value = variables[key] ?? String(resolved[tokenRange])
            resolved.replaceSubrange(tokenRange, with: value)
        }

        return resolved
    }
}
