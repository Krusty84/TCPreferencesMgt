//
//  PrefsBrowserView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 14/08/2025.
//
import Foundation
import SwiftUI
import SwiftData

struct PrefsBrowserView1: View {
    let connectionID: UUID
    @Environment(\.modelContext) private var context
    @Query private var connQ: [TCConnection]
    private var connection: TCConnection? { connQ.first }
    // Leftside panel
    private enum BrowserMode: String, CaseIterable, Identifiable {
        case general = "General"
        case collections = "Collections"
        var id: String { rawValue }
    }
    @State private var expandedCollections: Set<String> = []  // holds TCCollection.key
    @State private var browserMode: BrowserMode = .general
    // Paging
    @State private var pageSize = 2_000
    @State private var loaded = 0
    @State private var allLoaded = false
    
    // Data + filters
    @State private var items: [TCPreference] = []
    @State private var nameFilter: String = ""
    @State private var selectedCategory: String = "All"
    @State private var selectedScope: String = "All"
    //@State private var connection: TCConnection?
    @State private var isSyncing = false
    @State private var lastSyncMessage: String = ""
    // Table selection
    @State private var selection: Set<TCPreference.ID> = []
    
    // --- separate edit states ---
    @State private var editValues = false
    @State private var editComment = false
    
    // temp buffers for edits
    @State private var newValueText = ""
    @State private var draftValues: [String] = []
    @State private var draftComment: String = ""
    
    // helper for arrange data in three columns
    private let kLabelWidth: CGFloat = 130
    private let kRowSpacing: CGFloat = 10
    private let kGap12: CGFloat = 60   // bigger gap between col 1 and 2
    private let kGap23: CGFloat = 20   // smaller gap between col 2 and 3
    
    @State private var sortDescriptors: [SortDescriptor<TCPreference>] = [
        SortDescriptor(\.name, order: .forward)
    ]
    
    //assign prefs to collections
    @Query private var collQ: [TCConnection]
    @State private var showAssignDialog = false
    @State private var collectionNameInput = ""
    @State private var selectedCollectionKey: String = ""   // picks an existing collection
    @State private var newCollectionName: String = ""       // to create a new one
    private enum CollectionChoice: String, CaseIterable, Identifiable {
        case existing = "Existing"
        case new = "Create New"
        var id: String { rawValue }
    }
    @State private var collChoice: CollectionChoice = .existing
    @State private var existingCollections: [TCPreferenceCollection] = []
    
    
    init(connectionID: UUID) {
        self.connectionID = connectionID
        // bind the query to this ID (capture as constant for #Predicate)
        let idConst = connectionID
        _connQ = Query(filter: #Predicate { $0.id == idConst })
        //
        _collQ = Query(
            filter: #Predicate { $0.connectionID == idConst },
            sort: [SortDescriptor(\TCConnectionCollection.name, order: .forward)]
        )
    }
    
    @ViewBuilder
    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) { // tighter label→value gap
            Text(title + ":")
                .fontWeight(.semibold)
                .frame(minWidth: kLabelWidth, alignment: .leading) // aligns labels in a column
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            // no lineLimit -> shows full value, wraps as needed
        }
    }
    //
    @State private var pinCategoryFilter = false
    private enum PrefStatus { case new, changed, stable, missing, unknown }
    
    private func status(for p: TCPreference) -> PrefStatus {
        guard let runEnd = connection?.lastImportCompletedAt,
              let runStart = connection?.lastImportStartedAt else {
            // Fallback: if we have a recent lastImportedAt, treat as stable
            return (p.lastImportedAt.timeIntervalSinceNow > -300) ? .stable : .unknown
        }
        let seenThisRun = (p.lastSeenAt ?? .distantPast) >= runEnd
        if !seenThisRun { return (p.firstSeenAt < runStart) ? .missing : .new }
        if p.firstSeenAt >= runStart { return .new }
        if let changed = p.lastChangedAt, changed >= runStart { return .changed }
        return .stable
    }
    
    @ViewBuilder
    private func statusBadge(_ s: PrefStatus) -> some View {
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
    
    
    var body: some View {
        HStack(spacing: 0) {
            leftSide
            Divider()
            rightSide
        }
        .onAppear { loadNextBatch() }
        .onChange(of: selection) { _ in
            editValues = false; editComment = false; newValueText = ""
            if let p = selectedPref {
                pinCategoryFilter = (selectedCategory == p.category) && (p.category != "All")
            } else {
                pinCategoryFilter = false
            }
        }
        .onChange(of: selectedCategory) { _ in
            if let p = selectedPref {
                pinCategoryFilter = (selectedCategory == p.category) && (p.category != "All")
            } else {
                pinCategoryFilter = false
            }
        }
    }
    
    //MARK: - LeftSide Panel
    
    @ViewBuilder
    private var leftSide: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8){
                Picker("", selection: $browserMode) {
                    ForEach(BrowserMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                
                if browserMode == .general {
                    VStack() {
                        Text("Filters").font(.headline)
                        TextField("Search by name, description, values, or comment", text: $nameFilter)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Picker("Filter by category", selection: $selectedCategory) {
                                Text("All").tag("All")
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            
                            Picker("Filter by protection scope", selection: $selectedScope) {
                                Text("All").tag("All")
                                ForEach(scopes, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        prefTable
                        footerButtons
                    }
                    .contextMenu(forSelectionType: TCPreference.ID.self) { selection in
                        Button("Export…") { exportPreferencesXML(selection) }
                            .disabled(selection.isEmpty)
                        Button("Assign to Collection…") {
                            // Optional: preselect activeCollectionKey if you have one
                            selectedCollectionKey = ""    // none selected by default
                            newCollectionName = ""        // clear previous input
                            showAssignDialog = true
                        }
                        .disabled(selection.isEmpty)
                    }
                    .sheet(isPresented: $showAssignDialog) {
                        assignCollectionSheet(selection: selection)
                    }
                    
                } else if browserMode == .collections {
                     collectionsList
                }
            }
        }
        .padding(12)
        .frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var prefTable: some View {
        Table(filteredItems.sorted(using: sortDescriptors), selection: $selection) {
            // History indicator column (not sortable)
            TableColumn("") { p in
                if hasHistory(p) {
                    Image(systemName: "clock")
                        .help("Has history (\(historyCount(for: p)) records)")
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .width(10)

            // Status badge column (not sortable)
            TableColumn("") { p in
                statusBadge(status(for: p))
                    .frame(width: 18, alignment: .center)
            }
            .width(10)

            // NEW: Collection indicator column
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
        .onChange(of: sortDescriptors) { new in
            sortDescriptors = new
        }
    }
    
    @ViewBuilder
    private var collectionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if collQ.isEmpty {
                Text("No collections defined.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(collQ, id: \.key) { col in
                            // Disclosure per collection
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedCollections.contains(col.key) },
                                    set: { isOpen in
                                        if isOpen { expandedCollections.insert(col.key) }
                                        else { expandedCollections.remove(col.key) }
                                    }
                                )
                            ) {
                                // Body: preferences assigned to this collection
                                let prefs = col.prefCollections.compactMap { $0.preference }
                                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

                                if prefs.isEmpty {
                                    Text("No preferences assigned")
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Table(prefs, selection: $selection) {
                                        TableColumn("") { p in
                                            if hasHistory(p) {
                                                Image(systemName: "clock")
                                                    .help("Has history (\(historyCount(for: p)) records)")
                                            } else {
                                                Color.clear.frame(width: 1, height: 1)
                                            }
                                        }
                                        .width(24)

                                        TableColumn("") { p in
                                            statusBadge(status(for: p))
                                                .frame(width: 18, alignment: .center)
                                        }
                                        .width(24)

                                        TableColumn("Name", value: \.name)
                                        TableColumn("Location", value: \.protectionScope)
                                    }
                                    .frame(minHeight: 120, maxHeight: 240)
                                    .contextMenu(forSelectionType: TCPreference.ID.self) { sel in
                                        Button("Remove from Collection") {
                                            removePreferencesFromCollection(selection: sel, collection: col)
                                        }
                                        .disabled(sel.isEmpty)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(col.name)
                                        .font(.headline)
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
                                Button("Export Collection…") {
                                       let prefs = col.prefCollections.compactMap { $0.preference }
                                       if !prefs.isEmpty {
                                           exportPrefCollectionXML(prefs, fileName: "Pref_\(col.name)_collection.xml")
                                       }
                                   }
                                   .disabled(col.prefCollections.isEmpty)

                                   Divider()

                                   Button("Delete Collection") {
                                       deleteCollection(col)
                                   }
                                   .disabled(!col.prefCollections.isEmpty) // only enabled if empty
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
        .onAppear {
            if expandedCollections.isEmpty {
                expandedCollections = Set(collQ.map(\.key))
            }
        }
    }
    
    
    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: 12) {
            if isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundStyle(.secondary)
            } else if !lastSyncMessage.isEmpty {
                Text(lastSyncMessage).foregroundStyle(.secondary)
            } else {
                Text("Preferences found: \(filteredItems.count)")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("TC Sync") { tcSync() }
                .disabled(isSyncing || connection == nil)
            
            Button("Reload") { reloadAll() }
                .disabled(isSyncing)
            
            Button("Load more") { loadNextBatch() }
                .disabled(allLoaded || isSyncing)
        }
    }
    
    //MARK: - RightSide Panel
    
    @ViewBuilder
    private var rightSide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = selectedPref {
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
    
    @ViewBuilder
    private func descriptionSection(p: TCPreference) -> some View {
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
    
    @ViewBuilder
    private func valuesSection(p: TCPreference) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if editValues {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("New value…", text: $newValueText)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            guard !newValueText.isEmpty else { return }
                            draftValues.append(newValueText)
                            newValueText = ""
                        }
                    }
                }
                
                List {
                    ForEach(editValues ? draftValues : (p.values ?? []), id: \.self) { val in
                        HStack {
                            Text(val).textSelection(.enabled)
                            Spacer()
                            if editValues {
                                Button {
                                    draftValues.removeAll { $0 == val }
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
                
                HStack {
                    if editValues {
                        Button("Save Values") { saveValues() }
                            .keyboardShortcut(.defaultAction)
                        Button("Cancel") { cancelValues() }
                    } else {
                        Button("Edit Values") { beginValuesEdit(from: p) }
                    }
                    Spacer()
                }
            }
        } label: {
            HStack {
                Text("Values")
                Text("(updated \(humanReadableTimeFormat(p.lastChangedAt ?? p.lastImportedAt)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func historySection(p: TCPreference) -> some View {
        GroupBox("History") {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let revs = revisions(for: p)
                    if revs.isEmpty {
                        Text("No history recorded")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    } else {
                        ForEach(revs) { rev in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rev.capturedAt.formatted(date: .numeric, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
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
                            
                            Divider().opacity(0.25)
                        }
                    }
                }
                .padding(2)
            }
            .frame(minHeight: 140, maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func commentSection(p: TCPreference) -> some View {
        GroupBox("Comment") {
            if editComment {
                TextField("Add comment…", text: $draftComment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                HStack {
                    Button("Save Comment") { saveComment() }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { cancelComment() }
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.comment?.isEmpty == false ? p.comment! : "—")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Edit Comment") { beginCommentEdit(from: p) }
                        Spacer()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var placeholderSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Select a preference to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
    
    
    
    // MARK: - Derived
    
    private var selectedPref: TCPreference? {
        guard let id = selection.first else { return nil }
        return items.first { $0.id == id }
    }
    
    private var categories: [String] {
        Array(Set(items.map { $0.category }.filter { !$0.isEmpty })).sorted()
    }
    
    private var scopes: [String] {
        Array(Set(items.map { $0.protectionScope }.filter { !$0.isEmpty })).sorted()
    }
    
    private var filteredItems: [TCPreference] {
        let raw = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = raw.isEmpty ? [] : raw.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        
        return items.filter { p in
            // Category & protection scope filters
            let matchCat   = selectedCategory == "All" || p.category == selectedCategory
            let matchScope = selectedScope == "All" || p.protectionScope == selectedScope
            guard matchCat && matchScope else { return false }
            
            // Text search across multiple fields
            guard !tokens.isEmpty else { return true }
            
            // Build a single searchable string
            let haystack: String = [
                p.name,
                p.prefDescription,
                (p.values ?? []).joined(separator: " "),
                (p.comment ?? "")
            ]
                .joined(separator: " ")
                .lowercased()
            
            // AND semantics: every token must appear somewhere
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
    
    // MARK: - Data
    
    private func loadNextBatch() {
        guard !allLoaded else { return }
        let idConst = connectionID
        
        var d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == idConst },
            sortBy: [SortDescriptor(\TCPreference.name, order: .forward)]
        )
        d.fetchOffset = loaded
        d.fetchLimit = pageSize
        
        do {
            let batch = try context.fetch(d)
            items.append(contentsOf: batch)
            loaded += batch.count
            allLoaded = batch.count < pageSize
        } catch {
            print("Batch fetch error:", error)
        }
    }
    
    private func reloadAll() {
        items.removeAll(keepingCapacity: true)
        selection.removeAll()
        loaded = 0
        allLoaded = false
        loadNextBatch()
    }
    
    // MARK: - Edit: Values
    
    private func beginValuesEdit(from p: TCPreference) {
        draftValues = p.values ?? []
        newValueText = ""
        editValues = true
    }
    
    private func cancelValues() {
        draftValues = []
        newValueText = ""
        editValues = false
    }
    
    private func saveValues() {
        guard let idx = currentIndex else { return }
        items[idx].values = draftValues
        do { try context.save() } catch { print("Save values error:", error) }
        cancelValues()
    }
    
    // MARK: - Edit: Comment
    
    private func beginCommentEdit(from p: TCPreference) {
        draftComment = p.comment ?? ""
        editComment = true
    }
    
    private func cancelComment() {
        draftComment = ""
        editComment = false
    }
    
    private func saveComment() {
        guard let idx = currentIndex else { return }
        items[idx].comment = draftComment
        do { try context.save() } catch { print("Save comment error:", error) }
        cancelComment()
    }
    
    private var currentIndex: Int? {
        guard let id = selection.first else { return nil }
        return items.firstIndex { $0.id == id }
    }
    
    // MARK: - Detail Header
    
    private func detailHeader(p: TCPreference) -> some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 12) {

                // NAME — full width
                field("Name", p.name)

                // MAIN SECTION — three columns
                HStack(alignment: .top, spacing: 0) {
                    // Column 1
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Type", prefsTypeMapping(p.type))
                        field("Protection Scope", p.protectionScope)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(width: kGap12) // big gap 1→2

                    // Column 2
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Location", p.protectionScope)   // keep if you don't have a dedicated location
                        field("Multiple", p.isArray ? "Multiple" : "Single")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(width: kGap23) // small gap 2→3

                    // Column 3
                    VStack(alignment: .leading, spacing: kRowSpacing) {
                        field("Environment", p.isEnvEnabled ? "Enabled" : "Disabled")

                        // Category with pin checkbox
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Category:")
                                .fontWeight(.semibold)
                                .frame(minWidth: kLabelWidth, alignment: .leading)
                            Text(p.category.isEmpty ? "—" : p.category)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Filter by this", isOn: Binding(
                                get: { pinCategoryFilter },
                                set: { newVal in
                                    pinCategoryFilter = newVal
                                    selectedCategory = newVal ? p.category : "All"
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("Filter the list by category '\(p.category)'")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // COLLECTION — its own full-width row
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

                // TIMESTAMPS — bottom row
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
    
    private func labeled(_ title: String, _ view: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title + ":").fontWeight(.semibold).frame(width: 140, alignment: .trailing)
            view
        }
    }
    
    private func revisions(for pref: TCPreference) -> [TCPreferenceRevision] {
        let idConst = pref.id
        var d = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate { $0.preference?.id == idConst },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        do {
            return try context.fetch(d)
        } catch {
            print("Fetch revisions error:", error)
            return []
        }
    }
    
    private func tcSync() {
        guard let conn = connection else { return }
        isSyncing = true
        lastSyncMessage = ""
        
        Task { @MainActor in
            do {
                let processed = try await PreferencesImporter.importAll(
                    context: context,
                    connection: conn,
                    baseUrl: conn.url,
                    batchSize: 2_000
                )
                
                // refresh table data after sync
                items.removeAll(keepingCapacity: true)
                loaded = 0
                allLoaded = false
                loadNextBatch()
                
                lastSyncMessage = "Synced \(processed) preferences."
            } catch {
                lastSyncMessage = "Sync failed: \(error.localizedDescription)"
                print("TC Sync error:", error)
            }
            isSyncing = false
        }
    }
    
    private func humanReadableTimeFormat(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return d.formatted(date: .numeric, time: .shortened)
    }
    
    private func hasHistory(_ pref: TCPreference) -> Bool {
        // Fast path if relation is already loaded:
        if pref.revisions.count > 1 { return true }
        
        // Fallback: cheap existence check via key (avoid PersistentIdentifier)
        let keyConst = pref.key
        var d = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate<TCPreferenceRevision> { rev in
                rev.preference?.key == keyConst
            }
        )
        d.fetchLimit = 2  // only need to know if there are 2+
        do {
            return try context.fetch(d).count > 1
        } catch {
            print("History fetch error:", error)
            return false
        }
    }
    
    private func historyCount(for pref: TCPreference) -> Int {
        // If relation is loaded, use it
        if !pref.revisions.isEmpty { return pref.revisions.count }
        
        // Otherwise fetch by key (stable)
        let keyConst = pref.key
        let d = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate<TCPreferenceRevision> { rev in
                rev.preference?.key == keyConst
            }
        )
        do { return try context.fetch(d).count } catch { return 0 }
    }
    
    private func applySort() {
        // Client-side sort of the currently loaded page
        items = items.sorted(using: sortDescriptors)
    }
    
    // Turn a selection of IDs into actual model objects (from the page you loaded)
    private func prefs(from selection: Set<TCPreference.ID>) -> [TCPreference] {
        // We only have the current page in memory (items), so filter that
        // If you want full-dataset export, fetch by IDs here.
        items.filter { selection.contains($0.id) }
    }
    
    
    private func prefsTypeMapping(_ type: Int) -> String {
        switch type {
            case 0: return "String"
            case 1: return "Logical"
            case 2: return "Integer"
            case 3: return "Double"
            default: return "Code \(type)"
        }
    }
    
    
    // Simple XML escaper
    private func xmlEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }
    
    // Build the export XML string. Matches your example structure.
    private func buildPreferencesXML(_ prefs: [TCPreference]) -> String {
        // Group by category (selected prefs can span many categories)
        let groups = Dictionary(grouping: prefs, by: { $0.category })
        
        var xml = ""
        xml += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<preferences version=\"10.0\">\n"
        
        for category in groups.keys.sorted(by: { $0.localizedCompare($1) == .orderedAscending }) {
            let items = groups[category]!.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })
            
            xml += "  <category name=\"\(xmlEscape(category))\">\n"
            xml += "    <category_description></category_description>\n"
            
            for p in items {
                let typeString = prefsTypeMapping(p.type)
                let arrayAttr  = p.isArray ? "true" : "false"
                let disabled   = p.isDisabled ? "true" : "false"
                let envEnabled = p.isEnvEnabled ? "true" : "false"
                
                xml += "    <preference name=\"\(xmlEscape(p.name))\" " +
                "type=\"\(typeString)\" array=\"\(arrayAttr)\" disabled=\"\(disabled)\" " +
                "protectionScope=\"\(xmlEscape(p.protectionScope))\" envEnabled=\"\(envEnabled)\">\n"
                
                let desc = p.prefDescription.isEmpty ? "" : xmlEscape(p.prefDescription)
                xml += "      <preference_description>\(desc)</preference_description>\n"
                
                // Context + values
                if let vals = p.values, !vals.isEmpty {
                    xml += "      <context name=\"Teamcenter\">\n"
                    for v in vals {
                        xml += "        <value>\(xmlEscape(v))</value>\n"
                    }
                    xml += "      </context>\n"
                } else {
                    // Still emit empty context like your first sample
                    xml += "      <context name=\"Teamcenter\">\n"
                    xml += "      </context>\n"
                }
                
                xml += "    </preference>\n"
            }
            
            xml += "  </category>\n"
        }
        
        xml += "</preferences>\n"
        return xml
    }
    
    // Save panel + write file
    private func exportPreferencesXML(_ selection: Set<TCPreference.ID>) {
        let chosen = prefs(from: selection)
        guard !chosen.isEmpty else { return }
        
        // Suggest a filename
        let suggestedName: String = {
            if chosen.count == 1, let p = chosen.first {
                return "\(p.name).xml"
            } else {
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd-HHmmss"
                return "preferences_export_\(df.string(from: Date())).xml"
            }
        }()
        
        // NSSavePanel
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = suggestedName
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let xml = buildPreferencesXML(chosen)
            do {
                try xml.data(using: .utf8)?.write(to: url)
            } catch {
                // Optional: surface an error (you can replace with a nicer alert/toast)
                print("Export failed:", error)
            }
        }
    }
    
    private func exportPrefCollectionXML(_ prefs: [TCPreference], fileName: String) {
        let xml = buildPreferencesXML(prefs)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = fileName
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try xml.data(using: .utf8)?.write(to: url)
            } catch {
                print("Export failed:", error)
            }
        }
    }
    
    //MARK: Collections features
    
    @ViewBuilder
    private var assignCollectionDialog: some View {
        VStack(spacing: 12) {
            Text("Assign Preferences to Collection")
                .font(.headline)
            
            TextField("Collection name", text: $collectionNameInput)
                .textFieldStyle(.roundedBorder)
            
            if !existingCollections.isEmpty {
                Picker("Or select existing", selection: $collectionNameInput) {
                    ForEach(existingCollections) { col in
                        Text(col.name).tag(col.name)
                    }
                }
                .labelsHidden()
            }
            
            HStack {
                Button("Cancel") { showAssignDialog = false }
                Spacer()
                Button("Assign") {
                    let prefs = filteredItems.filter { selection.contains($0.persistentModelID) }
                    if !prefs.isEmpty {
                        assignToCollection(prefs: prefs, name: collectionNameInput)
                    }
                    showAssignDialog = false
                    collectionNameInput = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
    
    @ViewBuilder
    private func assignCollectionSheet(selection: Set<TCPreference.ID>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assign Preferences to Collection").font(.headline)
            
            Picker("", selection: $collChoice) {
                ForEach(CollectionChoice.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.segmented)
            
            // Existing collections (always visible; disabled when "Create New" selected)
            VStack(alignment: .leading, spacing: 6) {
                Text("Existing").foregroundStyle(.secondary)
                Picker("Existing", selection: $selectedCollectionKey) {
                    Text("—").tag("")   // explicit “none”
                    ForEach(collQ, id: \.key) { c in
                        Text(c.name).tag(c.key)
                    }
                }
                .labelsHidden()
                .disabled(collChoice == .new)
                .opacity(collChoice == .new ? 0.5 : 1.0)
            }
            
            // New collection (always visible; disabled when "Existing" selected)
            VStack(alignment: .leading, spacing: 6) {
                Text("New Collection Name").font(.subheadline)
                TextField("Enter name…", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(collChoice == .existing)
                    .opacity(collChoice == .existing ? 0.5 : 1.0)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    showAssignDialog = false
                    resetAssignInputs()
                }
                Button("Assign") {
                    assignSelectionToCollection(selection)
                    showAssignDialog = false
                    resetAssignInputs()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(assignDisabled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
    
    private func assignSelectionToCollection(_ selection: Set<TCPreference.ID>) {
        // Resolve selected prefs from current page
        let chosenPrefs = filteredItems.filter { selection.contains($0.persistentModelID) }
        guard !chosenPrefs.isEmpty else { return }
        
        // Decide target collection
        let target: TCConnectionCollection
        
        switch collChoice {
            case .existing:
                guard let existing = collQ.first(where: { $0.key == selectedCollectionKey }) else { return }
                target = existing
                
            case .new:
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                
                // Reuse same-name (case-insensitive) if present
                if let existing = collQ.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    target = existing
                } else {
                    guard let connID = chosenPrefs.first?.connectionID else { return }
                    let col = TCConnectionCollection(name: name, connectionID: connID)
                    context.insert(col)
                    target = col
                }
        }
        
        // Link each pref (avoid duplicates)
        for pref in chosenPrefs {
            let alreadyLinked = pref.prefCollections.contains { $0.collection?.key == target.key }
            if !alreadyLinked {
                let link = TCPreferenceJoinTCPreferenceCollection(preference: pref, collection: target, connectionID: pref.connectionID)
                context.insert(link)
            }
        }
        
        do { try context.save() } catch {
            print("Assign to collection save error:", error)
        }
    }
    
    private var assignDisabled: Bool {
        switch collChoice {
            case .existing:
                return selectedCollectionKey.isEmpty
            case .new:
                return newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func resetAssignInputs() {
        collChoice = .existing
        selectedCollectionKey = ""
        newCollectionName = ""
    }
    
    private func fetchCollections() -> [TCPreferenceCollection] {
        let descriptor = FetchDescriptor<TCPreferenceCollection>()
        do { return try context.fetch(descriptor) }
        catch { return [] }
    }
    
    private func assignToCollection(prefs: [TCPreference], name: String) {
        guard !name.isEmpty else { return }
        
        // Find existing or create new
        let col: TCConnectionCollection
        if let existing = fetchCollections().first(where: { $0.name == name }) {
            col = existing
        } else {
            guard let first = prefs.first else { return }
            col = TCConnectionCollection(name: name, connectionID: first.connectionID)
            context.insert(col)
        }
        
        // Assign each pref
        for pref in prefs {
            let join = TCPreferenceJoinTCPreferenceCollection(
                preference: pref,
                collection: col,
                connectionID: pref.connectionID
            )
            context.insert(join)
        }
        
        do {
            try context.save()
        } catch {
            print("❌ Failed to assign prefs to collection: \(error)")
        }
    }
    
    private func deleteCollection(_ col: TCPreferenceCollection) {
        guard col.prefCollections.isEmpty else { return } // safety
        context.delete(col)
        do {
            try context.save()
            print("Deleted empty collection: \(col.name)")
        } catch {
            print("Failed to delete collection:", error)
        }
    }
    
    private func removePreferencesFromCollection(selection: Set<TCPreference.ID>, collection: TCPreferenceCollection) {
        let prefs = filteredItems.filter { selection.contains($0.id) }
        guard !prefs.isEmpty else { return }
        
        for pref in prefs {
            if let link = collection.prefCollections.first(where: { $0.preference?.id == pref.id }) {
                context.delete(link)
            }
        }
        do {
            try context.save()
        } catch {
            print("❌ Remove from collection failed:", error)
        }
    }
}
