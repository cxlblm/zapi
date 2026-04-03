import Foundation

public enum RequestExecutorError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case nonHTTPResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case .nonHTTPResponse:
            return "The server returned a non-HTTP response."
        }
    }
}

public final class RequestExecutor: Sendable {
    private let configuration: URLSessionConfiguration
    private let resolver: EnvironmentResolver

    public init(
        configuration: URLSessionConfiguration = .ephemeral,
        resolver: EnvironmentResolver = EnvironmentResolver()
    ) {
        self.configuration = configuration.copy() as? URLSessionConfiguration ?? configuration
        self.resolver = resolver
    }

    public func execute(
        _ request: APIRequest,
        environment: APIEnvironment? = nil
    ) async throws -> RequestHistoryEntry {
        let prepared = try prepare(request, variables: environment?.variables ?? [:])
        let redirectDelegate = RedirectControlDelegate(followRedirects: request.followRedirects)
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )

        let startedAt = Date()
        let (data, response) = try await session.data(for: prepared.urlRequest)
        defer { session.finishTasksAndInvalidate() }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestExecutorError.nonHTTPResponse
        }

        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let bodyText = String(data: data, encoding: .utf8)

        return RequestHistoryEntry(
            requestID: request.id,
            executedAt: startedAt,
            resolvedRequest: prepared.snapshot,
            response: APIResponseSnapshot(
                statusCode: httpResponse.statusCode,
                headers: normalizedHeaders(httpResponse.allHeaderFields),
                bodyText: bodyText,
                bodyBase64: data.base64EncodedString(),
                mimeType: httpResponse.mimeType,
                sizeBytes: data.count,
                durationMilliseconds: elapsedMilliseconds
            )
        )
    }

    public func preview(
        _ request: APIRequest,
        environment: APIEnvironment? = nil
    ) throws -> ResolvedRequestSnapshot {
        try prepare(request, variables: environment?.variables ?? [:]).snapshot
    }

    private func prepare(
        _ request: APIRequest,
        variables: [String: String]
    ) throws -> PreparedRequest {
        let resolvedURLTemplate = resolver.resolve(request.urlTemplate, variables: variables)
        guard var components = URLComponents(string: resolvedURLTemplate) else {
            throw RequestExecutorError.invalidURL(resolvedURLTemplate)
        }

        let enabledQueryItems = request.queryItems
            .filter(\.isEnabled)
            .map {
                URLQueryItem(
                    name: resolver.resolve($0.key, variables: variables),
                    value: resolver.resolve($0.value, variables: variables)
                )
            }

        if !enabledQueryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + enabledQueryItems
        }

        var resolvedHeaders: [String: String] = [:]
        var urlRequest = URLRequest(
            url: URL(string: "https://localhost.invalid")!,
            timeoutInterval: request.timeoutInterval
        )
        urlRequest.httpMethod = request.method.rawValue

        for header in request.headers where header.isEnabled {
            let key = resolver.resolve(header.key, variables: variables)
            let value = resolver.resolve(header.value, variables: variables)
            resolvedHeaders[key] = value
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        applyAuth(
            request.auth,
            to: &components,
            headers: &resolvedHeaders,
            urlRequest: &urlRequest,
            variables: variables
        )

        guard let url = components.url else {
            throw RequestExecutorError.invalidURL(resolvedURLTemplate)
        }
        urlRequest.url = url

        let body = try buildBody(request.body, variables: variables)
        urlRequest.httpBody = body.data
        for (key, value) in body.additionalHeaders {
            if resolvedHeaders[key] == nil {
                resolvedHeaders[key] = value
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        return PreparedRequest(
            urlRequest: urlRequest,
            snapshot: ResolvedRequestSnapshot(
                method: request.method,
                url: url.absoluteString,
                headers: resolvedHeaders,
                bodyPreview: body.preview
            )
        )
    }

    private func applyAuth(
        _ auth: RequestAuth,
        to components: inout URLComponents,
        headers: inout [String: String],
        urlRequest: inout URLRequest,
        variables: [String: String]
    ) {
        switch auth {
        case .none:
            return
        case let .bearerToken(token):
            let resolvedToken = resolver.resolve(token, variables: variables)
            let authorization = "Bearer \(resolvedToken)"
            if headers["Authorization"] == nil {
                headers["Authorization"] = authorization
                urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
        case let .basic(username, password):
            let resolvedUsername = resolver.resolve(username, variables: variables)
            let resolvedPassword = resolver.resolve(password, variables: variables)
            let encoded = Data("\(resolvedUsername):\(resolvedPassword)".utf8).base64EncodedString()
            let authorization = "Basic \(encoded)"
            if headers["Authorization"] == nil {
                headers["Authorization"] = authorization
                urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
            }
        case let .apiKey(name, value, location):
            let resolvedName = resolver.resolve(name, variables: variables)
            let resolvedValue = resolver.resolve(value, variables: variables)

            switch location {
            case .header:
                if headers[resolvedName] == nil {
                    headers[resolvedName] = resolvedValue
                    urlRequest.setValue(resolvedValue, forHTTPHeaderField: resolvedName)
                }
            case .query:
                let existing = components.queryItems ?? []
                if !existing.contains(where: { $0.name == resolvedName }) {
                    components.queryItems = existing + [URLQueryItem(name: resolvedName, value: resolvedValue)]
                }
            }
        }
    }

    private func buildBody(
        _ body: HTTPBody,
        variables: [String: String]
    ) throws -> PreparedBody {
        switch body {
        case .none:
            return PreparedBody(data: nil, preview: nil, additionalHeaders: [:])
        case let .raw(text, contentType):
            let resolved = resolver.resolve(text, variables: variables)
            return PreparedBody(
                data: Data(resolved.utf8),
                preview: resolved,
                additionalHeaders: contentType.map { ["Content-Type": $0] } ?? [:]
            )
        case let .json(text):
            let resolved = resolver.resolve(text, variables: variables)
            return PreparedBody(
                data: Data(resolved.utf8),
                preview: resolved,
                additionalHeaders: ["Content-Type": "application/json"]
            )
        case let .formURLEncoded(fields):
            let resolvedFields = fields
                .filter(\.isEnabled)
                .map { field in
                    URLQueryItem(
                        name: resolver.resolve(field.key, variables: variables),
                        value: resolver.resolve(field.value, variables: variables)
                    )
                }

            var components = URLComponents()
            components.queryItems = resolvedFields
            let preview = resolvedFields
                .map { "\($0.name)=\($0.value ?? "")" }
                .joined(separator: "&")
            let encoded = components.percentEncodedQuery ?? ""

            return PreparedBody(
                data: Data(encoded.utf8),
                preview: preview,
                additionalHeaders: [
                    "Content-Type": "application/x-www-form-urlencoded; charset=utf-8"
                ]
            )
        }
    }

    private func normalizedHeaders(_ rawHeaders: [AnyHashable: Any]) -> [String: String] {
        rawHeaders.reduce(into: [:]) { partialResult, pair in
            partialResult[String(describing: pair.key)] = String(describing: pair.value)
        }
    }
}

private struct PreparedRequest {
    var urlRequest: URLRequest
    var snapshot: ResolvedRequestSnapshot
}

private struct PreparedBody {
    var data: Data?
    var preview: String?
    var additionalHeaders: [String: String]
}

private final class RedirectControlDelegate: NSObject, URLSessionTaskDelegate {
    private let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(followRedirects ? request : nil)
    }
}
