import Foundation

public struct APIProject: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var collections: [APICollection]
    public var environments: [APIEnvironment]
    public var selectedEnvironmentID: UUID?
    public var history: [RequestHistoryEntry]
    public var authPresets: [SavedAuthPreset]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case collections
        case environments
        case selectedEnvironmentID
        case history
        case authPresets
    }

    public init(
        id: UUID = UUID(),
        name: String,
        collections: [APICollection] = [],
        environments: [APIEnvironment] = [],
        selectedEnvironmentID: UUID? = nil,
        history: [RequestHistoryEntry] = [],
        authPresets: [SavedAuthPreset] = []
    ) {
        self.id = id
        self.name = name
        self.collections = collections
        self.environments = environments
        self.selectedEnvironmentID = selectedEnvironmentID
        self.history = history
        self.authPresets = authPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        collections = try container.decodeIfPresent([APICollection].self, forKey: .collections) ?? []
        environments = try container.decodeIfPresent([APIEnvironment].self, forKey: .environments) ?? []
        selectedEnvironmentID = try container.decodeIfPresent(UUID.self, forKey: .selectedEnvironmentID)
        history = try container.decodeIfPresent([RequestHistoryEntry].self, forKey: .history) ?? []
        authPresets = try container.decodeIfPresent([SavedAuthPreset].self, forKey: .authPresets) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(collections, forKey: .collections)
        try container.encode(environments, forKey: .environments)
        try container.encodeIfPresent(selectedEnvironmentID, forKey: .selectedEnvironmentID)
        try container.encode(history, forKey: .history)
        try container.encode(authPresets, forKey: .authPresets)
    }

    public var selectedEnvironment: APIEnvironment? {
        guard let selectedEnvironmentID else {
            return nil
        }

        return environments.first(where: { $0.id == selectedEnvironmentID })
    }
}

public struct APICollection: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var requests: [APIRequest]

    public init(id: UUID = UUID(), name: String, requests: [APIRequest] = []) {
        self.id = id
        self.name = name
        self.requests = requests
    }
}

public struct APIEnvironment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var variables: [String: String]
    public var maskedKeys: Set<String>

    public init(
        id: UUID = UUID(),
        name: String,
        variables: [String: String] = [:],
        maskedKeys: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.variables = variables
        self.maskedKeys = maskedKeys
    }
}

public struct SavedAuthPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var auth: RequestAuth

    public init(id: UUID = UUID(), name: String, auth: RequestAuth) {
        self.id = id
        self.name = name
        self.auth = auth
    }
}

public struct APIRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var method: HTTPMethod
    public var urlTemplate: String
    public var auth: RequestAuth
    public var queryItems: [APIKeyValue]
    public var headers: [APIKeyValue]
    public var body: HTTPBody
    public var timeoutInterval: TimeInterval
    public var followRedirects: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        method: HTTPMethod = .get,
        urlTemplate: String,
        auth: RequestAuth = .none,
        queryItems: [APIKeyValue] = [],
        headers: [APIKeyValue] = [],
        body: HTTPBody = .none,
        timeoutInterval: TimeInterval = 60,
        followRedirects: Bool = true
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.urlTemplate = urlTemplate
        self.auth = auth
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
        self.followRedirects = followRedirects
    }
}

public struct APIKeyValue: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

public enum HTTPMethod: String, Codable, Equatable, Sendable, CaseIterable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}

public enum HTTPBody: Codable, Equatable, Sendable {
    case none
    case raw(text: String, contentType: String?)
    case json(String)
    case formURLEncoded([APIKeyValue])

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case contentType
        case fields
    }

    private enum Kind: String, Codable {
        case none
        case raw
        case json
        case formURLEncoded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .none:
            self = .none
        case .raw:
            self = .raw(
                text: try container.decode(String.self, forKey: .text),
                contentType: try container.decodeIfPresent(String.self, forKey: .contentType)
            )
        case .json:
            self = .json(try container.decode(String.self, forKey: .text))
        case .formURLEncoded:
            self = .formURLEncoded(try container.decode([APIKeyValue].self, forKey: .fields))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .raw(text, contentType):
            try container.encode(Kind.raw, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(contentType, forKey: .contentType)
        case let .json(text):
            try container.encode(Kind.json, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .formURLEncoded(fields):
            try container.encode(Kind.formURLEncoded, forKey: .kind)
            try container.encode(fields, forKey: .fields)
        }
    }
}

public enum APIKeyLocation: String, Codable, Equatable, Sendable, CaseIterable {
    case header
    case query
}

public enum RequestAuth: Codable, Equatable, Sendable {
    case none
    case bearerToken(String)
    case basic(username: String, password: String)
    case apiKey(name: String, value: String, location: APIKeyLocation)

    private enum CodingKeys: String, CodingKey {
        case kind
        case token
        case username
        case password
        case name
        case value
        case location
    }

    private enum Kind: String, Codable {
        case none
        case bearerToken
        case basic
        case apiKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .none:
            self = .none
        case .bearerToken:
            self = .bearerToken(try container.decode(String.self, forKey: .token))
        case .basic:
            self = .basic(
                username: try container.decode(String.self, forKey: .username),
                password: try container.decode(String.self, forKey: .password)
            )
        case .apiKey:
            self = .apiKey(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(String.self, forKey: .value),
                location: try container.decode(APIKeyLocation.self, forKey: .location)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .bearerToken(token):
            try container.encode(Kind.bearerToken, forKey: .kind)
            try container.encode(token, forKey: .token)
        case let .basic(username, password):
            try container.encode(Kind.basic, forKey: .kind)
            try container.encode(username, forKey: .username)
            try container.encode(password, forKey: .password)
        case let .apiKey(name, value, location):
            try container.encode(Kind.apiKey, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(value, forKey: .value)
            try container.encode(location, forKey: .location)
        }
    }
}

public struct ResolvedRequestSnapshot: Codable, Equatable, Sendable {
    public var method: HTTPMethod
    public var url: String
    public var headers: [String: String]
    public var bodyPreview: String?

    public init(
        method: HTTPMethod,
        url: String,
        headers: [String: String],
        bodyPreview: String?
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyPreview = bodyPreview
    }
}

public struct APIResponseSnapshot: Codable, Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var bodyText: String?
    public var bodyBase64: String
    public var mimeType: String?
    public var sizeBytes: Int
    public var durationMilliseconds: Int

    public init(
        statusCode: Int,
        headers: [String: String],
        bodyText: String?,
        bodyBase64: String,
        mimeType: String?,
        sizeBytes: Int,
        durationMilliseconds: Int
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.bodyText = bodyText
        self.bodyBase64 = bodyBase64
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct RequestHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var requestID: UUID
    public var executedAt: Date
    public var resolvedRequest: ResolvedRequestSnapshot
    public var response: APIResponseSnapshot

    public init(
        id: UUID = UUID(),
        requestID: UUID,
        executedAt: Date = Date(),
        resolvedRequest: ResolvedRequestSnapshot,
        response: APIResponseSnapshot
    ) {
        self.id = id
        self.requestID = requestID
        self.executedAt = executedAt
        self.resolvedRequest = resolvedRequest
        self.response = response
    }
}
