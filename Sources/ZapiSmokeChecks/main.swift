import Foundation
import ZapiCore

@main
struct ZapiSmokeChecks {
    static func main() async throws {
        try validateEnvironmentResolution()
        try validateCurlImportAndExport()
        try validateOpenAPIImport()
        try validateCodeSnippetGeneration()
        try await validateProjectPersistence()
        try await validateRequestExecution()

        print("Zapi smoke checks passed.")
    }

    private static func validateEnvironmentResolution() throws {
        let resolver = EnvironmentResolver()
        let resolved = resolver.resolve(
            "https://{{host}}/users/{{user_id}}",
            variables: [
                "host": "api.example.com",
                "user_id": "42"
            ]
        )

        guard resolved == "https://api.example.com/users/42" else {
            throw SmokeCheckError.failed("EnvironmentResolver returned an unexpected result.")
        }
    }

    private static func validateCurlImportAndExport() throws {
        let importer = CurlImporter()
        let request = try importer.import(
            """
            curl --location --request POST --url https://api.example.com/users \
              --header 'Content-Type: application/json' \
              --header 'X-Trace: abc123' \
              --data '{"name":"ian"}'
            """,
            name: "Imported"
        )

        guard request.method == .post else {
            throw SmokeCheckError.failed("CurlImporter did not infer the HTTP method.")
        }

        guard request.urlTemplate == "https://api.example.com/users" else {
            throw SmokeCheckError.failed("CurlImporter did not preserve the request URL.")
        }

        guard case let .json(requestBody) = request.body, requestBody == #"{"name":"ian"}"# else {
            throw SmokeCheckError.failed("CurlImporter did not capture the JSON body.")
        }

        let exporter = CurlExporter()
        let command = exporter.export(
            snapshot: ResolvedRequestSnapshot(
                method: request.method,
                url: request.urlTemplate,
                headers: Dictionary(uniqueKeysWithValues: request.headers.map { ($0.key, $0.value) }),
                bodyPreview: requestBody
            ),
            followRedirects: request.followRedirects
        )

        guard command.contains("--location"),
              command.contains("--request 'POST'"),
              command.contains("--header 'X-Trace: abc123'") else {
            throw SmokeCheckError.failed("CurlExporter did not include expected flags.")
        }
    }

    private static func validateOpenAPIImport() throws {
        let importer = OpenAPIImporter()
        let collection = try importer.importDocument(
            """
            {
              "openapi": "3.0.0",
              "info": {
                "title": "User API",
                "version": "1.0.0"
              },
              "servers": [
                { "url": "https://api.example.com/v1" }
              ],
              "paths": {
                "/users/{id}": {
                  "get": {
                    "summary": "Get User",
                    "parameters": [
                      { "name": "locale", "in": "query", "example": "en-US" }
                    ]
                  }
                }
              }
            }
            """
        )

        guard collection.name == "User API", collection.requests.count == 1 else {
            throw SmokeCheckError.failed("OpenAPIImporter did not create the expected collection.")
        }

        let request = collection.requests[0]
        guard request.urlTemplate == "https://api.example.com/v1/users/{{id}}" else {
            throw SmokeCheckError.failed("OpenAPIImporter did not normalize path parameters.")
        }

        guard request.queryItems.first?.key == "locale",
              request.queryItems.first?.value == "en-US" else {
            throw SmokeCheckError.failed("OpenAPIImporter did not import query parameters.")
        }
    }

    private static func validateCodeSnippetGeneration() throws {
        let generator = CodeSnippetGenerator()
        let snapshot = ResolvedRequestSnapshot(
            method: .post,
            url: "https://api.example.com/users?hello=world",
            headers: [
                "Authorization": "Bearer token-123",
                "Content-Type": "application/json"
            ],
            bodyPreview: #"{"name":"Ian"}"#
        )

        let swiftSnippet = generator.generate(
            format: .swiftURLSession,
            snapshot: snapshot,
            followRedirects: true
        )
        let jsSnippet = generator.generate(
            format: .javascriptFetch,
            snapshot: snapshot,
            followRedirects: true
        )

        guard swiftSnippet.contains("URLRequest"),
              swiftSnippet.contains("request.httpMethod = \"POST\"") else {
            throw SmokeCheckError.failed("CodeSnippetGenerator did not create the Swift snippet.")
        }

        guard jsSnippet.contains("await fetch(\"https://api.example.com/users?hello=world\""),
              jsSnippet.contains("method: \"POST\"") else {
            throw SmokeCheckError.failed("CodeSnippetGenerator did not create the JavaScript snippet.")
        }
    }

    private static func validateProjectPersistence() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try LocalProjectStore(rootURL: rootURL)

        let project = APIProject(
            name: "Demo",
            collections: [
                APICollection(
                    name: "Users",
                    requests: [
                        APIRequest(name: "List users", urlTemplate: "https://example.com/users")
                    ]
                )
            ],
            environments: [
                APIEnvironment(name: "Local", variables: ["host": "localhost"])
            ],
            authPresets: [
                SavedAuthPreset(name: "Local Bearer", auth: .bearerToken("{{token}}"))
            ]
        )

        try await store.save(project)
        let loaded = try await store.load()

        guard loaded == project else {
            throw SmokeCheckError.failed("LocalProjectStore failed to round-trip the project document.")
        }

        let legacyProjectData = Data(
            """
            {
              "id": "\(UUID().uuidString)",
              "name": "Legacy Workspace",
              "collections": [],
              "environments": [],
              "history": []
            }
            """.utf8
        )

        let legacyProject = try JSONDecoder().decode(APIProject.self, from: legacyProjectData)
        guard legacyProject.authPresets.isEmpty else {
            throw SmokeCheckError.failed("APIProject failed to decode legacy project data without auth presets.")
        }
    }

    private static func validateRequestExecution() async throws {
        StubURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == "https://api.example.com/users?include=profile" else {
                throw SmokeCheckError.failed("RequestExecutor built an unexpected URL.")
            }

            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer secret" else {
                throw SmokeCheckError.failed("RequestExecutor failed to resolve headers.")
            }

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.example.com/users")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            return (response, Data(#"{"ok":true}"#.utf8))
        }

        defer { StubURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]

        let executor = RequestExecutor(configuration: configuration)
        let request = APIRequest(
            name: "List users",
            method: .get,
            urlTemplate: "https://{{host}}/users",
            queryItems: [APIKeyValue(key: "include", value: "profile")],
            headers: [APIKeyValue(key: "Authorization", value: "Bearer {{token}}")]
        )
        let environment = APIEnvironment(
            name: "Local",
            variables: [
                "host": "api.example.com",
                "token": "secret"
            ]
        )

        let history = try await executor.execute(request, environment: environment)

        guard history.response.statusCode == 200 else {
            throw SmokeCheckError.failed("RequestExecutor did not capture the response status code.")
        }

        guard history.response.bodyText == #"{"ok":true}"# else {
            throw SmokeCheckError.failed("RequestExecutor did not capture the response body.")
        }
    }
}

private enum SmokeCheckError: Error {
    case failed(String)
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
