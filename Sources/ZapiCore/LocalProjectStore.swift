import Foundation

public actor LocalProjectStore {
    public let rootURL: URL
    public let fileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        rootURL: URL? = nil,
        appDirectoryName: String = "Zapi"
    ) throws {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = appSupport.appendingPathComponent(appDirectoryName, isDirectory: true)
        }

        self.fileURL = self.rootURL.appendingPathComponent("project.json")

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    public func load() throws -> APIProject? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(APIProject.self, from: data)
    }

    public func save(_ project: APIProject) throws {
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
    }
}
