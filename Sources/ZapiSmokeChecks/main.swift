import Foundation
import ZapiCore

@main
struct ZapiSmokeChecks {
    static func main() async throws {
        try validateEnvironmentResolution()
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
            ]
        )

        try await store.save(project)
        let loaded = try await store.load()

        guard loaded == project else {
            throw SmokeCheckError.failed("LocalProjectStore failed to round-trip the project document.")
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
