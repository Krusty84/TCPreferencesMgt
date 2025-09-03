//
//  PrefsBrowserView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 19/08/2025.
//

import SwiftUI
import SwiftData

struct TCPreferencesBrowserView: View {
    // MARK: Identity & Environment
    let connectionID: UUID
    @Environment(\.modelContext) private var context
    
    // MARK: ViewModel
    @StateObject private var vm: TCPreferencesBrowserViewModel

    // MARK: Local Enums (UI modes only)
    private enum BrowserMode: String, CaseIterable, Identifiable {
        case general = "General"
        case collections = "Collections"
        var id: String { rawValue }
    }
    private enum CollectionsViewKind: String, CaseIterable, Identifiable {
        case user = "Your"
        case recommended = "Recommended"
        var id: String { rawValue }
    }

    // MARK: UI State (left panel)
    @State private var expandedCollections: Set<String> = []  // holds TCCollection.key
    @State private var browserMode: BrowserMode = .general
    @State private var collectionsKind: CollectionsViewKind = .user
    @State private var selectedBOUIObject: String = "All"     // filter for BO UI prefs
    
    // MARK: UI State (dialogs)
    @State private var showAssignDialog = false

    // MARK: Layout helpers
    private let kLabelWidth: CGFloat = 130
    private let kRowSpacing: CGFloat = 10
    private let kGap12: CGFloat = 60   // big gap between columns 1 and 2
    private let kGap23: CGFloat = 20   // small gap between columns 2 and 3

    // MARK: Compare
    @Environment(\.openWindow) private var openWindow
    @State private var showCompareSheet = false

    private func allConnections() -> [TCConnection] {
        (try? context.fetch(FetchDescriptor<TCConnection>())) ?? []
    }
    // MARK: Init
    init(connectionID: UUID) {
        self.connectionID = connectionID
        _vm = StateObject(wrappedValue: TCPreferencesBrowserViewModel(connectionID: connectionID))
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            leftSide
            Divider()
            rightSide
        }
        .onAppear {
            vm.setContext(context)
            vm.initialLoad()
            if expandedCollections.isEmpty {
                expandedCollections = Set(vm.collections.map(\.key))
            }
        }
        .environmentObject(vm)
    }
}

// MARK: - Left Side

private extension TCPreferencesBrowserView {
    @ViewBuilder
    var leftSide: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8){
                Picker("", selection: $browserMode) {
                    ForEach(BrowserMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                
                if browserMode == .general {
                    generalPreferencesList
                } else {
                    collectionPreferencesList
                }
            }
        }
        .padding(12)
        .frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
    }

    // General mode: searchable table + footer
    @ViewBuilder
    var generalPreferencesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack {
                TextField("Search by name, description, values ​​or comments among the loaded", text: $vm.nameFilter)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Filter by category", selection: $vm.selectedCategory) {
                        Text("All").tag("All")
                        ForEach(vm.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .help("Category of preferences")
                    .labelsHidden()
                    
                    Picker("Filter by protection scope", selection: $vm.selectedScope) {
                        Text("All").tag("All")
                        ForEach(vm.scopes, id: \.self) { Text($0).tag($0) }
                    }
                    .help("Level of impact of preferences")
                    .labelsHidden()
                }
                regularPreferencesList
                footerButtons
            }
           // .contextMenu(forSelectionType: TCPreference.ID.self) { selection in
            .contextMenu(forSelectionType: PersistentIdentifier.self) { selection in
                Button("Export…") { vm.exportPreferencesXML(selection: selection) }
                    .disabled(selection.isEmpty)
                Button("Copy to clipboard…") { vm.copyPreferencesXML(selection: selection) }
                    .disabled(selection.isEmpty)
                Divider()
                Button("Compare to…") { showCompareSheet = true }
                    .disabled(selection.isEmpty)
                Divider()
                Button("Assign to collection…") { showAssignDialog = true }
                    .disabled(selection.isEmpty)
            }
            .sheet(isPresented: $showAssignDialog) {
                assignCollectionSheet
            }
            .sheet(isPresented: $showCompareSheet) {
                ComparePickerSheet(
                    currentConnectionID: connectionID,
                    allConnections: allConnections(),
                    onCancel: { showCompareSheet = false },
                    onChoose: { otherIDs in
                        let names = vm.filteredItems
                            .filter { vm.selection.contains($0.persistentModelID) }
                            .map(\.name)
                        let payload = CompareLaunchPayload(
                            leftConnectionID: connectionID,
                            rightConnectionIDs: otherIDs,
                            preferenceNames: names
                        )
                        openWindow(id: "compare", value: payload)
                        showCompareSheet = false
                    }
                )
            }
        }
    }

    // The main table for "General" mode
    @ViewBuilder
    var regularPreferencesList: some View {
        Table(vm.filteredItems.sorted(using: vm.sortDescriptors), selection: $vm.selection) {
            // History indicator (not sortable)
            TableColumn("") { p in
                if vm.hasHistory(p) {
                    Image(systemName: "clock")
                        .help("Has history (\(vm.historyCount(for: p)) records)")
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .width(10)
            
            // Status badge (not sortable)
            TableColumn("") { p in
                preferenceStatusBadge(vm.status(for: p))
                    .frame(width: 18, alignment: .center)
            }
            .width(10)
            
            // Collection indicator
            TableColumn("") { p in
                if !p.prefCollections.isEmpty {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.purple)
                        .help("Assigned to \(p.prefCollections.compactMap { $0.collection?.name }.joined(separator: ", "))")
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .width(10)
            
            TableColumn("Name") { p in
                Text(p.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(p.name)
            }
            TableColumn("Location", value: \.protectionScope).width(52)
        }
        .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: vm.sortDescriptors) { new in
            vm.sortDescriptors = new
        }
    }

    // Collections mode: container with mode switch
    @ViewBuilder
    var collectionPreferencesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $collectionsKind) {
                ForEach(CollectionsViewKind.allCases) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            if collectionsKind == .user {
                userPreferencesCollectionList
            } else {
                recommendedPreferencesCollectionList
            }
        }
    }

    // User-defined collections
    @ViewBuilder
    var userPreferencesCollectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.collections.isEmpty {
                Text("No collections defined.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.collections, id: \.key) { col in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedCollections.contains(col.key) },
                                    set: { isOpen in
                                        if isOpen { expandedCollections.insert(col.key) }
                                        else { expandedCollections.remove(col.key) }
                                    }
                                )
                            ) {
//                                let prefs = col.prefCollections
//                                    .compactMap { $0.preference }
//                                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
//                                
                                let prefs = col.prefCollections
                                    .compactMap { $0.preference }
                                
                                if prefs.isEmpty {
                                    Text("No preferences assigned")
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Table(prefs, selection: $vm.selection) {
                                        TableColumn("") { p in
                                            if vm.hasHistory(p) {
                                                Image(systemName: "clock")
                                                    .help("Has history (\(vm.historyCount(for: p)) records)")
                                            } else {
                                                Color.clear.frame(width: 1, height: 1)
                                            }
                                        }
                                        .width(24)
                                        TableColumn("") { p in
                                            preferenceStatusBadge(vm.status(for: p))
                                                .frame(width: 18, alignment: .center)
                                        }
                                        .width(24)
                                        TableColumn("Name", value: \.name)
                                        TableColumn("Location", value: \.protectionScope)
                                    }
                                    .frame(minHeight: 120, maxHeight: 240)
                                    .contextMenu(forSelectionType: TCPreference.ID.self) { sel in
                                        Button("Remove from Collection") {
                                            vm.removePreferencesFromCollection(selection: sel, collection: col)
                                        }
                                        .disabled(sel.isEmpty)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(col.name).font(.headline)
                                    Spacer()
                                    let count = col.prefCollections.compactMap { $0.preference }.count
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .contextMenu {
                                Button("Export…") {
                                    let prefs = col.prefCollections.compactMap { $0.preference }
                                    if !prefs.isEmpty {
                                        vm.exportPrefCollectionXML(prefs, fileName: "Pref_\(col.name)_collection.xml")
                                    }
                                }
                                .disabled(col.prefCollections.isEmpty)
                                Button("Copy to clipboard…") {
                                    let prefs = col.prefCollections.compactMap { $0.preference }
                                    vm.copyPrefCollectionXML(prefs)
                                }
                                .disabled(col.prefCollections.isEmpty)
                                Divider()
                                Button("Delete") { vm.deleteCollection(col) }
                                    .disabled(!col.prefCollections.isEmpty) // only if empty
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
    }

    // Recommended collections wrapper
    @ViewBuilder
    var recommendedPreferencesCollectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    preferencesImportantForPerfomance
                    preferencesRelatedToBOUI
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
        .padding(8)
    }

    // Recommended: Performance-critical
    @ViewBuilder
    var preferencesImportantForPerfomance: some View {
        DisclosureGroup("Important for performance") {
            let importantPreferences: [TCPreference] = vm.fetchPrefs(for: vm.perfomanceCriticalPreferencesList)
            performanceTable(importantPreferences)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    // Recommended: Business Objects UI (XMLRenderingStylesheets)
    @ViewBuilder
    var preferencesRelatedToBOUI: some View {
        DisclosureGroup("Business objects UI (XMLRenderingStylesheets)") {
            // Fetch all relevant prefs
            let uiPreferences: [TCPreference] = vm.fetchPrefs(for: vm.uiStylesheetsPreferencesList)

            // Build object name list from prefix before "."
            let objectNames: [String] = Array(
                Set(
                    uiPreferences.compactMap { pref in
                        pref.name.contains(".")
                            ? String(pref.name.split(separator: ".").first!)
                            : nil
                    }
                )
            ).sorted()

            VStack(alignment: .leading, spacing: 8) {
                // Object filter
                HStack {
                    Text("Type").foregroundStyle(.secondary)
                    Picker("Type", selection: $selectedBOUIObject) {
                        Text("All").tag("All")
                        ForEach(objectNames, id: \.self) { obj in Text(obj).tag(obj) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Filter table rows by selected object
                let filtered: [TCPreference] = {
                    guard selectedBOUIObject != "All" else { return uiPreferences }
                    return uiPreferences.filter { $0.name.hasPrefix(selectedBOUIObject + ".") }
                }()

                performanceTable(filtered)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Right Side

private extension TCPreferencesBrowserView {
    @ViewBuilder
    var rightSide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = vm.selectedPref {
                    detailHeader(p: p)
                    descriptionSection(p: p)
                    valuesSection(p: p)
                    historySection(p: p)
                    commentSection(p: p)
                } else {
                    placeholderSection
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
    }
}

//Compare Helper - Select another connections
private struct ComparePickerSheet: View {
    let currentConnectionID: UUID
    let allConnections: [TCConnection]
    var onCancel: () -> Void
    var onChoose: ([UUID]) -> Void

    @State private var chosen: Set<UUID> = []

    // de-dupe and exclude the current connection
    private var options: [TCConnection] {
        var seen = Set<UUID>()
        var out: [TCConnection] = []
        for c in allConnections where c.id != currentConnectionID {
            if seen.insert(c.id).inserted { out.append(c) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare to other connections").font(.headline)
            Text("You can select two or more.")
                .foregroundStyle(.secondary)

            // single data source; no nested ForEach
            List(options, selection: $chosen) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name.isEmpty ? "(No name)" : c.name)
                            .font(.headline)
                        Text(c.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.desc).foregroundStyle(.secondary)
                }
                .tag(c.id) // multi-select uses Set<UUID>
                .contentShape(Rectangle())
            }
            .frame(width: 560, height: 280)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("OK") {
                    onChoose(Array(chosen))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(16)
    }
}

// MARK: - Detail + Sections

private extension TCPreferencesBrowserView {
    // Details header card
    func detailHeader(p: TCPreference) -> some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 12) {
                // Name — full width
                field("Name", p.name)
                
                // Three columns grid
                HStack(alignment: .top, spacing: 0) {
                    // Col 1
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Type", vm.prefsTypeMapping(p.type))
                        field("Protection Scope", p.protectionScope)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer().frame(width: kGap12)
                    
                    // Col 2
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Location", p.protectionScope)
                        field("Multiple", p.isArray ? "Multiple" : "Single")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer().frame(width: kGap23)
                    
                    // Col 3
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Environment", p.isEnvEnabled ? "Enabled" : "Disabled")
                        // Category + pin toggle
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Category:")
                                .fontWeight(.semibold)
                                .frame(minWidth: kLabelWidth, alignment: .leading)
                            Text(p.category.isEmpty ? "—" : p.category)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle(isOn: Binding(
                                get: { vm.pinCategoryFilter },
                                set: { newVal in vm.setPinCategory(newVal, for: p) }
                            )) {
                                Image(systemName: "dot.scope")
                            }
                            .toggleStyle(.checkbox)
                            .help("Filter the preferences by category '\(p.category)'")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Collection row
                Divider().padding(.vertical, 6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Collection:")
                        .fontWeight(.semibold)
                        .frame(minWidth: kLabelWidth, alignment: .leading)
                    let names = p.prefCollections.compactMap { $0.collection?.name }
                    Text(names.isEmpty ? "—" : names.joined(separator: ", "))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Timestamps
                Divider().padding(.vertical, 6)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("First Seen", p.firstSeenAt.formatted(date: .numeric, time: .shortened))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer().frame(width: kGap12)
                    
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Last Imported", p.lastImportedAt.formatted(date: .numeric, time: .shortened))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer().frame(width: kGap23)
                    
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Last Changed", p.lastChangedAt?.formatted(date: .numeric, time: .shortened) ?? "—")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Description block
    @ViewBuilder
    func descriptionSection(p: TCPreference) -> some View {
        GroupBox("Description") {
            ScrollView {
                Text(p.prefDescription.isEmpty ? "—" : p.prefDescription)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Values block
    @ViewBuilder
    func valuesSection(p: TCPreference) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if vm.editValues {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("New value…", text: $vm.newValueText)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            guard !vm.newValueText.isEmpty else { return }
                            vm.draftValues.append(vm.newValueText)
                            vm.newValueText = ""
                        }
                    }
                }
                
                List {
                    ForEach(vm.editValues ? vm.draftValues : (p.values ?? []), id: \.self) { val in
                        HStack {
                            Text(val).textSelection(.enabled)
                            Spacer()
                            if vm.editValues {
                                Button {
                                    vm.draftValues.removeAll { $0 == val }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(minHeight: 140)
                .listStyle(.inset)

                // Future inline edit (kept as-is)
                // Buttons commented out by you — unchanged
            }
        } label: {
            HStack {
                Text("Values")
                Text("(updated \(vm.humanReadableTimeFormat(p.lastChangedAt ?? p.lastImportedAt)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // History block
    @ViewBuilder
    func historySection(p: TCPreference) -> some View {
        GroupBox("History") {
            ScrollView(.vertical) {
                HistoryList(prefID: p.persistentModelID)
            }
            .frame(minHeight: 140, maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private struct HistoryList: View {
        let prefID: PersistentIdentifier
        @EnvironmentObject var vm: TCPreferencesBrowserViewModel
        @State private var revs: [TCPreferenceRevision] = []

        var body: some View {
            LazyVStack(alignment: .leading, spacing: 8) {
                if revs.isEmpty {
                    Text("No history recorded")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    // explicit id helps the type-checker
                    ForEach(revs, id: \.persistentModelID) { rev in
                        HistoryRow(prefID: prefID, rev: rev)
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(2)
            .task(id: prefID) {
                revs = vm.revisions(for: prefID)
            }
        }
    }

    private struct HistoryRow: View {
        let prefID: PersistentIdentifier
        let rev: TCPreferenceRevision
        @EnvironmentObject var vm: TCPreferencesBrowserViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(rev.capturedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        vm.copyHistoryRevisionXML(prefID: prefID, rev: rev)
                    } label: {
                        Image(systemName: "clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy this revision of the preference to the clipboard")
                }

                if let vals = rev.values, !vals.isEmpty {
                    Text(vals.joined(separator: ", "))
                        .textSelection(.enabled)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(4)
        }
    }


    // Comment block
    @ViewBuilder
    func commentSection(p: TCPreference) -> some View {
        GroupBox("Comment") {
            if vm.editComment {
                TextField("Add comment…", text: $vm.draftComment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                HStack {
                    Button("Save Comment") { vm.saveComment() }
                    Button("Cancel") { vm.cancelComment() }
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.comment?.isEmpty == false ? p.comment! : "—")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Edit Comment") { vm.beginCommentEdit(from: p) }
                            .help("Add your comment here")
                        Spacer()
                    }
                }
            }
        }
    }

    // Placeholder when nothing selected
    @ViewBuilder
    var placeholderSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Select a preference to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

// MARK: - Shared UI Pieces

private extension TCPreferencesBrowserView {
    // Reusable label:value row
    @ViewBuilder
    func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title + ":")
                .fontWeight(.semibold)
                .frame(minWidth: kLabelWidth, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // BO UI helper (kept for future use)
    func bouiObjectNames() -> [String] {
        let names = vm.uiStylesheetsPreferencesList
            .compactMap { $0.contains(".") ? String($0.split(separator: ".").first!) : nil }
        return Array(Set(names)).sorted()
    }

    // Footer actions + status
    @ViewBuilder
    var footerButtons: some View {
        HStack(spacing: 12) {
            if vm.isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundStyle(.secondary)
            } else if !vm.lastSyncMessage.isEmpty {
                Text(vm.lastSyncMessage).foregroundStyle(.secondary)
            } else {
                Text("Total preferences: \(vm.connection?.preferences.count ?? 0)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("TC Sync") { vm.tcSync() }
                .disabled(vm.isSyncing || vm.connection == nil)
            Button("Loaded \(vm.filteredItems.count)") { vm.loadNextBatch() }
                .disabled(vm.allLoaded || vm.isSyncing)
        }
    }

    // Table used by recommended sections
    @ViewBuilder
    func performanceTable(_ prefs: [TCPreference]) -> some View {
        if prefs.isEmpty {
            Text("No matching preferences found in this connection.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Table(prefs, selection: $vm.selection) {
                // History
                TableColumn("") { p in
                    if vm.hasHistory(p) {
                        Image(systemName: "clock")
                            .help("Has history (\(vm.historyCount(for: p)) records)")
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .width(18)

                // Status
                TableColumn("") { p in
                    preferenceStatusBadge(vm.status(for: p))
                        .frame(width: 18, alignment: .center)
                }
                .width(18)

                // Bookmark
                TableColumn("") { p in
                    if !p.prefCollections.isEmpty {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.purple)
                            .help("Assigned to \(p.prefCollections.compactMap { $0.collection?.name }.joined(separator: ", "))")
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .width(18)

                // Name
                TableColumn("Name") { p in
                    Text(p.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(p.name)
                }

                // Location
                TableColumn("Location", value: \TCPreference.protectionScope)
                    .width(120)
            }
            .frame(minHeight: 160, maxHeight: 280)
            .contextMenu(forSelectionType: TCPreference.ID.self) { selection in
                Button("Export…") { vm.exportPreferencesXML(selection: selection) }
                    .disabled(selection.isEmpty)
                Button("Copy to clipboard…") { vm.copyPreferencesXML(selection: selection) }
                    .disabled(selection.isEmpty)
                Divider()
                Button("Assign to collection…") { showAssignDialog = true }
                    .disabled(selection.isEmpty)
            }
        }
    }

    // Status badge (pure UI)
    @ViewBuilder
    func preferenceStatusBadge(_ s: TCPreferencesBrowserViewModel.PrefStatus) -> some View {
        switch s {
        case .new:
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .help("New in the latest import")
        case .changed:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.orange)
                .help("Changed in the latest import")
        case .stable:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Unchanged in the latest import")
        case .missing:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
                .help("Missing in the latest import (was present before)")
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.gray)
                .help("Status unknown — run an import to compute status")
        }
    }

    // Assign-to-collection sheet
    @ViewBuilder
    var assignCollectionSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assign Preferences to Collection").font(.headline)
            
            Picker("", selection: $vm.collChoice) {
                ForEach(TCPreferencesBrowserViewModel.CollectionChoice.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.segmented)
            
            // Existing collections
            VStack(alignment: .leading, spacing: 6) {
                Text("Existing").foregroundStyle(.secondary)
                Picker("Existing", selection: $vm.selectedCollectionKey) {
                    Text("—").tag("")
                    ForEach(vm.collections, id: \.key) { c in
                        Text(c.name).tag(c.key)
                    }
                }
                .labelsHidden()
                .disabled(vm.collChoice == .new)
                .opacity(vm.collChoice == .new ? 0.5 : 1.0)
            }
            
            // New collection
            VStack(alignment: .leading, spacing: 6) {
                Text("New Collection Name").font(.subheadline)
                TextField("Enter name…", text: $vm.newCollectionName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.collChoice == .existing)
                    .opacity(vm.collChoice == .existing ? 0.5 : 1.0)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    showAssignDialog = false
                    vm.resetAssignInputs()
                }
                Button("Assign") {
                    vm.assignSelectionToCollection()
                    showAssignDialog = false
                    vm.resetAssignInputs()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.assignDisabled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
    
}
