import Foundation

public enum CurlImportError: Error, LocalizedError, Equatable {
    case emptyCommand
    case invalidCommand
    case missingValue(String)
    case missingURL

    public var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Paste a cURL command to import."
        case .invalidCommand:
            return "The pasted text does not look like a valid cURL command."
        case let .missingValue(flag):
            return "The cURL flag \(flag) is missing its value."
        case .missingURL:
            return "The cURL command does not include a request URL."
        }
    }
}

public struct CurlImporter: Sendable {
    public init() {}

    public func `import`(_ command: String, name: String = "Imported Request") throws -> APIRequest {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CurlImportError.emptyCommand
        }

        let tokens = try tokenize(trimmed)
        guard !tokens.isEmpty else {
            throw CurlImportError.emptyCommand
        }

        let first = tokens[0].lowercased()
        let tokenStream = first == "curl" ? Array(tokens.dropFirst()) : tokens
        guard !tokenStream.isEmpty else {
            throw CurlImportError.invalidCommand
        }

        var method: HTTPMethod?
        var url: String?
        var headers: [APIKeyValue] = []
        var followRedirects = true
        var bodyText: String?
        var contentType: String?
        var auth: RequestAuth = .none

        var index = 0
        while index < tokenStream.count {
            let token = tokenStream[index]

            switch token {
            case "-X", "--request":
                guard index + 1 < tokenStream.count else {
                    throw CurlImportError.missingValue(token)
                }
                method = HTTPMethod(rawValue: tokenStream[index + 1].uppercased()) ?? .get
                index += 2

            case "-H", "--header":
                guard index + 1 < tokenStream.count else {
                    throw CurlImportError.missingValue(token)
                }
                let headerLine = tokenStream[index + 1]
                let parts = headerLine.split(separator: ":", maxSplits: 1).map(String.init)
                if let key = parts.first {
                    let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                    headers.append(APIKeyValue(key: key, value: value))
                    if key.caseInsensitiveCompare("Content-Type") == .orderedSame {
                        contentType = value
                    }
                }
                index += 2

            case "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode":
                guard index + 1 < tokenStream.count else {
                    throw CurlImportError.missingValue(token)
                }
                bodyText = tokenStream[index + 1]
                index += 2

            case "-L", "--location":
                followRedirects = true
                index += 1

            case "--url":
                guard index + 1 < tokenStream.count else {
                    throw CurlImportError.missingValue(token)
                }
                url = tokenStream[index + 1]
                index += 2

            case "-u", "--user":
                guard index + 1 < tokenStream.count else {
                    throw CurlImportError.missingValue(token)
                }
                let userParts = tokenStream[index + 1].split(separator: ":", maxSplits: 1).map(String.init)
                let username = userParts.first ?? ""
                let password = userParts.count > 1 ? userParts[1] : ""
                auth = .basic(username: username, password: password)
                index += 2

            default:
                if token.hasPrefix("http://") || token.hasPrefix("https://") {
                    url = token
                }
                index += 1
            }
        }

        guard let resolvedURL = url else {
            throw CurlImportError.missingURL
        }

        let body: HTTPBody
        if let bodyText {
            if let contentType, contentType.localizedCaseInsensitiveContains("application/json") {
                body = .json(bodyText)
            } else {
                body = .raw(text: bodyText, contentType: contentType)
            }
        } else {
            body = .none
        }

        let resolvedMethod = method ?? (bodyText == nil ? .get : .post)

        return APIRequest(
            name: name,
            method: resolvedMethod,
            urlTemplate: resolvedURL,
            auth: auth,
            queryItems: [],
            headers: headers,
            body: body,
            timeoutInterval: 60,
            followRedirects: followRedirects
        )
    }

    private func tokenize(_ command: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escape = false

        for character in command {
            if escape {
                current.append(character)
                escape = false
                continue
            }

            if character == "\\" {
                escape = true
                continue
            }

            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
