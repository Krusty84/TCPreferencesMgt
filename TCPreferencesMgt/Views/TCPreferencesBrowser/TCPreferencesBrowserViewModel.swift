//
//  PrefsBrowserViewModel.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 19/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import LoggerHelper

@MainActor
final class TCPreferencesBrowserViewModel: ObservableObject {
    // MARK: - Inputs
    let connectionID: UUID
    private(set) var context: ModelContext!

    // MARK: - Data
    @Published var connection: TCConnection?
    @Published var items: [TCPreference] = []
    @Published var collections: [TCPreferenceCollection] = []

    // MARK: - UI State & Filters
//    @Published var selection: Set<TCPreference.ID> = [] {
//        didSet {
//            clearEditsOnSelectionChange()
//            updatePinCategory()
//        }
//    }
    @Published var selection: Set<PersistentIdentifier> = []
    @Published var compareSelection: Set<PersistentIdentifier> = []
    @Published var nameFilter: String = ""
    @Published var selectedCategory: String = "All" { didSet { updatePinCategory() } }
    @Published var selectedScope: String = "All"
    @Published var sortDescriptors: [SortDescriptor<TCPreference>] = [
        SortDescriptor(\.name, order: .forward)
    ]

    // MARK: - Paging
    @Published var pageSize: Int = 2_000
    private(set) var loaded: Int = 0
    @Published var allLoaded: Bool = false

    // MARK: - Sync
    @Published var isSyncing = false
    @Published var lastSyncMessage: String = ""

    // MARK: - Edit state
    @Published var editValues = false
    @Published var editComment = false

    @Published var newValueText = ""
    @Published var draftValues: [String] = []
    @Published var draftComment: String = ""

    // MARK: - Category pin
    @Published var pinCategoryFilter = false

    // MARK: - Collections assignment
    enum CollectionChoice: String, CaseIterable, Identifiable {
        case existing = "Existing"
        case new = "Create New"
        var id: String { rawValue }
    }
    @Published var collChoice: CollectionChoice = .existing
    @Published var selectedCollectionKey: String = ""
    @Published var newCollectionName: String = ""
    
    // MARK: - Predefined Collection preferences list
    @Published var perfomanceCriticalPreferencesList: [String] = [
        "Fms_BootStrap_Urls",
        "Mail_OSMail_activated",
        "Mail_server_name",
        "Mail_server_port",
        "ADA_enabled"
    ]
    //
    @Published var uiStylesheetsPreferencesList: [String] = [
        "RENDERING"
    ]
    // MARK: - Status
    enum PrefStatus { case new, changed, stable, missing, unknown }

    // MARK: - Init
    init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    func setContext(_ context: ModelContext) {
        self.context = context
        fetchConnection()
        refreshCollections()
    }

    // MARK: - Derived
//    var selectedPref: TCPreference? {
//        guard let id = selection.first else { return nil }
//        return items.first { $0.id == id }
//    }
    
    var selectedPref: TCPreference? {
        guard let id = selection.first else { return nil }
        return items.first { $0.persistentModelID == id }
    }

    var categories: [String] {
        Array(Set(items.map { $0.category }.filter { !$0.isEmpty })).sorted()
    }

    var scopes: [String] {
        Array(Set(items.map { $0.protectionScope }.filter { !$0.isEmpty })).sorted()
    }

    var filteredItems: [TCPreference] {
        let raw = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = raw.isEmpty ? [] : raw.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)

        return items.filter { p in
            let matchCat   = selectedCategory == "All" || p.category == selectedCategory
            let matchScope = selectedScope == "All" || p.protectionScope == selectedScope
            guard matchCat && matchScope else { return false }

            guard !tokens.isEmpty else { return true }
            let haystack = ([p.name, p.prefDescription] + (p.values ?? []) + [p.comment ?? ""]).joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: - Loading
    @MainActor
    func initialLoad() {
        guard context != nil else { return }
        loaded = 0
        allLoaded = false
        items.removeAll(keepingCapacity: true)
        loadNextBatch()
    }

    @MainActor
    func loadNextBatch() {
        guard context != nil, !allLoaded else { return }
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
            LoggerHelper.error("Batch fetch error: \(error)")
        }
    }

    func reloadAll() {
        items.removeAll(keepingCapacity: true)
        selection.removeAll()
        loaded = 0
        allLoaded = false
        loadNextBatch()
    }

    @MainActor
    private func fetchConnection() {
        guard context != nil else { return }
        let idConst = connectionID
        let d = FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == idConst })
        do { connection = try context.fetch(d).first } catch { connection = nil }
    }

    @MainActor
    func refreshCollections() {
        guard context != nil else { collections = []; return }
        let descriptor = FetchDescriptor<TCPreferenceCollection>(
            predicate: #Predicate { $0.connectionID == connectionID },
            sortBy: [SortDescriptor(\TCPreferenceCollection.name, order: .forward)]
        )
        do { collections = try context.fetch(descriptor) } catch { collections = [] }
    }
    
    /// Fetch by exact names and/or substring terms (case-insensitive).
    /// - Exact name: contains a dot, e.g. "BOMItem.SUMMARYRENDERING"
    /// - Substring term: no dot, e.g. "RENDERING", "SUMMARYRENDERING"
    @MainActor
    func fetchPrefs(for namesOrTerms: [String]) -> [TCPreference] {
        guard !namesOrTerms.isEmpty else { return [] }

        // Split into exact names vs substring tokens
        let exactNames = namesOrTerms.filter { $0.contains(".") }
        let tokens = namesOrTerms
            .filter { !$0.contains(".") }
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        var results: [TCPreference] = []

        // 1) Exact-name matches via SwiftData predicate (fast and precise)
        if !exactNames.isEmpty {
            let set = Set(exactNames)
            var d = FetchDescriptor<TCPreference>(
                predicate: #Predicate { p in
                    p.connectionID == connectionID && set.contains(p.name)
                },
                sortBy: [SortDescriptor(\TCPreference.name, order: .forward)]
            )
            if let fetched = try? context.fetch(d) {
                results.append(contentsOf: fetched)
            }
        }

        // 2) Substring matches (case-insensitive) — filter an in-memory pool
        if !tokens.isEmpty {
            // Prefer what you already loaded; otherwise fetch once for this connection
            var pool = items
            if pool.isEmpty {
                var dAll = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == connectionID },
                    sortBy: [SortDescriptor(\TCPreference.name, order: .forward)]
                )
                if let fetchedAll = try? context.fetch(dAll) {
                    pool = fetchedAll
                }
            }

            let more = pool.filter { p in
                let n = p.name.lowercased()
                return tokens.contains(where: { n.contains($0) })
            }
            results.append(contentsOf: more)
        }

        // De-duplicate (in case an item matched both exact and substring paths) and sort
        var seen = Set<String>() // use your stable unique key
        let unique = results.filter { seen.insert($0.key).inserted }
        return unique.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Status & History
    @MainActor
    func status(for p: TCPreference) -> PrefStatus {
        guard let conn = connection,
              let runEnd = conn.lastImportCompletedAt,
              let runStart = conn.lastImportStartedAt else {
            return (p.lastImportedAt.timeIntervalSinceNow > -300) ? .stable : .unknown
        }
        let seenThisRun = (p.lastSeenAt ?? .distantPast) >= runEnd
        if !seenThisRun { return (p.firstSeenAt < runStart) ? .missing : .new }
        if p.firstSeenAt >= runStart { return .new }
        if let changed = p.lastChangedAt, changed >= runStart { return .changed }
        return .stable
    }
    
    @MainActor
    func revisions(for id: PersistentIdentifier) -> [TCPreferenceRevision] {
        // re-fetch the preference on this context
        let predPref = #Predicate<TCPreference> { $0.persistentModelID == id }
        var fdPref = FetchDescriptor<TCPreference>(predicate: predPref, sortBy: [])
        guard let pref = try? context.fetch(fdPref).first else { return [] }

        var fd = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate { $0.preference?.persistentModelID == id },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return (try? context.fetch(fd)) ?? []
    }

    @MainActor
    func hasHistory(_ pref: TCPreference) -> Bool {
        if pref.revisions.count > 1 { return true }
        guard context != nil else { return false }
        let keyConst = pref.key
        var d = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate<TCPreferenceRevision> { rev in rev.preference?.key == keyConst }
        )
        d.fetchLimit = 2
        do { return try context.fetch(d).count > 1 } catch { LoggerHelper.error("History fetch error: \(error)"); return false }
    }

    @MainActor
    func historyCount(for pref: TCPreference) -> Int {
        if !pref.revisions.isEmpty { return pref.revisions.count }
        guard context != nil else { return 0 }
        let keyConst = pref.key
        let d = FetchDescriptor<TCPreferenceRevision>(
            predicate: #Predicate<TCPreferenceRevision> { rev in rev.preference?.key == keyConst }
        )
        do { return try context.fetch(d).count } catch { return 0 }
    }

    // MARK: - Edits
    func beginValuesEdit(from p: TCPreference) {
        draftValues = p.values ?? []
        newValueText = ""
        editValues = true
    }

    func cancelValues() {
        draftValues = []
        newValueText = ""
        editValues = false
    }

    func saveValues() {
        guard let idx = currentIndex else { return }
        items[idx].values = draftValues
        do { try context.save() } catch { LoggerHelper.error("Save values error: \(error)") }
        cancelValues()
    }

    func beginCommentEdit(from p: TCPreference) {
        draftComment = p.comment ?? ""
        editComment = true
    }

    func cancelComment() {
        draftComment = ""
        editComment = false
    }

    func saveComment() {
        guard let idx = currentIndex else { return }
        items[idx].comment = draftComment
        do { try context.save() } catch { LoggerHelper.error("Save comment error: \(error)")}
        cancelComment()
    }

    private var currentIndex: Int? {
        guard let pid = selection.first else { return nil }
        return items.firstIndex { $0.persistentModelID == pid }
    }

    private func clearEditsOnSelectionChange() {
        editValues = false
        editComment = false
        newValueText = ""
    }

    private func updatePinCategory() {
        if let p = selectedPref {
            pinCategoryFilter = (selectedCategory == p.category) && (p.category != "All")
        } else {
            pinCategoryFilter = false
        }
    }

    func setPinCategory(_ newValue: Bool, for p: TCPreference) {
        pinCategoryFilter = newValue
        selectedCategory = newValue ? p.category : "All"
    }

    // MARK: - Export XML
    //func exportPreferencesXML(selection: Set<TCPreference.ID>) {
    func exportPreferencesXML(selection: Set<PersistentIdentifier>) {
        let chosen = prefs(from: selection)
        guard !chosen.isEmpty else { return }

        let suggestedName: String = {
            if chosen.count == 1, let p = chosen.first {
                return "\(p.name).xml"
            } else {
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd-HHmmss"
                return "preferences_export_\(df.string(from: Date())).xml"
            }
        }()

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = suggestedName

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard let self else { return }
            let xml = self.buildPreferencesXML(chosen)
            do { try xml.data(using: .utf8)?.write(to: url) } catch { LoggerHelper.error("Export failed: \(error)")}
        }
    }

    func exportPrefCollectionXML(_ prefs: [TCPreference], fileName: String) {
        let xml = buildPreferencesXML(prefs)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = fileName

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try xml.data(using: .utf8)?.write(to: url) } catch { LoggerHelper.error("Export failed: \(error)") }
        }
    }
    
    //func copyPreferencesXML(selection: Set<TCPreference.ID>) {
    func copyPreferencesXML(selection: Set<PersistentIdentifier>) {
        let chosen = prefs(from: selection)
        guard !chosen.isEmpty else { return }
        let xml = buildPreferencesXML(chosen)
        copyToClipboard(xml)
    }
    
    func copyPrefCollectionXML(_ prefs: [TCPreference]) {
        guard !prefs.isEmpty else { return }
        let xml = buildPreferencesXML(prefs)
        copyToClipboard(xml)
    }
    
    func copyHistoryRevisionXML(prefID: PersistentIdentifier, rev: TCPreferenceRevision) {
        let pred = #Predicate<TCPreference> { $0.persistentModelID == prefID }
        var fd = FetchDescriptor<TCPreference>(predicate: pred)
        guard let pref = try? context.fetch(fd).first else { return }
        var xml = ""
        xml += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<preferences version=\"10.0\">\n"
        xml += "  <category name=\"\(xmlEscape(pref.category))\">\n"
        xml += "    <category_description></category_description>\n"
        xml += "    <preference name=\"\(xmlEscape(pref.name))\" " +
                "type=\"\(prefsTypeMapping(pref.type))\" array=\"\(pref.isArray ? "true" : "false")\" " +
                "disabled=\"\(pref.isDisabled ? "true" : "false")\" " +
                "protectionScope=\"\(xmlEscape(pref.protectionScope))\" " +
                "envEnabled=\"\(pref.isEnvEnabled ? "true" : "false")\">\n"
        
        let desc = pref.prefDescription.isEmpty ? "" : xmlEscape(pref.prefDescription)
        xml += "      <preference_description>\(desc)</preference_description>\n"

        xml += "      <context name=\"Teamcenter\">\n"
        if let vals = rev.values {
            for v in vals {
                xml += "        <value>\(xmlEscape(v))</value>\n"
            }
        }
        xml += "      </context>\n"

        xml += "    </preference>\n"
        xml += "  </category>\n"
        xml += "</preferences>\n"

        copyToClipboard(xml)
    }

//    private func prefs(from selection: Set<TCPreference.ID>) -> [TCPreference] {
//        items.filter { selection.contains($0.id) }
//    }
    
    private func prefs(from selection: Set<PersistentIdentifier>) -> [TCPreference] {
        items.filter { selection.contains($0.persistentModelID) }
    }
    
    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func prefsTypeMapping(_ type: Int) -> String {
        switch type {
            case 0: return "String"
            case 1: return "Logical"
            case 2: return "Integer"
            case 3: return "Double"
            default: return "Code \(type)"
        }
    }

    private func xmlEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }

    private func buildPreferencesXML(_ prefs: [TCPreference]) -> String {
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

                if let vals = p.values, !vals.isEmpty {
                    xml += "      <context name=\"Teamcenter\">\n"
                    for v in vals {
                        xml += "        <value>\(xmlEscape(v))</value>\n"
                    }
                    xml += "      </context>\n"
                } else {
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

    // MARK: - Collections features
    var assignDisabled: Bool {
        switch collChoice {
            case .existing: return selectedCollectionKey.isEmpty
            case .new: return newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @MainActor
    func assignSelectionToCollection() {
       // let chosenPrefs = filteredItems.filter { selection.contains($0.id) }
        let chosenPrefs = filteredItems.filter { selection.contains($0.persistentModelID) }
        guard !chosenPrefs.isEmpty else { return }

        let target: TCPreferenceCollection
        switch collChoice {
            case .existing:
                guard let existing = collections.first(where: { $0.key == selectedCollectionKey }) else { return }
                target = existing
            case .new:
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    target = existing
                } else {
                    guard let connID = chosenPrefs.first?.connectionID else { return }
                    let col = TCPreferenceCollection(name: name, connectionID: connID)
                    context.insert(col)
                    target = col
                }
        }

        for pref in chosenPrefs {
            let alreadyLinked = pref.prefCollections.contains { $0.collection?.key == target.key }
            if !alreadyLinked {
                let link = TCPreferenceJoinTCPreferenceCollection(preference: pref, collection: target, connectionID: pref.connectionID)
                context.insert(link)
            }
        }

        do { try context.save() } catch { LoggerHelper.error("Assign to collection save error: \(error)")}
        refreshCollections()
    }

    func resetAssignInputs() {
        collChoice = .existing
        selectedCollectionKey = ""
        newCollectionName = ""
    }

    @MainActor
    func assignToCollection(prefs: [TCPreference], name: String) {
        guard !name.isEmpty else { return }

        let col: TCPreferenceCollection
        if let existing = (try? context.fetch(FetchDescriptor<TCPreferenceCollection>()))?.first(where: { $0.name == name }) {
            col = existing
        } else {
            guard let first = prefs.first else { return }
            col = TCPreferenceCollection(name: name, connectionID: first.connectionID)
            context.insert(col)
        }

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
            LoggerHelper.error("Failed to assign prefs to collection: \(error)")
        }
        refreshCollections()
    }

    @MainActor
    func deleteCollection(_ col: TCPreferenceCollection) {
        guard col.prefCollections.isEmpty else { return }
        context.delete(col)
        do {
            try context.save()
            refreshCollections()
        } catch {
            LoggerHelper.error("Failed to delete collection: \(error)")
        }
    }

    @MainActor
    func removePreferencesFromCollection(selection: Set<TCPreference.ID>, collection: TCPreferenceCollection) {
        let prefs = filteredItems.filter { selection.contains($0.id) }
        guard !prefs.isEmpty else { return }

        for pref in prefs {
            if let link = collection.prefCollections.first(where: { $0.preference?.id == pref.id }) {
                context.delete(link)
            }
        }
        do { try context.save() } catch { LoggerHelper.error("Remove from collection failed: \(error)")}
        refreshCollections()
    }

    // MARK: - Sync
    @MainActor
    func tcSync() {
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

                //lastSyncMessage = "Synced \(processed) preferences."
                lastSyncMessage = "Preferences synced."
            } catch {
                lastSyncMessage = "Sync failed: \(error.localizedDescription)"
                LoggerHelper.error("TC Synchronization error: \(error)")
            }
            isSyncing = false
        }
    }

    // MARK: - Utils
    func humanReadableTimeFormat(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return d.formatted(date: .numeric, time: .shortened)
    }
}
