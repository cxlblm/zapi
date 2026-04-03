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
    @State private var isCurlExportPresented = false
    @State private var isOpenAPIImportPresented = false
    @State private var isCodeSnippetsPresented = false

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

                    Button {
                        isOpenAPIImportPresented = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .help("Import OpenAPI")

                    Button {
                        isCurlExportPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .help("Export cURL")
                    .disabled(model.selectedRequest == nil)

                    Button {
                        isCodeSnippetsPresented = true
                    } label: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Generate Code Snippets")
                    .disabled(model.selectedRequest == nil)

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

                    Button {
                        model.saveNow()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save")
                    .keyboardShortcut("s", modifiers: [.command])
                }
                .controlSize(.small)
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
        .sheet(isPresented: $isOpenAPIImportPresented) {
            OpenAPIImportSheet()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .sheet(isPresented: $isCurlExportPresented) {
            CurlExportSheet()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 440)
        }
        .sheet(isPresented: $isCodeSnippetsPresented) {
            CodeSnippetsSheet()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 520)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isEnvironmentManagerPresented: Bool
    @State private var activeTab: SidebarContentTab = .requests
    @State private var historySearchText = ""
    @State private var historyFilter: HistoryStatusFilter = .all
    @State private var onlySelectedRequestHistory = false
    @State private var isClearHistoryConfirmationPresented = false
    @State private var historyDeleteTarget: RequestHistoryEntry?
    @State private var renameTarget: SidebarRenameTarget?
    @State private var deleteTarget: SidebarDeleteTarget?

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            sourceList

            sidebarFooter
        }
        .background(ZapiTheme.sidebarBackground)
        .sheet(item: $renameTarget) { target in
            RenameItemSheet(
                title: target.title,
                fieldLabel: target.fieldLabel,
                initialName: target.currentName
            ) { updatedName in
                switch target.kind {
                case let .collection(id):
                    model.renameCollection(id: id, to: updatedName)
                case let .request(id):
                    model.renameRequest(id: id, to: updatedName)
                }
            }
        }
        .confirmationDialog(
            deleteTarget?.title ?? "",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let deleteTarget {
                Button(deleteTarget.confirmationTitle, role: .destructive) {
                    switch deleteTarget.kind {
                    case let .collection(id):
                        model.deleteCollection(id: id)
                    case let .request(id):
                        model.deleteRequest(id: id)
                    }
                    self.deleteTarget = nil
                }
            }

            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            if let deleteTarget {
                Text(deleteTarget.message)
            }
        }
        .confirmationDialog(
            "Clear History?",
            isPresented: $isClearHistoryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                model.clearHistory()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All local request history entries will be removed from this workspace.")
        }
        .confirmationDialog(
            "Delete History Entry?",
            isPresented: Binding(
                get: { historyDeleteTarget != nil },
                set: { if !$0 { historyDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let historyDeleteTarget {
                Button("Delete Entry", role: .destructive) {
                    model.deleteHistoryEntry(id: historyDeleteTarget.id)
                    self.historyDeleteTarget = nil
                }
            }

            Button("Cancel", role: .cancel) {
                historyDeleteTarget = nil
            }
        } message: {
            if let historyDeleteTarget {
                Text("The local history entry for \(historyDeleteTarget.resolvedRequest.method.rawValue) \(historyDeleteTarget.resolvedRequest.url) will be removed.")
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZapiTheme.separator)
                .frame(height: 1)
        }
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $activeTab) {
                    ForEach(SidebarContentTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                switch activeTab {
                case .requests:
                    requestsList
                case .history:
                    historyDrawer
                }
            }
            .padding(14)
        }
    }

    private var requestsList: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                SidebarCollectionSection(
                    collection: collection,
                    onAddRequest: {
                        model.addRequest(to: collection.id)
                    },
                    onMoveCollectionUp: {
                        model.moveCollection(id: collection.id, direction: .up)
                    },
                    onMoveCollectionDown: {
                        model.moveCollection(id: collection.id, direction: .down)
                    },
                    onRenameCollection: {
                        renameTarget = SidebarRenameTarget(
                            kind: .collection(collection.id),
                            currentName: collection.name
                        )
                    },
                    onDeleteCollection: {
                        deleteTarget = SidebarDeleteTarget(
                            kind: .collection(collection.id),
                            name: collection.name
                        )
                    },
                    onSelectRequest: { requestID in
                        model.selectRequest(collectionID: collection.id, requestID: requestID)
                    },
                    onRenameRequest: { request in
                        renameTarget = SidebarRenameTarget(
                            kind: .request(request.id),
                            currentName: model.requestName(for: request)
                        )
                    },
                    onDuplicateRequest: { request in
                        model.duplicateRequest(id: request.id)
                    },
                    onMoveRequestUp: { request in
                        model.moveRequest(id: request.id, direction: .up)
                    },
                    onMoveRequestDown: { request in
                        model.moveRequest(id: request.id, direction: .down)
                    },
                    onDeleteRequest: { request in
                        deleteTarget = SidebarDeleteTarget(
                            kind: .request(request.id),
                            name: model.requestName(for: request)
                        )
                    }
                )
            }
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

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("History")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                if !model.project.history.isEmpty {
                    Button("Clear") {
                        isClearHistoryConfirmationPresented = true
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10, weight: .semibold))
                }
                Text("\(filteredHistory.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TextField("Search URL, method, or status", text: $historySearchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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

            historyDetailCard

            if filteredHistory.isEmpty {
                Text("Send a request to populate local history.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(filteredHistory) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(historyStatusColor(entry.response.statusCode))
                                .frame(width: 7, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.resolvedRequest.url)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(entry.resolvedRequest.method.rawValue) • Status \(entry.response.statusCode) • \(entry.response.durationMilliseconds) ms")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.inspectHistoryEntry(entry)
                        }

                        HStack(spacing: 6) {
                            Button {
                                model.inspectHistoryEntry(entry)
                            } label: {
                                Label("Inspect", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SidebarMiniButtonStyle())

                            Button {
                                model.resendHistoryEntry(entry)
                            } label: {
                                Label("Resend", systemImage: "paperplane")
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

                            Button {
                                historyDeleteTarget = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SidebarMiniButtonStyle())
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(model.selectedHistoryEntryID == entry.id ? ZapiTheme.sidebarSelected : ZapiTheme.sidebarCard)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var historyDetailCard: some View {
        if let entry = model.selectedHistoryEntry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Entry")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("\(entry.resolvedRequest.method.rawValue) • Status \(entry.response.statusCode)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Text(entry.executedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(entry.resolvedRequest.url)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    historyMetaPill("Time", "\(entry.response.durationMilliseconds) ms")
                    historyMetaPill("Size", "\(entry.response.sizeBytes) B")
                    historyMetaPill("MIME", entry.response.mimeType ?? "unknown")
                }

                HStack(spacing: 6) {
                    Button {
                        model.inspectHistoryEntry(entry)
                    } label: {
                        Label("Inspect", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SidebarMiniButtonStyle())

                    Button {
                        model.resendHistoryEntry(entry)
                    } label: {
                        Label("Resend", systemImage: "paperplane")
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

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.resolvedRequest.url, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SidebarMiniButtonStyle())

                    Button {
                        historyDeleteTarget = entry
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SidebarMiniButtonStyle())
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ZapiTheme.sidebarCard)
            )
        } else if !model.project.history.isEmpty {
            Text("Select a history entry to inspect its request and response metadata.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private func historyMetaPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ZapiTheme.input)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ZapiTheme.separator)
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
    let onAddRequest: () -> Void
    let onMoveCollectionUp: () -> Void
    let onMoveCollectionDown: () -> Void
    let onRenameCollection: () -> Void
    let onDeleteCollection: () -> Void
    let onSelectRequest: (UUID) -> Void
    let onRenameRequest: (APIRequest) -> Void
    let onDuplicateRequest: (APIRequest) -> Void
    let onMoveRequestUp: (APIRequest) -> Void
    let onMoveRequestDown: (APIRequest) -> Void
    let onDeleteRequest: (APIRequest) -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(collection.requests.count) requests")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("New Request", action: onAddRequest)
                    Button("Move Collection Up", action: onMoveCollectionUp)
                        .disabled(!model.canMoveCollection(id: collection.id, direction: .up))
                    Button("Move Collection Down", action: onMoveCollectionDown)
                        .disabled(!model.canMoveCollection(id: collection.id, direction: .down))
                    Button("Rename Collection", action: onRenameCollection)
                    Button("Delete Collection", role: .destructive, action: onDeleteCollection)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary)
            }

            ForEach(collection.requests) { request in
                SidebarRequestRow(
                    request: request,
                    isSelected: request.id == model.selectedRequestID,
                    onRename: {
                        onRenameRequest(request)
                    },
                    onDuplicate: {
                        onDuplicateRequest(request)
                    },
                    onMoveUp: {
                        onMoveRequestUp(request)
                    },
                    onMoveDown: {
                        onMoveRequestDown(request)
                    },
                    onDelete: {
                        onDeleteRequest(request)
                    }
                )
                .onTapGesture {
                    onSelectRequest(request.id)
                }
            }
        }
    }
}

private struct SidebarRequestRow: View {
    let request: APIRequest
    let isSelected: Bool
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text(request.method.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.name.isEmpty ? "Untitled Request" : request.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)

                Text(request.urlTemplate)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                Button("Rename Request", action: onRename)
                Button("Duplicate Request", action: onDuplicate)
                Button("Move Up", action: onMoveUp)
                    .disabled(!model.canMoveRequest(id: request.id, direction: .up))
                Button("Move Down", action: onMoveDown)
                    .disabled(!model.canMoveRequest(id: request.id, direction: .down))
                Button("Delete Request", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? ZapiTheme.sidebarSelected : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
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

private struct RenameItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let fieldLabel: String
    let initialName: String
    let onSave: (String) -> Void

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(fieldLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(fieldLabel, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            name = initialName
        }
    }
}

private struct SidebarRenameTarget: Identifiable {
    enum Kind {
        case collection(UUID)
        case request(UUID)
    }

    let kind: Kind
    let currentName: String

    var id: UUID {
        switch kind {
        case let .collection(id), let .request(id):
            return id
        }
    }

    var title: String {
        switch kind {
        case .collection:
            return "Rename Collection"
        case .request:
            return "Rename Request"
        }
    }

    var fieldLabel: String {
        switch kind {
        case .collection:
            return "Collection Name"
        case .request:
            return "Request Name"
        }
    }
}

private struct SidebarDeleteTarget {
    enum Kind {
        case collection(UUID)
        case request(UUID)
    }

    let kind: Kind
    let name: String

    var title: String {
        switch kind {
        case .collection:
            return "Delete Collection?"
        case .request:
            return "Delete Request?"
        }
    }

    var confirmationTitle: String {
        switch kind {
        case .collection:
            return "Delete Collection"
        case .request:
            return "Delete Request"
        }
    }

    var message: String {
        switch kind {
        case .collection:
            return "\"\(name)\" and its requests will be removed from the local workspace."
        case .request:
            return "\"\(name)\" will be removed from the local workspace."
        }
    }
}

private struct SidebarMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
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
                VStack(spacing: 10) {
                    RequestTabBar()
                    RequestTopBar(
                        request: request,
                        isEnvironmentManagerPresented: $isEnvironmentManagerPresented
                    )
                    requestDiagnosticsView(for: request)
                    sectionPicker
                    editorPanel(for: request)
                    statusBar(for: request)
                }
                .padding(14)
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
        .padding(3)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
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
                    remove: model.removeQueryItem,
                    allowVariableInsertion: true
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
                    remove: model.removeHeader,
                    allowVariableInsertion: true
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
                    labeledField("Token", placeholder: "{{token}}", text: model.bearerTokenBinding(), allowVariableInsertion: true)
                case .basic:
                    labeledField("Username", placeholder: "username", text: model.basicUsernameBinding(), allowVariableInsertion: true)
                    labeledSecureField("Password", placeholder: "password", text: model.basicPasswordBinding(), allowVariableInsertion: true)
                case .apiKey:
                    labeledField("Name", placeholder: "X-API-Key", text: model.apiKeyNameBinding())
                    labeledField("Value", placeholder: "{{api_key}}", text: model.apiKeyValueBinding(), allowVariableInsertion: true)

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
                let bodyKind = model.bodyKindBinding().wrappedValue

                Picker("Body Type", selection: model.bodyKindBinding()) {
                    ForEach(BodyEditorKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if case .raw = bodyKind {
                    labeledField("Content-Type", placeholder: "text/plain", text: model.rawContentTypeBinding())
                }

                switch bodyKind {
                case .form:
                    if case let .formURLEncoded(fields) = request.body {
                        keyValueRows(
                            items: fields,
                            keyPlaceholder: "field",
                            valuePlaceholder: "value",
                            enabled: model.bindingForFormEnabled,
                            keyBinding: { model.bindingForFormField($0, keyPath: \.key) },
                            valueBinding: { model.bindingForFormField($0, keyPath: \.value) },
                            remove: model.removeFormField,
                            allowVariableInsertion: true
                        )

                        Button {
                            model.addFormField()
                        } label: {
                            Label("Add Form Field", systemImage: "plus")
                        }
                        .buttonStyle(.link)
                    }
                case .none, .raw, .json:
                    HStack {
                        Spacer()

                        if case .json = bodyKind {
                            Button("Format JSON") {
                                model.formatSelectedJSONBody()
                            }
                            .buttonStyle(.link)
                        }

                        EnvironmentReferenceMenu(labelText: "Insert Variable") { key in
                            model.bodyTextBinding().appendReference(
                                model.environmentVariableReference(for: key),
                                separator: "\n"
                            )
                        }
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
    }

    @ViewBuilder
    private func requestDiagnosticsView(for request: APIRequest) -> some View {
        let diagnostics = model.requestDiagnostics(for: request)

        if diagnostics.preview != nil || diagnostics.hasIssues {
            VStack(alignment: .leading, spacing: 8) {
                if let preview = diagnostics.preview {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Resolved URL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(preview.url)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }
                }

                if !diagnostics.missingKeys.isEmpty {
                    diagnosticNotice(
                        text: "Missing environment variables: \(formattedKeyList(diagnostics.missingKeys))",
                        systemImage: "exclamationmark.circle.fill",
                        tint: ZapiTheme.warning,
                        actionTitle: "Manage"
                    ) {
                        isEnvironmentManagerPresented = true
                    }
                }

                if !diagnostics.emptyKeys.isEmpty {
                    diagnosticNotice(
                        text: "Empty environment values: \(formattedKeyList(diagnostics.emptyKeys))",
                        systemImage: "exclamationmark.circle.fill",
                        tint: ZapiTheme.warning,
                        actionTitle: "Manage"
                    ) {
                        isEnvironmentManagerPresented = true
                    }
                }

                if let previewErrorMessage = diagnostics.previewErrorMessage {
                    diagnosticNotice(
                        text: previewErrorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: ZapiTheme.danger,
                        actionTitle: nil
                    ) {
                        isEnvironmentManagerPresented = true
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func statusBar(for request: APIRequest) -> some View {
        HStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
        remove: @escaping (UUID) -> Void,
        allowVariableInsertion: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("On")
                    .frame(width: 36, alignment: .leading)
                Text("Key")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 28)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ZapiTheme.chromeStrip)

            Divider()

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Toggle("", isOn: enabled(item.id))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .frame(width: 36)

                    HStack(spacing: 6) {
                        TextField(keyPlaceholder, text: keyBinding(item.id))
                            .textFieldStyle(.roundedBorder)

                        if allowVariableInsertion {
                            EnvironmentReferenceMenu(labelText: nil) { key in
                                keyBinding(item.id).appendReference(
                                    model.environmentVariableReference(for: key)
                                )
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        TextField(valuePlaceholder, text: valueBinding(item.id))
                            .textFieldStyle(.roundedBorder)

                        if allowVariableInsertion {
                            EnvironmentReferenceMenu(labelText: nil) { key in
                                valueBinding(item.id).appendReference(
                                    model.environmentVariableReference(for: key)
                                )
                            }
                        }
                    }

                    Button(role: .destructive) {
                        remove(item.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 13, weight: .regular))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ZapiTheme.panelStroke, lineWidth: 1)
        )
    }

    private func labeledField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        allowVariableInsertion: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)

            if allowVariableInsertion {
                EnvironmentReferenceMenu(labelText: nil) { key in
                    text.appendReference(model.environmentVariableReference(for: key))
                }
            }
        }
    }

    private func labeledSecureField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        allowVariableInsertion: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)

            if allowVariableInsertion {
                EnvironmentReferenceMenu(labelText: nil) { key in
                    text.appendReference(model.environmentVariableReference(for: key))
                }
            }
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

    @ViewBuilder
    private func diagnosticNotice(
        text: String,
        systemImage: String,
        tint: Color,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedKeyList(_ keys: [String]) -> String {
        let previewKeys = keys.prefix(3)
            .map { model.environmentVariableReference(for: $0) }
            .joined(separator: ", ")

        if keys.count > 3 {
            return "\(previewKeys) +\(keys.count - 3) more"
        }

        return previewKeys
    }
}

private struct EnvironmentReferenceMenu: View {
    @EnvironmentObject private var model: AppModel

    let labelText: String?
    let onSelect: (String) -> Void

    var body: some View {
        if !model.selectedEnvironmentVariableKeys.isEmpty {
            Menu {
                ForEach(model.selectedEnvironmentVariableKeys, id: \.self) { key in
                    Button(model.environmentVariableReference(for: key)) {
                        onSelect(key)
                    }
                }
            } label: {
                if let labelText {
                    Label(labelText, systemImage: "curlybraces")
                } else {
                    Image(systemName: "curlybraces")
                        .frame(width: 18, height: 18)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Insert environment variable reference")
        }
    }
}

private struct RequestTabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Method", selection: model.binding(for: \.method, default: .get)) {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .padding(.vertical, 1)

                TextField("https://api.example.com/resource", text: model.binding(for: \.urlTemplate, default: ""))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))

                EnvironmentReferenceMenu(labelText: nil) { key in
                    model.binding(for: \.urlTemplate, default: "").appendReference(
                        model.environmentVariableReference(for: key)
                    )
                }

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
                    .textFieldStyle(.roundedBorder)

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
                .padding(.vertical, 1)

                Toggle("Follow Redirects", isOn: model.binding(for: \.followRedirects, default: true))
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Text("Timeout")
                        .foregroundStyle(.secondary)
                    TextField("60", value: model.binding(for: \.timeoutInterval, default: 60), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(ZapiTheme.chromeStrip)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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

private struct CurlExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var curlCommand = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export cURL")
                        .font(.title3.weight(.bold))
                    Text("Review the resolved local request as a cURL command and copy it anywhere.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
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
            } else {
                Text("The command uses the currently selected environment and resolved request values.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: .constant(curlCommand))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(curlCommand, forType: .string)
                }
                .disabled(curlCommand.isEmpty)
            }
        }
        .padding(20)
        .task(id: model.selectedRequestID) {
            do {
                curlCommand = try model.exportSelectedRequestAsCurl()
                errorMessage = nil
            } catch {
                curlCommand = ""
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OpenAPIImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var documentText = """
{
  "openapi": "3.0.0",
  "info": {
    "title": "Sample API",
    "version": "1.0.0"
  },
  "servers": [
    { "url": "https://api.example.com" }
  ],
  "paths": {
    "/users/{id}": {
      "get": {
        "summary": "Get User",
        "parameters": [
          { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
        ]
      }
    }
  }
}
"""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import OpenAPI")
                        .font(.title3.weight(.bold))
                    Text("Paste an OpenAPI JSON document to create a local collection of requests.")
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
            } else {
                Text("Current scope: OpenAPI JSON documents. Server variables and path parameters are imported as local placeholders like `{{id}}`.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $documentText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Import") {
                    do {
                        try model.importOpenAPIDocument(documentText)
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

private struct CodeSnippetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var selectedFormat: CodeSnippetFormat = .swiftURLSession
    @State private var snippet = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generate Code")
                        .font(.title3.weight(.bold))
                    Text("Generate ready-to-copy code snippets from the currently selected request.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            Picker("Format", selection: $selectedFormat) {
                ForEach(CodeSnippetFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            TextEditor(text: .constant(snippet))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(ZapiTheme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ZapiTheme.panelStroke, lineWidth: 1)
                )
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
                .disabled(snippet.isEmpty)
            }
        }
        .padding(20)
        .task(id: selectedFormat) {
            refreshSnippet()
        }
        .task(id: model.selectedRequestID) {
            refreshSnippet()
        }
    }

    private func refreshSnippet() {
        do {
            snippet = try model.generateCodeSnippet(format: selectedFormat)
            errorMessage = nil
        } catch {
            snippet = ""
            errorMessage = error.localizedDescription
        }
    }
}

private struct ResponseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeTab: ResponseTab = .body

    var body: some View {
        ZStack {
            ZapiTheme.detailBackground.ignoresSafeArea()

            VStack(spacing: 10) {
                responseHeader
                responsePanel
            }
            .padding(14)
        }
    }

    private var responseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Response")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Picker("", selection: $activeTab) {
                    ForEach(ResponseTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 244)
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
        .padding(12)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ZapiTheme.panelStroke, lineWidth: 1))
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZapiTheme.inspectorPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ZapiTheme.panelStroke, lineWidth: 1))
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricItem("Status", model.latestResponse.map { "\($0.statusCode)" } ?? "idle", tint: statusTint)
            Divider().frame(height: 18)
            metricItem("Time", model.latestResponse.map { "\($0.durationMilliseconds) ms" } ?? "0 ms")
            Divider().frame(height: 18)
            metricItem("Size", model.latestResponse.map { "\($0.sizeBytes) B" } ?? "0 B")
            Divider().frame(height: 18)
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
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
        VStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ZapiTheme.accentStart.opacity(0.16), ZapiTheme.accentEnd.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(ZapiTheme.accentStart)
                }

            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.vertical, 10)
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

private enum SidebarContentTab: String, CaseIterable, Identifiable {
    case requests = "Requests"
    case history = "History"

    var id: String { rawValue }
}

private enum ZapiTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let editorBackground = Color(nsColor: .windowBackgroundColor)
    static let detailBackground = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let inspectorPanel = Color(nsColor: .controlBackgroundColor)
    static let panelStroke = Color.black.opacity(0.035)
    static let separator = Color.black.opacity(0.025)
    static let input = Color(nsColor: .textBackgroundColor)
    static let codeBackground = Color(nsColor: .textBackgroundColor)
    static let chromeStrip = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarCard = Color(nsColor: .controlBackgroundColor)
    static let sidebarSelected = Color.accentColor.opacity(0.08)
    static let selectedEditorItem = Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
    static let selectedEditorStroke = Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
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

private extension Binding where Value == String {
    func appendReference(_ reference: String, separator: String = "") {
        let currentValue = wrappedValue

        guard !currentValue.contains(reference) else { return }

        if currentValue.isEmpty {
            wrappedValue = reference
        } else if separator.isEmpty {
            wrappedValue = currentValue + reference
        } else {
            let resolvedSeparator = currentValue.hasSuffix(separator) ? "" : separator
            wrappedValue = currentValue + resolvedSeparator + reference
        }
    }
}
