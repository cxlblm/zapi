import AppKit
import SwiftUI
import ZapiCore

@main
struct ZapiApp: App {
    @StateObject private var model: AppModel
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue

    init() {
        let store = try? LocalProjectStore()
        _model = StateObject(wrappedValue: AppModel(store: store))

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        WindowGroup("Zapi") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1280, minHeight: 820)
                .preferredColorScheme(currentAppearance.colorScheme)
                .task {
                    await model.load()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .preferredColorScheme(currentAppearance.colorScheme)
                .frame(width: 480, height: 320)
        }
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }
}

private struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue
    @State private var isEnvironmentManagerPresented = false
    @State private var isCurlImportPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(isEnvironmentManagerPresented: $isEnvironmentManagerPresented)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } content: {
            RequestEditorView(isEnvironmentManagerPresented: $isEnvironmentManagerPresented)
                .navigationSplitViewColumnWidth(min: 560, ideal: 700)
        } detail: {
            ResponseView()
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        }
        .background(ZapiTheme.canvas.ignoresSafeArea())
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Menu {
                        Picker("Appearance", selection: $appAppearanceRawValue) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.rawValue).tag(appearance.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .help("Appearance")

                    Button {
                        isEnvironmentManagerPresented = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    .help("Manage Environments")

                    Button {
                        isCurlImportPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                    .help("Import cURL")
                }

                ControlGroup {
                    Button {
                        model.addCollection()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("New Collection")

                    Button {
                        model.addRequest()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New Request")
                }

                Button {
                    model.saveNow()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save")
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .sheet(isPresented: $isEnvironmentManagerPresented) {
            EnvironmentManagerSheet()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .sheet(isPresented: $isCurlImportPresented) {
            CurlImportSheet()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 420)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isEnvironmentManagerPresented: Bool
    @State private var historySearchText = ""
    @State private var historyFilter: HistoryStatusFilter = .all
    @State private var onlySelectedRequestHistory = false

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            sourceList

            sidebarFooter
        }
        .background(ZapiTheme.sidebarBackground)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [ZapiTheme.accentStart, ZapiTheme.accentEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zapi")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Local API Workspace")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let environment = model.project.selectedEnvironment {
                Button {
                    isEnvironmentManagerPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ZapiTheme.success)
                            .frame(width: 8, height: 8)
                        Text(environment.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(environment.variables.count) vars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(ZapiTheme.sidebarCard)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZapiTheme.panelStroke)
                .frame(height: 1)
        }
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Requests")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(model.project.collections.flatMap(\.requests).count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ForEach(model.project.collections) { collection in
                    SidebarCollectionSection(collection: collection)
                }

                historyDrawer
            }
            .padding(18)
        }
    }

    private var historyDrawer: some View {
        let filteredHistory = Array(
            model.filteredHistory(
                searchText: historySearchText,
                statusFilter: historyFilter,
                onlySelectedRequest: onlySelectedRequestHistory
            )
            .prefix(12)
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(filteredHistory.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TextField("Search URL, method, or status", text: $historySearchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)

            Picker("Status", selection: $historyFilter) {
                ForEach(HistoryStatusFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Only Current Request", isOn: $onlySelectedRequestHistory)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .toggleStyle(.switch)
                .disabled(model.selectedRequest == nil)

            if filteredHistory.isEmpty {
                Text("Send a request to populate local history.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(filteredHistory) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(historyStatusColor(entry.response.statusCode))
                                .frame(width: 8, height: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.resolvedRequest.url)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(entry.resolvedRequest.method.rawValue) • Status \(entry.response.statusCode) • \(entry.response.durationMilliseconds) ms")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.inspectHistoryEntry(entry)
                        }

                        HStack(spacing: 8) {
                            Button {
                                model.inspectHistoryEntry(entry)
                            } label: {
                                Label("Inspect", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SidebarMiniButtonStyle())

                            Button {
                                model.restoreRequest(from: entry)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SidebarMiniButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(model.selectedHistoryEntryID == entry.id ? ZapiTheme.sidebarSelected : ZapiTheme.sidebarCard)
                    )
                }
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.addRequest()
            } label: {
                Label("New Request", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SidebarActionButtonStyle())

            Text("RapidAPI-style local client")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ZapiTheme.panelStroke)
                .frame(height: 1)
        }
    }

    private func historyStatusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: return ZapiTheme.success
        case 300..<400: return ZapiTheme.warning
        default: return ZapiTheme.danger
        }
    }
}

private struct SidebarCollectionSection: View {
    let collection: APICollection
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(collection.requests.count) requests")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ForEach(collection.requests) { request in
                SidebarRequestRow(
                    request: request,
                    isSelected: request.id == model.selectedRequestID
                )
                .onTapGesture {
                    model.selectRequest(collectionID: collection.id, requestID: request.id)
                }
            }
        }
    }
}

private struct SidebarRequestRow: View {
    let request: APIRequest
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(request.method.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.name.isEmpty ? "Untitled Request" : request.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)

                Text(request.urlTemplate)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? ZapiTheme.sidebarSelected : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? ZapiTheme.accentStart.opacity(0.18) : .clear, lineWidth: 1)
                )
        )
    }

    private var methodColor: Color {
        switch request.method {
        case .get: return ZapiTheme.success
        case .post: return ZapiTheme.accentStart
        case .put, .patch: return ZapiTheme.warning
        case .delete: return ZapiTheme.danger
        case .head, .options: return .secondary
        }
    }
}

private struct SidebarMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? ZapiTheme.sidebarSelected : ZapiTheme.sidebarCard)
            )
    }
}

private struct RequestEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isEnvironmentManagerPresented: Bool
    @State private var activeSection: RequestSection = .params

    var body: some View {
        ZStack {
            ZapiTheme.editorBackground.ignoresSafeArea()

            if let request = model.selectedRequest {
                VStack(spacing: 14) {
                    RequestTabBar()
                    RequestTopBar(
                        request: request,
                        isEnvironmentManagerPresented: $isEnvironmentManagerPresented
                    )
                    sectionPicker
                    editorPanel(for: request)
                    statusBar(for: request)
                }
                .padding(18)
            } else {
                PlaceholderView(
                    title: "No Request Selected",
                    systemImage: "paperplane",
                    message: "Create a request from the sidebar to start shaping an API call."
                )
                .padding(40)
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $activeSection) {
            ForEach(RequestSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func editorPanel(for request: APIRequest) -> some View {
        switch activeSection {
        case .params:
            panelShell(title: "Query Parameters", subtitle: "Build the request URL with reusable local variables.") {
                keyValueRows(
                    items: request.queryItems,
                    keyPlaceholder: "parameter",
                    valuePlaceholder: "{{value}}",
                    enabled: model.bindingForQueryEnabled,
                    keyBinding: { model.bindingForQueryItem($0, keyPath: \.key) },
                    valueBinding: { model.bindingForQueryItem($0, keyPath: \.value) },
                    remove: model.removeQueryItem
                )

                Button {
                    model.addQueryItem()
                } label: {
                    Label("Add Query Parameter", systemImage: "plus")
                }
                .buttonStyle(.link)
            }
        case .headers:
            panelShell(title: "Headers", subtitle: "Attach custom headers or override auth-generated ones.") {
                keyValueRows(
                    items: request.headers,
                    keyPlaceholder: "Header",
                    valuePlaceholder: "Value",
                    enabled: model.bindingForHeaderEnabled,
                    keyBinding: { model.bindingForHeader($0, keyPath: \.key) },
                    valueBinding: { model.bindingForHeader($0, keyPath: \.value) },
                    remove: model.removeHeader
                )

                Button {
                    model.addHeader()
                } label: {
                    Label("Add Header", systemImage: "plus")
                }
                .buttonStyle(.link)
            }
        case .auth:
            panelShell(title: "Authorization", subtitle: "Configure local auth helpers without any cloud sync.") {
                Picker("Type", selection: model.authKindBinding()) {
                    ForEach(AuthEditorKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                switch model.authKindBinding().wrappedValue {
                case .none:
                    infoMessage("No automatic auth will be added to this request.")
                case .bearer:
                    labeledField("Token", placeholder: "{{token}}", text: model.bearerTokenBinding())
                case .basic:
                    labeledField("Username", placeholder: "username", text: model.basicUsernameBinding())
                    labeledSecureField("Password", placeholder: "password", text: model.basicPasswordBinding())
                case .apiKey:
                    labeledField("Name", placeholder: "X-API-Key", text: model.apiKeyNameBinding())
                    labeledField("Value", placeholder: "{{api_key}}", text: model.apiKeyValueBinding())

                    HStack(spacing: 14) {
                        Text("Location")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)

                        Picker("Location", selection: model.apiKeyLocationBinding()) {
                            ForEach(APIKeyLocation.allCases, id: \.self) { location in
                                Text(location.rawValue.capitalized).tag(location)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }
                }
            }
        case .body:
            panelShell(title: "Body", subtitle: "Send raw payloads, JSON, or urlencoded forms.") {
                Picker("Body Type", selection: model.bodyKindBinding()) {
                    ForEach(BodyEditorKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if case .raw = model.bodyKindBinding().wrappedValue {
                    labeledField("Content-Type", placeholder: "text/plain", text: model.rawContentTypeBinding())
                }

                TextEditor(text: model.bodyTextBinding())
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 300)
                    .background(ZapiTheme.codeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                    )
            }
        }
    }

    private func statusBar(for request: APIRequest) -> some View {
        HStack(spacing: 14) {
            StatusPill(title: "Env", value: model.project.selectedEnvironment?.name ?? "None")
            StatusPill(title: "Timeout", value: "\(Int(request.timeoutInterval))s")
            StatusPill(title: "Redirects", value: request.followRedirects ? "Follow" : "Manual")
            Spacer()
            Text(request.authSummary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func panelShell<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            content()
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }

    private func keyValueRows(
        items: [APIKeyValue],
        keyPlaceholder: String,
        valuePlaceholder: String,
        enabled: @escaping (UUID) -> Binding<Bool>,
        keyBinding: @escaping (UUID) -> Binding<String>,
        valueBinding: @escaping (UUID) -> Binding<String>,
        remove: @escaping (UUID) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("On")
                    .frame(width: 36, alignment: .leading)
                Text("Key")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 32)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Toggle("", isOn: enabled(item.id))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.85)
                        .frame(width: 36)

                    TextField(keyPlaceholder, text: keyBinding(item.id))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ZapiTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                        )

                    TextField(valuePlaceholder, text: valueBinding(item.id))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ZapiTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                        )

                    Button(role: .destructive) {
                        remove(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )
        }
    }

    private func labeledSecureField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )
        }
    }

    private func infoMessage(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ZapiTheme.accentStart)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct RequestTabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.openRequests) { request in
                        RequestTabItem(
                            request: request,
                            collectionName: model.collectionName(for: request.id),
                            isSelected: request.id == model.selectedRequestID,
                            onSelect: {
                                model.selectRequest(
                                    collectionID: model.project.collections.first(where: {
                                        $0.requests.contains(where: { $0.id == request.id })
                                    })?.id,
                                    requestID: request.id
                                )
                            },
                            onClose: {
                                model.closeRequestTab(request.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Button {
                model.addRequest()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(ZapiTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ZapiTheme.panelStroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct RequestTabItem: View {
    let request: APIRequest
    let collectionName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(methodColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.name.isEmpty ? "Untitled Request" : request.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
                    .lineLimit(1)

                Text(collectionName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 196, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? ZapiTheme.selectedEditorItem : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? ZapiTheme.selectedEditorStroke : Color.clear, lineWidth: 1)
        )
        .onTapGesture(perform: onSelect)
    }

    private var methodColor: Color {
        switch request.method {
        case .get: return ZapiTheme.success
        case .post: return ZapiTheme.accentStart
        case .put, .patch: return ZapiTheme.warning
        case .delete: return ZapiTheme.danger
        case .head, .options: return .secondary
        }
    }
}

private struct RequestTopBar: View {
    let request: APIRequest
    @Binding var isEnvironmentManagerPresented: Bool
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker("Method", selection: model.binding(for: \.method, default: .get)) {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )

                TextField("https://api.example.com/resource", text: model.binding(for: \.urlTemplate, default: ""))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(ZapiTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                    )

                Button {
                    model.sendSelectedRequest()
                } label: {
                    HStack(spacing: 8) {
                        if model.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(model.isSending ? "Sending" : "Send")
                            .fontWeight(.semibold)
                    }
                    .frame(width: 96)
                    .padding(.vertical, 10)
                }
                .buttonStyle(SendButtonStyle())
                .disabled(model.isSending)
            }

            HStack(spacing: 10) {
                TextField("Request name", text: model.binding(for: \.name, default: ""))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ZapiTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                    )

                Picker(
                    "Environment",
                    selection: Binding(
                        get: { model.project.selectedEnvironmentID },
                        set: { model.selectEnvironment(id: $0) }
                    )
                ) {
                    ForEach(model.project.environments) { environment in
                        Text(environment.name).tag(Optional(environment.id))
                    }
                }
                .labelsHidden()
                .frame(width: 176)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )

                Toggle("Follow Redirects", isOn: model.binding(for: \.followRedirects, default: true))
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Text("Timeout")
                        .foregroundStyle(.secondary)
                    TextField("60", value: model.binding(for: \.timeoutInterval, default: 60), format: .number)
                        .textFieldStyle(.plain)
                        .frame(width: 48)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )

                Spacer()
            }
        }
        .padding(14)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct EnvironmentManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var renamedKeys: [String: String] = [:]
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { model.project.selectedEnvironmentID },
                set: { model.selectEnvironment(id: $0) }
            )) {
                ForEach(model.project.environments) { environment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(environment.name)
                            .font(.system(size: 13, weight: .bold))
                        Text("\(environment.variables.count) variables")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(environment.id))
                }
            }
            .navigationTitle("Environments")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.addEnvironment()
                    } label: {
                        Label("Add Environment", systemImage: "plus")
                    }

                    Button {
                        model.deleteSelectedEnvironment()
                    } label: {
                        Label("Delete Environment", systemImage: "trash")
                    }
                    .disabled(model.project.environments.count <= 1 || model.selectedEnvironmentIndex == nil)
                }
            }
        } detail: {
            if model.project.selectedEnvironment != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Environment Details")
                                .font(.title3.weight(.bold))
                            Spacer()
                            Button("Done") {
                                dismiss()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Environment name", text: model.bindingForSelectedEnvironmentName())
                        }

                        Divider()

                        HStack {
                            Text("Variables")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.addEnvironmentVariable()
                            } label: {
                                Label("Add Variable", systemImage: "plus")
                            }
                        }

                        TextField("Search variables", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        ForEach(model.filteredEnvironmentKeys(searchText: searchText), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    TextField(
                                        "Key",
                                        text: Binding(
                                            get: { renamedKeys[key] ?? key },
                                            set: { renamedKeys[key] = $0 }
                                        )
                                    )

                                    Button("Rename") {
                                        let newKey = renamedKeys[key] ?? key
                                        model.renameEnvironmentKey(oldKey: key, newKey: newKey)
                                        renamedKeys.removeValue(forKey: key)
                                    }

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(
                                            model.environmentVariableReference(for: key),
                                            forType: .string
                                        )
                                    } label: {
                                        Label("Copy Ref", systemImage: "doc.on.doc")
                                    }

                                    Button(role: .destructive) {
                                        model.removeEnvironmentVariable(key: key)
                                        renamedKeys.removeValue(forKey: key)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }

                                HStack(spacing: 12) {
                                    Toggle("Masked", isOn: model.bindingForEnvironmentMasked(key: key))
                                        .toggleStyle(.switch)

                                    if model.bindingForEnvironmentMasked(key: key).wrappedValue {
                                        SecureField("Value", text: model.bindingForEnvironmentValue(key: key))
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        TextField("Value", text: model.bindingForEnvironmentValue(key: key))
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                            }
                            .padding(12)
                            .background(ZapiTheme.input)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(20)
                }
            } else {
                PlaceholderView(
                    title: "No Environment Selected",
                    systemImage: "shippingbox",
                    message: "Create or select an environment to manage its variables."
                )
                .padding(24)
            }
        }
    }
}

private struct CurlImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var curlCommand = """
curl https://httpbin.org/anything \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{"hello":"world"}'
"""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import cURL")
                        .font(.title3.weight(.bold))
                    Text("Paste a cURL command to create a new request in the current collection.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            TextEditor(text: $curlCommand)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack {
                Text("Supports common flags: `-X`, `-H`, `-d`, `-L`, `--url`, `-u`.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import") {
                    do {
                        try model.importCurlCommand(curlCommand)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
    }
}

private struct ResponseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeTab: ResponseTab = .body

    var body: some View {
        ZStack {
            ZapiTheme.detailBackground.ignoresSafeArea()

            VStack(spacing: 14) {
                responseHeader
                responsePanel
                historyPanel
            }
            .padding(18)
        }
    }

    private var responseHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Response")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("Tab", selection: $activeTab) {
                    ForEach(ResponseTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            metricsRow
            statusStrip

            if let error = model.latestErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ZapiTheme.danger)
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZapiTheme.danger)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ZapiTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private var responsePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.latestResponse != nil {
                if let resolved = model.latestResolvedRequest {
                    inspectorSection(title: "Resolved Request") {
                        Text("\(resolved.method.rawValue) \(resolved.url)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                inspectorSection(title: activeTab.rawValue) {
                    switch activeTab {
                    case .body:
                        responseTextEditor(model.prettyResponseBody)
                    case .headers:
                        headerTable
                    case .request:
                        responseTextEditor(requestPreview)
                    }
                }
            } else {
                Spacer()
                PlaceholderView(
                    title: "No Response Yet",
                    systemImage: "bolt.horizontal.circle",
                    message: "Send the selected request to inspect headers, body, and timing."
                )
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent History")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.project.history.count) entries")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if model.project.history.isEmpty {
                Text("No local request history yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.project.history.prefix(6)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.resolvedRequest.method.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(ZapiTheme.accentStart)
                            Text(entry.resolvedRequest.url)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }

                        Text("Status \(entry.response.statusCode) • \(entry.response.durationMilliseconds) ms")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZapiTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private var metricsRow: some View {
        HStack(spacing: 14) {
            metricItem("Status", model.latestResponse.map { "\($0.statusCode)" } ?? "idle", tint: statusTint)
            Divider().frame(height: 20)
            metricItem("Time", model.latestResponse.map { "\($0.durationMilliseconds) ms" } ?? "0 ms")
            Divider().frame(height: 20)
            metricItem("Size", model.latestResponse.map { "\($0.sizeBytes) B" } ?? "0 B")
            Divider().frame(height: 20)
            metricItem("MIME", model.latestResponse?.mimeType ?? "unknown")
            Spacer()
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(statusTint)
                .frame(width: 8, height: 28)
                .clipShape(Capsule())

            Text(statusText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(statusTint)

            Spacer()

            if let mime = model.latestResponse?.mimeType {
                Text(mime.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusTint.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var headerTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Header")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZapiTheme.chromeStrip)

                ForEach(Array(model.responseHeaderRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.key)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Text(row.value)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ZapiTheme.codeBackground)

                    Divider()
                }
            }
        }
        .background(ZapiTheme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private func responseTextEditor(_ text: String) -> some View {
        TextEditor(text: .constant(text))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZapiTheme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private func metricItem(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint ?? .primary)
        }
    }

    private func inspectorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private var requestPreview: String {
        guard let resolved = model.latestResolvedRequest else { return "No resolved request yet." }

        var lines = ["\(resolved.method.rawValue) \(resolved.url)"]
        if !resolved.headers.isEmpty {
            lines.append("")
            lines.append(contentsOf: resolved.headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" })
        }
        if let body = resolved.bodyPreview, !body.isEmpty {
            lines.append("")
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }

    private var statusTint: Color {
        guard let status = model.latestResponse?.statusCode else { return .secondary }
        switch status {
        case 200..<300: return ZapiTheme.success
        case 300..<400: return ZapiTheme.warning
        default: return ZapiTheme.danger
        }
    }

    private var statusText: String {
        guard let status = model.latestResponse?.statusCode else { return "Idle" }
        switch status {
        case 200..<300: return "Success"
        case 300..<400: return "Redirect"
        case 400..<500: return "Client Error"
        case 500...: return "Server Error"
        default: return "Unknown"
        }
    }
}

private struct ChromeBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.84))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ZapiTheme.chromeStrip)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ZapiTheme.accentStart.opacity(0.16), ZapiTheme.accentEnd.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ZapiTheme.accentStart)
                }

            Text(title)
                .font(.system(size: 20, weight: .bold))

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var renamedKeys: [String: String] = [:]
    @AppStorage("appAppearance") private var appAppearanceRawValue = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appAppearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Workspace") {
                TextField("Project Name", text: Binding(
                    get: { model.project.name },
                    set: {
                        model.project.name = $0
                        model.saveNow()
                    }
                ))
            }

            Section("Selected Environment") {
                if let environmentIndex = model.selectedEnvironmentIndex {
                    let environment = model.project.environments[environmentIndex]

                    ForEach(environment.variables.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField(
                                    "Key",
                                    text: Binding(
                                        get: { renamedKeys[key] ?? key },
                                        set: { renamedKeys[key] = $0 }
                                    )
                                )
                                .frame(maxWidth: 180)

                                TextField("Value", text: model.bindingForEnvironmentValue(key: key))

                                Button("Rename") {
                                    let newKey = renamedKeys[key] ?? key
                                    model.renameEnvironmentKey(oldKey: key, newKey: newKey)
                                    renamedKeys.removeValue(forKey: key)
                                }

                                Button(role: .destructive) {
                                    model.removeEnvironmentVariable(key: key)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        model.addEnvironmentVariable()
                    } label: {
                        Label("Add Variable", systemImage: "plus")
                    }
                } else {
                    Text("No environment selected.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }
}

private struct SidebarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
    }
}

private struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [ZapiTheme.accentEnd, ZapiTheme.accentStart]
                                : [ZapiTheme.accentStart, ZapiTheme.accentEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: ZapiTheme.accentStart.opacity(0.14), radius: 6, x: 0, y: 2)
    }
}

private enum RequestSection: String, CaseIterable, Identifiable {
    case params = "Params"
    case headers = "Headers"
    case auth = "Auth"
    case body = "Body"

    var id: String { rawValue }
}

private enum ResponseTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case headers = "Headers"
    case request = "Request"

    var id: String { rawValue }
}

private enum ZapiTheme {
    static let canvas = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let editorBackground = Color(nsColor: .windowBackgroundColor)
    static let detailBackground = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let inspectorPanel = Color(nsColor: .windowBackgroundColor)
    static let panelStroke = Color.black.opacity(0.08)
    static let input = Color(nsColor: .textBackgroundColor)
    static let codeBackground = Color(nsColor: .textBackgroundColor)
    static let chromeStrip = Color(nsColor: .underPageBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    static let sidebarCard = Color(red: 0.91, green: 0.93, blue: 0.96)
    static let sidebarSelected = Color.accentColor.opacity(0.12)
    static let selectedEditorItem = Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
    static let selectedEditorStroke = Color(nsColor: .selectedContentBackgroundColor).opacity(0.3)
    static let accentStart = Color(red: 0.04, green: 0.56, blue: 0.93)
    static let accentEnd = Color(red: 0.00, green: 0.75, blue: 0.76)
    static let success = Color(red: 0.14, green: 0.67, blue: 0.39)
    static let warning = Color(red: 0.91, green: 0.58, blue: 0.15)
    static let danger = Color(red: 0.87, green: 0.27, blue: 0.30)
}

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private extension APIRequest {
    var authSummary: String {
        switch auth {
        case .none:
            return "No auth"
        case .bearerToken:
            return "Bearer auth"
        case .basic:
            return "Basic auth"
        case let .apiKey(_, _, location):
            return "API Key in \(location.rawValue)"
        }
    }
}
