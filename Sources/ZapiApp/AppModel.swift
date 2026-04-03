import Foundation
import SwiftUI
import ZapiCore

@MainActor
final class AppModel: ObservableObject {
    @Published var project: APIProject
    @Published var selectedCollectionID: UUID?
    @Published var selectedRequestID: UUID?
    @Published var selectedHistoryEntryID: UUID?
    @Published var openRequestIDs: [UUID]
    @Published var latestResponse: APIResponseSnapshot?
    @Published var latestResolvedRequest: ResolvedRequestSnapshot?
    @Published var latestErrorMessage: String?
    @Published var isSending = false
    @Published var hasLoaded = false

    private let store: LocalProjectStore?
    private let executor: RequestExecutor
    private let curlImporter: CurlImporter
    private var autosaveTask: Task<Void, Never>?

    init(
        store: LocalProjectStore?,
        executor: RequestExecutor = RequestExecutor(),
        curlImporter: CurlImporter = CurlImporter()
    ) {
        self.store = store
        self.executor = executor
        self.curlImporter = curlImporter

        let sample = Self.sampleProject()
        self.project = sample
        self.selectedCollectionID = sample.collections.first?.id
        self.selectedRequestID = sample.collections.first?.requests.first?.id
        self.openRequestIDs = sample.collections.first?.requests.first.map { [$0.id] } ?? []
    }

    func load() async {
        guard !hasLoaded else { return }
        defer { hasLoaded = true }

        guard let store else { return }

        do {
            if let loaded = try await store.load() {
                project = loaded
                repairSelection()
            } else {
                repairSelection()
                scheduleAutosave()
            }
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func saveNow() {
        scheduleAutosave(immediate: true)
    }

    func addCollection() {
        let collection = APICollection(name: "New Collection")
        project.collections.append(collection)
        selectedCollectionID = collection.id

        let request = APIRequest(
            name: "New Request",
            method: .get,
            urlTemplate: "https://httpbin.org/get"
        )
        project.collections[project.collections.count - 1].requests.append(request)
        selectRequest(collectionID: collection.id, requestID: request.id)
        scheduleAutosave()
    }

    func addRequest() {
        guard let collectionIndex = selectedCollectionIndex ?? project.collections.indices.first else {
            addCollection()
            return
        }

        let request = APIRequest(
            name: "New Request",
            method: .get,
            urlTemplate: "https://httpbin.org/get"
        )
        project.collections[collectionIndex].requests.append(request)
        selectRequest(collectionID: project.collections[collectionIndex].id, requestID: request.id)
        scheduleAutosave()
    }

    func importCurlCommand(_ command: String) throws {
        if project.collections.isEmpty {
            project.collections.append(APICollection(name: "Imported"))
        }

        let collectionIndex = selectedCollectionIndex ?? project.collections.indices.first ?? 0
        let importedRequest = try curlImporter.import(command, name: "Imported cURL")
        project.collections[collectionIndex].requests.append(importedRequest)
        selectRequest(
            collectionID: project.collections[collectionIndex].id,
            requestID: importedRequest.id
        )
        scheduleAutosave()
    }

    func selectRequest(collectionID: UUID?, requestID: UUID) {
        selectedCollectionID = collectionID
        selectedRequestID = requestID
        selectedHistoryEntryID = nil
        openRequest(requestID)
    }

    func openRequest(_ requestID: UUID) {
        if openRequestIDs.contains(requestID) {
            openRequestIDs.removeAll(where: { $0 == requestID })
        }
        openRequestIDs.append(requestID)

        if openRequestIDs.count > 8 {
            openRequestIDs.removeFirst(openRequestIDs.count - 8)
        }
    }

    func closeRequestTab(_ requestID: UUID) {
        let wasSelected = selectedRequestID == requestID
        openRequestIDs.removeAll(where: { $0 == requestID })

        if wasSelected {
            if let nextID = openRequestIDs.last {
                selectedRequestID = nextID
                selectedCollectionID = collectionID(for: nextID)
            } else if let fallback = project.collections.first?.requests.first {
                selectedRequestID = fallback.id
                selectedCollectionID = project.collections.first?.id
                openRequestIDs = [fallback.id]
            } else {
                selectedRequestID = nil
                selectedCollectionID = nil
            }
        }
    }

    func request(for id: UUID) -> APIRequest? {
        project.collections
            .flatMap(\.requests)
            .first(where: { $0.id == id })
    }

    func collectionName(for requestID: UUID) -> String {
        project.collections.first(where: { collection in
            collection.requests.contains(where: { $0.id == requestID })
        })?.name ?? "Collection"
    }

    func addHeader() {
        mutateSelectedRequest { request in
            request.headers.append(APIKeyValue(key: "", value: ""))
        }
    }

    func addQueryItem() {
        mutateSelectedRequest { request in
            request.queryItems.append(APIKeyValue(key: "", value: ""))
        }
    }

    func addEnvironmentVariable() {
        guard let index = selectedEnvironmentIndex else { return }
        let key = nextEnvironmentKey(base: "NEW_KEY")
        project.environments[index].variables[key] = ""
        project.environments[index].maskedKeys.remove(key)
        scheduleAutosave()
    }

    func addEnvironment() {
        let name = nextEnvironmentName()
        let environment = APIEnvironment(
            name: name,
            variables: [
                "base_url": "",
                "token": ""
            ]
        )
        project.environments.append(environment)
        project.selectedEnvironmentID = environment.id
        scheduleAutosave()
    }

    func deleteSelectedEnvironment() {
        guard let index = selectedEnvironmentIndex, project.environments.count > 1 else { return }

        project.environments.remove(at: index)
        project.selectedEnvironmentID = project.environments.first?.id
        scheduleAutosave()
    }

    func removeHeader(id: UUID) {
        mutateSelectedRequest { request in
            request.headers.removeAll(where: { $0.id == id })
        }
    }

    func removeQueryItem(id: UUID) {
        mutateSelectedRequest { request in
            request.queryItems.removeAll(where: { $0.id == id })
        }
    }

    func removeEnvironmentVariable(key: String) {
        guard let index = selectedEnvironmentIndex else { return }
        project.environments[index].variables.removeValue(forKey: key)
        project.environments[index].maskedKeys.remove(key)
        scheduleAutosave()
    }

    func selectEnvironment(id: UUID?) {
        project.selectedEnvironmentID = id
        scheduleAutosave()
    }

    func inspectHistoryEntry(_ entry: RequestHistoryEntry) {
        latestResponse = entry.response
        latestResolvedRequest = entry.resolvedRequest
        latestErrorMessage = nil
        selectedHistoryEntryID = entry.id

        if request(for: entry.requestID) != nil {
            selectedCollectionID = collectionID(for: entry.requestID)
            selectedRequestID = entry.requestID
            openRequest(entry.requestID)
        }
    }

    func restoreRequest(from entry: RequestHistoryEntry) {
        let targetCollectionIndex = selectedCollectionIndex ?? project.collections.indices.first

        guard let targetCollectionIndex else {
            return
        }

        let restoredRequest = APIRequest(
            name: "Replay \(entry.resolvedRequest.method.rawValue)",
            method: entry.resolvedRequest.method,
            urlTemplate: entry.resolvedRequest.url,
            auth: .none,
            queryItems: [],
            headers: entry.resolvedRequest.headers
                .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
                .map { APIKeyValue(key: $0.key, value: $0.value) },
            body: entry.resolvedRequest.bodyPreview.map { .raw(text: $0, contentType: nil) } ?? .none
        )

        project.collections[targetCollectionIndex].requests.append(restoredRequest)
        selectRequest(collectionID: project.collections[targetCollectionIndex].id, requestID: restoredRequest.id)
        scheduleAutosave()
    }

    func sendSelectedRequest() {
        guard let request = selectedRequest else { return }
        latestErrorMessage = nil
        isSending = true

        Task {
            do {
                let entry = try await executor.execute(request, environment: project.selectedEnvironment)
                await MainActor.run {
                    latestResponse = entry.response
                    latestResolvedRequest = entry.resolvedRequest
                    selectedHistoryEntryID = entry.id
                    project.history.insert(entry, at: 0)
                    if project.history.count > 100 {
                        project.history = Array(project.history.prefix(100))
                    }
                    scheduleAutosave()
                }
            } catch {
                await MainActor.run {
                    latestErrorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isSending = false
            }
        }
    }

    var selectedRequest: APIRequest? {
        guard let location = selectedRequestLocation else { return nil }
        return project.collections[location.collectionIndex].requests[location.requestIndex]
    }

    var selectedEnvironmentIndex: Int? {
        guard let id = project.selectedEnvironmentID else { return nil }
        return project.environments.firstIndex(where: { $0.id == id })
    }

    var selectedCollectionIndex: Int? {
        guard let selectedCollectionID else { return nil }
        return project.collections.firstIndex(where: { $0.id == selectedCollectionID })
    }

    func binding<T>(for keyPath: WritableKeyPath<APIRequest, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { [weak self] in
                self?.selectedRequest?[keyPath: keyPath] ?? defaultValue
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    request[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindingForHeader(_ id: UUID, keyPath: WritableKeyPath<APIKeyValue, String>) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard
                    let self,
                    let header = self.selectedRequest?.headers.first(where: { $0.id == id })
                else {
                    return ""
                }
                return header[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    guard let index = request.headers.firstIndex(where: { $0.id == id }) else { return }
                    request.headers[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindingForHeaderEnabled(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.selectedRequest?.headers.first(where: { $0.id == id })?.isEnabled ?? true
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    guard let index = request.headers.firstIndex(where: { $0.id == id }) else { return }
                    request.headers[index].isEnabled = newValue
                }
            }
        )
    }

    func bindingForQueryItem(_ id: UUID, keyPath: WritableKeyPath<APIKeyValue, String>) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard
                    let self,
                    let item = self.selectedRequest?.queryItems.first(where: { $0.id == id })
                else {
                    return ""
                }
                return item[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    guard let index = request.queryItems.firstIndex(where: { $0.id == id }) else { return }
                    request.queryItems[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindingForQueryEnabled(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.selectedRequest?.queryItems.first(where: { $0.id == id })?.isEnabled ?? true
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    guard let index = request.queryItems.firstIndex(where: { $0.id == id }) else { return }
                    request.queryItems[index].isEnabled = newValue
                }
            }
        )
    }

    func bodyKindBinding() -> Binding<BodyEditorKind> {
        Binding(
            get: { [weak self] in
                guard let body = self?.selectedRequest?.body else { return .none }
                return BodyEditorKind(body: body)
            },
            set: { [weak self] newKind in
                self?.mutateSelectedRequest { request in
                    let existing = request.body
                    request.body = newKind.updatedBody(from: existing)
                }
            }
        )
    }

    func authKindBinding() -> Binding<AuthEditorKind> {
        Binding(
            get: { [weak self] in
                guard let auth = self?.selectedRequest?.auth else { return .none }
                return AuthEditorKind(auth: auth)
            },
            set: { [weak self] newKind in
                self?.mutateSelectedRequest { request in
                    request.auth = newKind.updatedAuth(from: request.auth)
                }
            }
        )
    }

    func bearerTokenBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .bearerToken(token) = self?.selectedRequest?.auth {
                    return token
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    request.auth = .bearerToken(newValue)
                }
            }
        )
    }

    func basicUsernameBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .basic(username, _) = self?.selectedRequest?.auth {
                    return username
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    let password: String
                    if case let .basic(_, currentPassword) = request.auth {
                        password = currentPassword
                    } else {
                        password = ""
                    }
                    request.auth = .basic(username: newValue, password: password)
                }
            }
        )
    }

    func basicPasswordBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .basic(_, password) = self?.selectedRequest?.auth {
                    return password
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    let username: String
                    if case let .basic(currentUsername, _) = request.auth {
                        username = currentUsername
                    } else {
                        username = ""
                    }
                    request.auth = .basic(username: username, password: newValue)
                }
            }
        )
    }

    func apiKeyNameBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .apiKey(name, _, _) = self?.selectedRequest?.auth {
                    return name
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    let value: String
                    let location: APIKeyLocation
                    if case let .apiKey(_, currentValue, currentLocation) = request.auth {
                        value = currentValue
                        location = currentLocation
                    } else {
                        value = ""
                        location = .header
                    }
                    request.auth = .apiKey(name: newValue, value: value, location: location)
                }
            }
        )
    }

    func apiKeyValueBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .apiKey(_, value, _) = self?.selectedRequest?.auth {
                    return value
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    let name: String
                    let location: APIKeyLocation
                    if case let .apiKey(currentName, _, currentLocation) = request.auth {
                        name = currentName
                        location = currentLocation
                    } else {
                        name = "X-API-Key"
                        location = .header
                    }
                    request.auth = .apiKey(name: name, value: newValue, location: location)
                }
            }
        )
    }

    func apiKeyLocationBinding() -> Binding<APIKeyLocation> {
        Binding(
            get: { [weak self] in
                if case let .apiKey(_, _, location) = self?.selectedRequest?.auth {
                    return location
                }
                return .header
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    let name: String
                    let value: String
                    if case let .apiKey(currentName, currentValue, _) = request.auth {
                        name = currentName
                        value = currentValue
                    } else {
                        name = "api_key"
                        value = ""
                    }
                    request.auth = .apiKey(name: name, value: value, location: newValue)
                }
            }
        )
    }

    func bodyTextBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let body = self?.selectedRequest?.body else { return "" }
                switch body {
                case .none:
                    return ""
                case let .raw(text, _):
                    return text
                case let .json(text):
                    return text
                case let .formURLEncoded(fields):
                    return fields
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: "\n")
                }
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    switch request.body {
                    case .none:
                        request.body = .raw(text: newValue, contentType: nil)
                    case let .raw(_, contentType):
                        request.body = .raw(text: newValue, contentType: contentType)
                    case .json:
                        request.body = .json(newValue)
                    case .formURLEncoded:
                        request.body = .formURLEncoded(
                            newValue
                                .split(separator: "\n", omittingEmptySubsequences: true)
                                .map { line in
                                    let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
                                    return APIKeyValue(
                                        key: pair.first ?? "",
                                        value: pair.count > 1 ? pair[1] : ""
                                    )
                                }
                        )
                    }
                }
            }
        )
    }

    func rawContentTypeBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                if case let .raw(_, contentType) = self?.selectedRequest?.body {
                    return contentType ?? ""
                }
                return ""
            },
            set: { [weak self] newValue in
                self?.mutateSelectedRequest { request in
                    guard case let .raw(text, _) = request.body else { return }
                    request.body = .raw(text: text, contentType: newValue.isEmpty ? nil : newValue)
                }
            }
        )
    }

    func bindingForEnvironmentValue(key: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return ""
                }
                return self.project.environments[index].variables[key] ?? ""
            },
            set: { [weak self] newValue in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return
                }
                self.project.environments[index].variables[key] = newValue
                self.scheduleAutosave()
            }
        )
    }

    func bindingForSelectedEnvironmentName() -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return ""
                }
                return self.project.environments[index].name
            },
            set: { [weak self] newValue in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return
                }
                self.project.environments[index].name = newValue
                self.scheduleAutosave()
            }
        )
    }

    func bindingForEnvironmentMasked(key: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return false
                }
                return self.project.environments[index].maskedKeys.contains(key)
            },
            set: { [weak self] newValue in
                guard
                    let self,
                    let index = self.selectedEnvironmentIndex
                else {
                    return
                }

                if newValue {
                    self.project.environments[index].maskedKeys.insert(key)
                } else {
                    self.project.environments[index].maskedKeys.remove(key)
                }

                self.scheduleAutosave()
            }
        )
    }

    func renameEnvironmentKey(oldKey: String, newKey: String) {
        guard
            let index = selectedEnvironmentIndex,
            oldKey != newKey,
            !newKey.isEmpty
        else {
            return
        }

        let value = project.environments[index].variables.removeValue(forKey: oldKey) ?? ""
        project.environments[index].variables[newKey] = value
        if project.environments[index].maskedKeys.remove(oldKey) != nil {
            project.environments[index].maskedKeys.insert(newKey)
        }
        scheduleAutosave()
    }

    func requestName(for request: APIRequest) -> String {
        request.name.isEmpty ? "Untitled Request" : request.name
    }

    var openRequests: [APIRequest] {
        openRequestIDs.compactMap(request(for:))
    }

    var recentHistory: [RequestHistoryEntry] {
        Array(project.history.prefix(12))
    }

    func filteredHistory(
        searchText: String,
        statusFilter: HistoryStatusFilter,
        onlySelectedRequest: Bool
    ) -> [RequestHistoryEntry] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return project.history.filter { entry in
            let matchesRequestScope: Bool
            if onlySelectedRequest, let selectedRequestID {
                matchesRequestScope = entry.requestID == selectedRequestID
            } else {
                matchesRequestScope = true
            }

            let matchesStatus = statusFilter.matches(statusCode: entry.response.statusCode)

            let matchesSearch: Bool
            if normalizedSearch.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch =
                    entry.resolvedRequest.url.lowercased().contains(normalizedSearch) ||
                    entry.resolvedRequest.method.rawValue.lowercased().contains(normalizedSearch) ||
                    String(entry.response.statusCode).contains(normalizedSearch)
            }

            return matchesRequestScope && matchesStatus && matchesSearch
        }
    }

    var prettyResponseBody: String {
        guard let response = latestResponse else { return "" }
        guard let bodyText = response.bodyText, !bodyText.isEmpty else { return "<empty body>" }

        if let formattedJSON = prettyPrintedJSON(from: bodyText) {
            return formattedJSON
        }

        return bodyText
    }

    var responseHeaderRows: [(key: String, value: String)] {
        guard let response = latestResponse else { return [] }
        return response.headers
            .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
            .map { ($0.key, $0.value) }
    }

    func filteredEnvironmentKeys(searchText: String) -> [String] {
        guard let environment = project.selectedEnvironment else { return [] }

        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return environment.variables.keys
            .filter { key in
                normalizedSearch.isEmpty || key.lowercased().contains(normalizedSearch)
            }
            .sorted()
    }

    func environmentVariableReference(for key: String) -> String {
        "{{\(key)}}"
    }

    private func mutateSelectedRequest(_ mutation: (inout APIRequest) -> Void) {
        guard let location = selectedRequestLocation else { return }
        mutation(&project.collections[location.collectionIndex].requests[location.requestIndex])
        scheduleAutosave()
    }

    private var selectedRequestLocation: (collectionIndex: Int, requestIndex: Int)? {
        guard let selectedRequestID else { return nil }

        for (collectionIndex, collection) in project.collections.enumerated() {
            if let requestIndex = collection.requests.firstIndex(where: { $0.id == selectedRequestID }) {
                return (collectionIndex, requestIndex)
            }
        }

        return nil
    }

    private func repairSelection() {
        if project.environments.isEmpty {
            let environment = APIEnvironment(
                name: "Local",
                variables: [
                    "base_url": "https://httpbin.org",
                    "token": "replace-me"
                ]
            )
            project.environments = [environment]
            project.selectedEnvironmentID = environment.id
        } else if project.selectedEnvironmentID == nil {
            project.selectedEnvironmentID = project.environments.first?.id
        }

        if project.collections.isEmpty {
            project = Self.sampleProject()
        }

        if let selectedRequestID,
           project.collections.contains(where: { $0.requests.contains(where: { $0.id == selectedRequestID }) }) {
            if selectedCollectionID == nil {
                selectedCollectionID = project.collections.first(where: { $0.requests.contains(where: { $0.id == selectedRequestID }) })?.id
            }
            openRequest(selectedRequestID)
            return
        }

        selectedCollectionID = project.collections.first?.id
        selectedRequestID = project.collections.first?.requests.first?.id
        openRequestIDs = selectedRequestID.map { [$0] } ?? []
    }

    private func collectionID(for requestID: UUID) -> UUID? {
        project.collections.first(where: { collection in
            collection.requests.contains(where: { $0.id == requestID })
        })?.id
    }

    private func prettyPrintedJSON(from text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func nextEnvironmentKey(base: String) -> String {
        guard let index = selectedEnvironmentIndex else { return base }
        let existing = Set(project.environments[index].variables.keys)

        if !existing.contains(base) {
            return base
        }

        var counter = 2
        while existing.contains("\(base)_\(counter)") {
            counter += 1
        }
        return "\(base)_\(counter)"
    }

    private func nextEnvironmentName() -> String {
        let existing = Set(project.environments.map(\.name))
        let base = "Environment"

        if !existing.contains(base) {
            return base
        }

        var counter = 2
        while existing.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    private func scheduleAutosave(immediate: Bool = false) {
        autosaveTask?.cancel()

        guard let store else { return }

        let snapshot = project
        autosaveTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
            }

            guard !Task.isCancelled else { return }
            try? await store.save(snapshot)
        }
    }

    private static func sampleProject() -> APIProject {
        let environment = APIEnvironment(
            name: "Local",
            variables: [
                "base_url": "https://httpbin.org",
                "token": "replace-me"
            ]
        )

        let request = APIRequest(
            name: "Get Anything",
            method: .get,
            urlTemplate: "{{base_url}}/anything",
            queryItems: [
                APIKeyValue(key: "hello", value: "world")
            ],
            headers: [
                APIKeyValue(key: "Authorization", value: "Bearer {{token}}")
            ],
            body: .none
        )

        return APIProject(
            name: "Local API Workspace",
            collections: [
                APICollection(name: "Sample", requests: [request])
            ],
            environments: [environment],
            selectedEnvironmentID: environment.id
        )
    }
}

enum BodyEditorKind: String, CaseIterable, Identifiable {
    case none = "None"
    case raw = "Raw"
    case json = "JSON"
    case form = "Form"

    var id: String { rawValue }

    init(body: HTTPBody) {
        switch body {
        case .none:
            self = .none
        case .raw:
            self = .raw
        case .json:
            self = .json
        case .formURLEncoded:
            self = .form
        }
    }

    func updatedBody(from existing: HTTPBody) -> HTTPBody {
        switch self {
        case .none:
            return .none
        case .raw:
            switch existing {
            case let .raw(text, contentType):
                return .raw(text: text, contentType: contentType)
            case let .json(text):
                return .raw(text: text, contentType: "text/plain")
            case let .formURLEncoded(fields):
                let text = fields.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                return .raw(text: text, contentType: "text/plain")
            case .none:
                return .raw(text: "", contentType: "text/plain")
            }
        case .json:
            switch existing {
            case let .json(text):
                return .json(text)
            case let .raw(text, _):
                return .json(text)
            case let .formURLEncoded(fields):
                let lines = fields.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",\n")
                return .json("{\n\(lines)\n}")
            case .none:
                return .json("{\n  \n}")
            }
        case .form:
            switch existing {
            case let .formURLEncoded(fields):
                return .formURLEncoded(fields)
            case let .raw(text, _), let .json(text):
                let fields = text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
                    let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
                    return APIKeyValue(
                        key: pair.first ?? "",
                        value: pair.count > 1 ? pair[1] : ""
                    )
                }
                return .formURLEncoded(fields)
            case .none:
                return .formURLEncoded([])
            }
        }
    }
}

enum AuthEditorKind: String, CaseIterable, Identifiable {
    case none = "None"
    case bearer = "Bearer"
    case basic = "Basic"
    case apiKey = "API Key"

    var id: String { rawValue }

    init(auth: RequestAuth) {
        switch auth {
        case .none:
            self = .none
        case .bearerToken:
            self = .bearer
        case .basic:
            self = .basic
        case .apiKey:
            self = .apiKey
        }
    }

    func updatedAuth(from existing: RequestAuth) -> RequestAuth {
        switch self {
        case .none:
            return .none
        case .bearer:
            if case let .bearerToken(token) = existing {
                return .bearerToken(token)
            }
            return .bearerToken("")
        case .basic:
            if case let .basic(username, password) = existing {
                return .basic(username: username, password: password)
            }
            return .basic(username: "", password: "")
        case .apiKey:
            if case let .apiKey(name, value, location) = existing {
                return .apiKey(name: name, value: value, location: location)
            }
            return .apiKey(name: "X-API-Key", value: "", location: .header)
        }
    }
}

enum HistoryStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case success = "2xx"
    case redirect = "3xx"
    case clientError = "4xx"
    case serverError = "5xx"

    var id: String { rawValue }

    func matches(statusCode: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .success:
            return (200..<300).contains(statusCode)
        case .redirect:
            return (300..<400).contains(statusCode)
        case .clientError:
            return (400..<500).contains(statusCode)
        case .serverError:
            return statusCode >= 500
        }
    }
}
