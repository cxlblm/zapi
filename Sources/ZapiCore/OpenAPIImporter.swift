import Foundation

public enum OpenAPIImportError: LocalizedError {
    case unsupportedFormat
    case invalidDocument
    case missingPaths
    case noOperations

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Only OpenAPI JSON documents are supported right now."
        case .invalidDocument:
            return "The OpenAPI document could not be parsed."
        case .missingPaths:
            return "The OpenAPI document does not contain any paths."
        case .noOperations:
            return "The OpenAPI document does not contain any supported operations."
        }
    }
}

public struct OpenAPIImporter: Sendable {
    public init() {}

    public func importDocument(_ text: String) throws -> APICollection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else {
            throw OpenAPIImportError.unsupportedFormat
        }

        guard
            let data = trimmed.data(using: .utf8),
            let rawRoot = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw OpenAPIImportError.invalidDocument
        }

        guard let rawPaths = rawRoot["paths"] as? [String: Any], !rawPaths.isEmpty else {
            throw OpenAPIImportError.missingPaths
        }

        let collectionName = ((rawRoot["info"] as? [String: Any])?["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = ((rawRoot["servers"] as? [[String: Any]])?.first?["url"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var requests: [APIRequest] = []

        for path in rawPaths.keys.sorted() {
            guard let pathItem = rawPaths[path] as? [String: Any] else { continue }
            let sharedParameters = parseParameters(pathItem["parameters"])

            for method in supportedMethods {
                guard let operation = pathItem[method.rawValue.lowercased()] as? [String: Any] else {
                    continue
                }

                let parameters = sharedParameters + parseParameters(operation["parameters"])
                let queryItems = parameters
                    .filter { $0.location == .query }
                    .map { parameter in
                        APIKeyValue(
                            key: parameter.name,
                            value: parameter.value
                        )
                    }
                let headers = parameters
                    .filter { $0.location == .header }
                    .map { parameter in
                        APIKeyValue(
                            key: parameter.name,
                            value: parameter.value
                        )
                    }

                let request = APIRequest(
                    name: operationName(for: operation, method: method, path: path),
                    method: method,
                    urlTemplate: resolvedURLTemplate(baseURL: baseURL, path: path),
                    queryItems: queryItems,
                    headers: headers,
                    body: parseBody(operation["requestBody"])
                )
                requests.append(request)
            }
        }

        guard !requests.isEmpty else {
            throw OpenAPIImportError.noOperations
        }

        return APICollection(
            name: collectionName?.isEmpty == false ? collectionName! : "Imported OpenAPI",
            requests: requests
        )
    }

    private var supportedMethods: [HTTPMethod] {
        [.get, .post, .put, .patch, .delete, .head, .options]
    }

    private func operationName(for operation: [String: Any], method: HTTPMethod, path: String) -> String {
        if let summary = operation["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }

        if let operationID = operation["operationId"] as? String, !operationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return operationID
        }

        return "\(method.rawValue) \(path)"
    }

    private func resolvedURLTemplate(baseURL: String?, path: String) -> String {
        let normalizedPath = normalizedTemplate(path)

        guard let baseURL, !baseURL.isEmpty else {
            return "{{base_url}}" + normalizedPath
        }

        let normalizedBase = normalizedTemplate(baseURL)
        if normalizedBase.hasSuffix("/") && normalizedPath.hasPrefix("/") {
            return String(normalizedBase.dropLast()) + normalizedPath
        }

        if !normalizedBase.hasSuffix("/") && !normalizedPath.hasPrefix("/") {
            return normalizedBase + "/" + normalizedPath
        }

        return normalizedBase + normalizedPath
    }

    private func normalizedTemplate(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{([a-zA-Z0-9._-]+)\}"#, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "{{$1}}")
    }

    private func parseParameters(_ rawValue: Any?) -> [OpenAPIParameter] {
        guard let rawParameters = rawValue as? [[String: Any]] else { return [] }

        return rawParameters.compactMap { parameter in
            guard
                let name = parameter["name"] as? String,
                let location = parameter["in"] as? String
            else {
                return nil
            }

            let example = firstExampleValue(in: parameter)
                ?? firstExampleValue(in: parameter["schema"] as? [String: Any])
            let isRequired = parameter["required"] as? Bool ?? false

            return OpenAPIParameter(
                name: name,
                location: location == "header" ? .header : .query,
                value: parameterValue(name: name, example: example, isRequired: isRequired)
            )
        }
    }

    private func parseBody(_ rawValue: Any?) -> HTTPBody {
        guard
            let requestBody = rawValue as? [String: Any],
            let content = requestBody["content"] as? [String: Any]
        else {
            return .none
        }

        if let jsonContent = content["application/json"] as? [String: Any] {
            if let example = firstExampleValue(in: jsonContent), let text = stringifyExample(example, pretty: true) {
                return .json(text)
            }

            if let schema = jsonContent["schema"] as? [String: Any],
               let generated = jsonBodyFromSchema(schema) {
                return .json(generated)
            }
        }

        if let formContent = content["application/x-www-form-urlencoded"] as? [String: Any] {
            if let example = firstExampleValue(in: formContent) as? [String: Any] {
                return .formURLEncoded(
                    example.keys.sorted().map { key in
                        APIKeyValue(key: key, value: stringifyScalar(example[key]) ?? "")
                    }
                )
            }

            if let schema = formContent["schema"] as? [String: Any],
               let fields = formFieldsFromSchema(schema) {
                return .formURLEncoded(fields)
            }
        }

        if let textContent = content["text/plain"] as? [String: Any],
           let example = firstExampleValue(in: textContent),
           let text = stringifyExample(example, pretty: false) {
            return .raw(text: text, contentType: "text/plain")
        }

        if let firstContentType = content.keys.sorted().first {
            return .raw(text: "", contentType: firstContentType)
        }

        return .none
    }

    private func jsonBodyFromSchema(_ schema: [String: Any]) -> String? {
        guard let properties = schema["properties"] as? [String: Any] else { return nil }

        let object = properties.keys.sorted().reduce(into: [String: Any]()) { partialResult, key in
            let propertySchema = properties[key] as? [String: Any]
            let example = firstExampleValue(in: propertySchema)
            partialResult[key] = example ?? ""
        }

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return text
    }

    private func formFieldsFromSchema(_ schema: [String: Any]) -> [APIKeyValue]? {
        guard let properties = schema["properties"] as? [String: Any] else { return nil }

        return properties.keys.sorted().map { key in
            let propertySchema = properties[key] as? [String: Any]
            let example = firstExampleValue(in: propertySchema)
            return APIKeyValue(key: key, value: stringifyScalar(example) ?? "")
        }
    }

    private func firstExampleValue(in object: [String: Any]?) -> Any? {
        guard let object else { return nil }

        if let example = object["example"] {
            return example
        }

        if let examples = object["examples"] as? [String: Any] {
            for key in examples.keys.sorted() {
                if let exampleObject = examples[key] as? [String: Any], let value = exampleObject["value"] {
                    return value
                }
            }
        }

        if let defaultValue = object["default"] {
            return defaultValue
        }

        return nil
    }

    private func stringifyExample(_ value: Any, pretty: Bool) -> String? {
        if let string = value as? String {
            return string
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(
               withJSONObject: value,
               options: pretty ? [.prettyPrinted, .sortedKeys] : []
           ) {
            return String(data: data, encoding: .utf8)
        }

        return stringifyScalar(value)
    }

    private func stringifyScalar(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let boolean as Bool:
            return boolean ? "true" : "false"
        default:
            return nil
        }
    }

    private func parameterValue(name: String, example: Any?, isRequired: Bool) -> String {
        if let exampleText = stringifyScalar(example) ?? stringifyExample(example as Any, pretty: false) {
            return exampleText
        }

        return isRequired ? "{{\(name)}}" : ""
    }
}

private struct OpenAPIParameter {
    var name: String
    var location: APIKeyLocation
    var value: String
}
