//
//  CompareWindowView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 23/08/2025.
//

import SwiftUI
import SwiftData
import TCSwiftBridge

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Independent width measuring (two keys)

private struct NameWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct CategoryWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension View {
    func measureNameWidth(_ assign: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: NameWidthKey.self, value: g.size.width) })
            .onPreferenceChange(NameWidthKey.self, perform: assign)
    }
    func measureCategoryWidth(_ assign: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: CategoryWidthKey.self, value: g.size.width) })
            .onPreferenceChange(CategoryWidthKey.self, perform: assign)
    }
}

// MARK: - Compare

struct CompareWindowView: View {
    let payload: CompareLaunchPayload

    @Environment(\.modelContext) private var context

    // Connections
    @State private var leftConn: TCConnection?
    @State private var rightConns: [TCConnection] = []
    @State private var activeRightIndex: Int = 0
    @State private var nameFilter: String = ""
    // Per-connection snapshot timestamps shown in headers
    @State private var connSnapshotTS: [UUID: Date] = [:]

    // Snapshots: name -> values
    @State private var leftDB:  [String:[String]] = [:]
    @State private var rightDBs: [[String:[String]]] = []

    // Refresh/UI state
    @State private var isRefreshingLeft = false
    @State private var isRefreshingAllRights = false
    @State private var isRefreshingActiveRight = false
    @State private var showOnlyDiffs = true
    @State private var leftIsFresh: Bool = false
    @State private var rightIsFresh: [Bool] = []
    // animated progress per column
    @State private var leftIsUpdating: Bool = false
    @State private var rightIsUpdating: [Bool] = []
    private var isBusy: Bool {
        isRefreshingLeft
        || isRefreshingAllRights
        || leftIsUpdating
        || rightIsUpdating.contains(true)
    }
    @State private var lastError: String = ""
    @State private var leftUpdateError: String? = nil
    @State private var rightUpdateErrors: [UUID: String] = [:]

    // Column sizing
    @State private var nameColWidth: CGFloat = 260
    @State private var catColWidth:  CGFloat = 160
    private let valColWidth: CGFloat = 280
    private let indColWidth: CGFloat = 26

    private let edgeGutter: CGFloat = 6
    private let headerHeight: CGFloat = 46
    
    private let rowHSpacing: CGFloat = 3        // was 6
    private let headerHPad: CGFloat = 4         // was 6–8 in places
    private let headerVPad: CGFloat = 5         // was 6
    private let cellHPad: CGFloat   = 4         // was 6
    private let cellVPad: CGFloat   = 3         // was 4
    private let separatorWidth: CGFloat = 0.75  // was 1
    
    
    init(payload: CompareLaunchPayload) { self.payload = payload }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            table
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, edgeGutter)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .padding(.horizontal, edgeGutter)
        .frame(minWidth: 1000, minHeight: 560)
        .task { await initialLoad() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            // Top row: title + controls
            HStack(spacing: 12) {
               // Text("Compare Preferences").font(.title3).bold()
                TextField("Search by name, category, or values among the loaded", text: $nameFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Spacer()
                Toggle("Show only differences", isOn: $showOnlyDiffs)
                    .toggleStyle(.switch)
                    .disabled(isBusy)

                Divider().frame(height: 22)

                // 2 buttons only
                Button {
                    Task { await refreshLeft() }
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshingLeft { ProgressView().controlSize(.small) }
                        Text("Update Left")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                
                Button {
                    Task { await refreshAllRights() }
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshingAllRights { ProgressView().controlSize(.small) }
                        Text("Update All Compared")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || rightConns.isEmpty)
            }

        }
        .padding(.horizontal, edgeGutter)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func sourceBadge(isFresh: Bool) -> some View {
        Group {
            if isFresh {
                Image(systemName: "bolt.fill").foregroundStyle(.blue)
            } else {
                Image(systemName: "tray").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func tinySpinner() -> some View {
        ProgressView().controlSize(.small).scaleEffect(0.7)
    }
    
    @ViewBuilder
    private func headerStatusIcon(isUpdating: Bool, isFresh: Bool, error: String?) -> some View {
        if isUpdating {
            ProgressView().controlSize(.small).scaleEffect(0.7)
        } else if let _ = error {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if isFresh {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            // neutral/initial state; keep compact
            // Image(systemName: "tray").foregroundStyle(.secondary).opacity(0.7)
        }
    }

    private func captionText(isUpdating: Bool, isFresh: Bool, ts: Date?, error: String?) -> (String, Color) {
        if isUpdating { return ("Updating…", .secondary) }
        if let e = error { return ("\(e)", .red) }
        if isFresh { return ("Updated: " + tsString(ts), .secondary) }
        return ("Snapshot: " + tsString(ts), .secondary)
    }
    
    
    // MARK: Table (single horizontal scrollbar at header level)
    
    private var table: some View {
        let allNames  = Array(Set(payload.preferenceNames)).sorted { $0.localizedCompare($1) == .orderedAscending }
        let shownNames = showOnlyDiffs ? allNames.filter { rowHasAnyDiff(name: $0) } : allNames

        return HStack(spacing: 0) {
            // LEFT PANE (frozen): Name, Category, Left column header + left values with single vertical scroll
            VStack(spacing: 0) {
                // Left headers (no horizontal scroll)
                HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
                    Text("Name").font(.headline)
                        .measureNameWidth { nameColWidth = max(nameColWidth, $0) }
                        .frame(width: nameColWidth, alignment: .leading)

                    Text("Category").font(.headline)
                        .measureCategoryWidth { catColWidth = max(catColWidth, $0) }
                        .frame(width: catColWidth, alignment: .leading)

                    // Left connection title + timestamp (stays frozen)
                    VStack(alignment: .leading, spacing: 2){
                        HStack(spacing: 6) {
                            sourceBadge(isFresh: leftIsFresh)
                            Text(leftConnTitle).font(.headline).lineLimit(1).truncationMode(.tail)
                            if leftIsUpdating { tinySpinner() }
                        }
                        if let leftID = leftConn?.id {
                            Text(leftIsUpdating ? "Updating…" : tsString(connSnapshotTS[leftID]))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(width: valColWidth, alignment: .leading)
                    .help({
                        guard let leftID = leftConn?.id else { return leftConnTitle }
                        return leftIsUpdating
                            ? "\(leftConnTitle)\nUpdating"
                            : columnHelp(leftConnTitle, isFresh: leftIsFresh, ts: connSnapshotTS[leftID])
                    }())
                }
                .padding(.vertical, 6)
                .background(.thinMaterial)

                Divider()

                // Left rows (vertical scroll only)
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shownNames.enumerated()), id: \.offset) { (rowIndex, n) in
                            HStack(alignment: .top, spacing: rowHSpacing) {
                                Text(n)
                                    .textSelection(.enabled)
                                    .lineLimit(1).truncationMode(.tail)
                                    .measureNameWidth { nameColWidth = max(nameColWidth, $0) }
                                    .frame(width: nameColWidth, alignment: .leading)

                                Text(category(for: n))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.tail)
                                    .measureCategoryWidth { catColWidth = max(catColWidth, $0) }
                                    .frame(width: catColWidth, alignment: .leading)

                                valueDiffCell(left: leftDB[n], right: nil)
                                    .frame(width: valColWidth, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                            .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))

                            Divider().opacity(0.15)
                        }
                    }
                }
            }

            // Vertical separator between frozen and scrolling panes
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 1)

            // RIGHT PANE: one Horizontal ScrollView that hosts BOTH the header captions and the right-side rows,
            //              so you get a single horizontal scrollbar at the header level.
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Right headers (inside the same horizontal scroller)
                    HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
                        ForEach(rightConns.indices, id: \.self) { idx in
                            let c = rightConns[idx]
                            let name = rightTitle(idx)
                            let isUpd = rightIsUpdating[safe: idx] ?? false

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    sourceBadge(isFresh: rightIsFresh[safe: idx] ?? false)
                                    Text(name).font(.headline).lineLimit(1).truncationMode(.tail)
                                    if isUpd { tinySpinner() }
                                }
                                Text(isUpd ? "Updating…" : tsString(connSnapshotTS[c.id]))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: valColWidth, alignment: .leading)
                            .help(isUpd
                                  ? "\(name)\nUpdating"
                                  : columnHelp(name, isFresh: rightIsFresh[safe: idx] ?? false,
                                               ts: connSnapshotTS[c.id]))

                            Text("Δ").font(.headline)
                                .frame(width: indColWidth, alignment: .center)
                                .help("Status vs Left")
                        }
                    }
                    .padding(.vertical, 6)
                    .background(.thinMaterial)

                    Divider()

                    // Right rows (vertical scroll INSIDE the same horizontal scroller)
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shownNames.enumerated()), id: \.offset) { (rowIndex, n) in
                                HStack(alignment: .top, spacing: rowHSpacing) {
                                    ForEach(rightConns.indices, id: \.self) { idx in
                                        let r = rightDBs[safe: idx]?[n]
                                        valueDiffCell(left: leftDB[n], right: r)
                                            .frame(width: valColWidth, alignment: .leading)

                                        statusDot(decideStatus(left: leftDB[n], right: r))
                                            .frame(width: indColWidth, alignment: .center)
                                    }
                                }
                                .padding(.vertical, 6)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))

                                Divider().opacity(0.15)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            // Status / totals
            Group {
                if !lastError.isEmpty {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if isRefreshingLeft {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Updating left (\(leftConnTitle))…")
                            .foregroundStyle(.secondary)
                    }
                } else if isRefreshingAllRights {
                    let updating = rightIsUpdating.filter { $0 }.count
                    let totalR   = max(rightConns.count, 1)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Updating compared connections… \(updating)/\(totalR)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let total = Set(payload.preferenceNames).count
                    let diffs = payload.preferenceNames.filter { rowHasAnyDiff(name: $0) }.count
                    Text("Total: \(total) • Differences: \(diffs)")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Close") { NSApplication.shared.keyWindow?.close() }
                .disabled(isBusy)
        }
        .padding(.horizontal, edgeGutter)
        .padding(.vertical, 6)
    }

    // MARK: Cells

    @ViewBuilder
    private func valueDiffCell(left: [String]?, right: [String]?) -> some View {
        let show = right ?? left
        let joined = (show?.isEmpty ?? true) ? "—" : show!.joined(separator: ", ")
        let isDifferent: Bool = { guard let r = right else { return false }
            return decideStatus(left: left, right: r) != .same
        }()

        Text(joined)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.vertical, cellVPad)      // tighter
            .padding(.horizontal, cellHPad)    // tighter
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDifferent ? Color.orange.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDifferent ? Color.orange.opacity(0.30) : Color.clear, lineWidth: 1)
            )
            .help(joined)
    }

    private func statusDot(_ s: RowStatus) -> some View {
        switch s {
        case .same:
            return Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Same")
        case .different:
            return Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help("Different")
        case .onlyLeft:
            return Image(systemName: "arrow.left.circle.fill").foregroundStyle(.blue).help("Only Left")
        case .onlyRight:
            return Image(systemName: "arrow.right.circle.fill").foregroundStyle(.purple).help("Only Right")
        }
    }

    private enum RowStatus { case same, different, onlyLeft, onlyRight }
    
    // MARK: Columns
    
    @ViewBuilder
    private func valueHeader(
        title: String,
        timestamp: Date?,
        isFresh: Bool,
        isUpdating: Bool,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: isFresh ? "bolt.fill" : "tray")
                    .font(.caption)
                    .foregroundStyle(isFresh ? .blue : .secondary)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isUpdating {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                }
            }
            Text(isUpdating ? "Updating…" :
                 (timestamp.map { $0.formatted(date: .numeric, time: .shortened) } ?? "—"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
    
    // MARK: Data helpers

    private var leftConnTitle: String {
        guard let c = leftConn else { return "Left" }
        return c.name.isEmpty ? c.url : c.name
    }
    private func rightTitle(_ idx: Int) -> String {
        guard rightConns.indices.contains(idx) else { return "Right \(idx+1)" }
        let c = rightConns[idx]; return c.name.isEmpty ? c.url : c.name
    }

    private func category(for name: String) -> String {
        let nameConst = name
        do {
            if let leftID = leftConn?.id {
                var d = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == leftID && $0.name == nameConst }
                )
                d.fetchLimit = 1
                if let p = try context.fetch(d).first { return p.category }
            }
            for rc in rightConns {
                let cid = rc.id
                var d2 = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == cid && $0.name == nameConst }
                )
                d2.fetchLimit = 1
                if let p2 = try context.fetch(d2).first { return p2.category }
            }
        } catch { }
        return ""
    }

    private func rowHasAnyDiff(name: String) -> Bool {
        let l = leftDB[name]
        for idx in rightConns.indices {
            let r = rightDBs[safe: idx]?[name]
            if decideStatus(left: l, right: r) != .same { return true }
        }
        return false
    }

    private func decideStatus(left: [String]?, right: [String]?) -> RowStatus {
        switch (left, right) {
        case (nil, nil): return .same
        case (nil, _):   return .onlyRight
        case (_, nil):   return .onlyLeft
        default:         return (left == right) ? .same : .different
        }
    }
    
    private func matchesSearch(_ name: String) -> Bool {
        let raw = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return true }

        let tokens = raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        // Gather haystack: name + category + left values + all right values
        let cat = category(for: name)
        let leftVals = (leftDB[name] ?? []).joined(separator: " ")
        let rightValsJoined = rightConns.indices.compactMap { idx in
            rightDBs[safe: idx]?[name]?.joined(separator: " ")
        }.joined(separator: " ")

        let haystack = [name, cat, leftVals, rightValsJoined]
            .joined(separator: " ")
            .lowercased()

        // AND semantics like your other view
        return tokens.allSatisfy { haystack.contains($0) }
    }

    // MARK: Load & refresh

    private func initialLoad() async {
        leftConn = try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == payload.leftConnectionID })
        ).first

        rightConns = (try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { payload.rightConnectionIDs.contains($0.id) })
        )) ?? []

        leftDB  = snapshotFromDB(connID: payload.leftConnectionID, names: payload.preferenceNames)
        rightDBs = rightConns.map { snapshotFromDB(connID: $0.id, names: payload.preferenceNames) }
        
        // Seed header timestamps from DB
        if let leftID = leftConn?.id {
            connSnapshotTS[leftID] = computeSnapshotTime(for: leftID)
        }
        for c in rightConns {
            connSnapshotTS[c.id] = computeSnapshotTime(for: c.id)
        }
        // Freshness flags
        leftIsFresh = false
        rightIsFresh = Array(repeating: false, count: rightConns.count)
        leftIsUpdating = false
        rightIsUpdating = Array(repeating: false, count: rightConns.count)
    }

    private func snapshotFromDB(connID: UUID, names: [String]) -> [String:[String]] {
        let nameSet = Set(names)
        let d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == connID && nameSet.contains($0.name) }
        )
        let list = (try? context.fetch(d)) ?? []
        var map: [String:[String]] = [:]
        for p in list { map[p.name] = p.values ?? [] }
        return map
    }
    
    private func readableUpdateError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("login") || msg.contains("auth") || msg.contains("unauthoriz") {
            return "Login failed"
        }
        return "Fetch data failed"
    }
    
    // MARK: - Snapshot timestamps (from STORAGE)

    private func snapshotTime(for connID: UUID, names: [String]) -> Date? {
        let nameSet = Set(names)
        let d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == connID && nameSet.contains($0.name) }
        )
        if let prefs = try? context.fetch(d), !prefs.isEmpty {
            // prefer per-pref lastImportedAt (max); fall back to connection's import time
            let maxPref = prefs.map(\.lastImportedAt).max()
            return maxPref
        }
        // Fallback to connection aggregate field if you keep it
        if let c = try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == connID })
        ).first {
            return c.lastImportCompletedAt
        }
        return nil
    }
    
    // Compute latest snapshot time for given connection (from DB)
    private func computeSnapshotTime(for connID: UUID) -> Date? {
        let nameSet = Set(payload.preferenceNames)
        let d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == connID && nameSet.contains($0.name) }
        )
        if let prefs = try? context.fetch(d), !prefs.isEmpty {
            return prefs.map(\.lastImportedAt).max()
        }
        if let c = try? context.fetch(FetchDescriptor<TCConnection>(
            predicate: #Predicate { $0.id == connID })
        ).first {
            return c.lastImportCompletedAt
        }
        return nil
    }

    // Read from cache, fallback to compute-once and store
    private func snapshotTimeCached(for connID: UUID) -> Date? {
        if let ts = connSnapshotTS[connID] { return ts }
        let ts = computeSnapshotTime(for: connID)
        if let ts { connSnapshotTS[connID] = ts }
        return ts
    }

    // Friendly string
    private func tsString(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return d.formatted(date: .numeric, time: .shortened)
    }

    private func tsString(for date: Date?) -> String {
        guard let d = date else { return "—" }
        return d.formatted(date: .numeric, time: .shortened)
    }
    
    /// Import ALL prefs from Teamcenter for a connection, then rebuild the in-memory snapshot for the names in payload.
    @MainActor
    private func importAndResnapshot(conn: TCConnection) async throws -> [String:[String]] {
        _ = try await PreferencesImporter.importAll(
            context: context,
            connection: conn,
            baseUrl: conn.url,
            batchSize: 2_000
        )
        return snapshotFromDB(connID: conn.id, names: payload.preferenceNames)
    }
    
    private func refreshLeft() async {
        guard let l = leftConn else { return }
        await MainActor.run {
            isRefreshingLeft = true
            leftIsUpdating   = true
            leftUpdateError  = nil
        }
        do {
            let snap = try await importAndResnapshot(conn: l)
            await MainActor.run {
                leftDB = snap
                leftIsFresh = true
                connSnapshotTS[l.id] = computeSnapshotTime(for: l.id) ?? Date()
                leftUpdateError = nil
            }
        } catch {
            print("Update Left failed:", error)
            await MainActor.run {
                leftUpdateError = readableUpdateError(error)
                leftIsFresh = false
            }
        }
        await MainActor.run {
            leftIsUpdating   = false
            isRefreshingLeft = false
        }
    }

    private func refreshAllRights() async {
        guard !rightConns.isEmpty else { return }
        await MainActor.run {
            isRefreshingAllRights = true
            rightIsUpdating = Array(repeating: true, count: rightConns.count)
            for c in rightConns { rightUpdateErrors[c.id] = nil }
        }
        for (idx, conn) in rightConns.enumerated() {
            do {
                let snap = try await importAndResnapshot(conn: conn)
                await MainActor.run {
                    if idx < rightDBs.count { rightDBs[idx] = snap } else { rightDBs.append(snap) }
                    rightIsFresh[idx] = true
                    connSnapshotTS[conn.id] = computeSnapshotTime(for: conn.id) ?? Date()
                    rightUpdateErrors[conn.id] = nil
                }
            } catch {
                print("Update Right[\(idx)] failed:", error)
                await MainActor.run {
                    rightIsFresh[idx] = false
                    rightUpdateErrors[conn.id] = readableUpdateError(error)
                }
            }
        }
        await MainActor.run {
            rightIsUpdating = Array(repeating: false, count: rightConns.count)
            isRefreshingAllRights = false
        }
    }
    
    private func fetchMap(from baseUrl: String, names: [String]) async -> [String:[String]] {
        guard let list = await TeamcenterAPIService.shared.getPreferences(
            tcEndpointUrl: APIConfig.tcGetPreferencesUrl(tcUrl: baseUrl),
            preferenceNames: names,
            includeDescriptions: true
        ) else { return [:] }

        var map: [String:[String]] = [:]
        for e in list { map[e.definition.name] = e.values?.values ?? [] }
        return map
    }

    private func refreshActiveRight() async {
        guard !rightConns.isEmpty, rightConns.indices.contains(activeRightIndex) else { return }
        isRefreshingActiveRight = true
        let r = rightConns[activeRightIndex]
        rightDBs[activeRightIndex] = await fetchMap(from: r.url, names: payload.preferenceNames)
        isRefreshingActiveRight = false
    }
    
    private func columnHelp(_ name: String, isFresh: Bool, ts: Date?) -> String {
        let when = tsString(for: ts)
        return isFresh
            ? "\(name)\nUpdated from Teamcenter just now.\nSnapshot: \(when)"
            : "\(name)\nUsing stored snapshot.\nSnapshot: \(when)"
    }

}

