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

    // Snapshots: name -> values
    @State private var leftDB:  [String:[String]] = [:]
    @State private var rightDBs: [[String:[String]]] = []

    // Refresh/UI state
    @State private var isRefreshingLeft = false
    @State private var isRefreshingAllRights = false
    @State private var isRefreshingActiveRight = false
    @State private var showOnlyDiffs = true

    // Column sizing
    @State private var nameColWidth: CGFloat = 260
    @State private var catColWidth:  CGFloat = 160
    private let valColWidth: CGFloat = 280
    private let indColWidth: CGFloat = 26
    private let rowHSpacing: CGFloat = 6
    private let edgeGutter: CGFloat = 6

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
        HStack(spacing: 12) {
            Text("Compare Preferences").font(.title3).bold()
            Spacer()
            Toggle("Show only differences", isOn: $showOnlyDiffs)
                .toggleStyle(.switch)

            Divider().frame(height: 22)

            Button {
                Task { await refreshLeft() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshingLeft { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (Left)")
                }
            }
            .buttonStyle(.bordered)

            Button {
                Task { await refreshActiveRight() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshingActiveRight { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (Right)")
                }
            }
            .buttonStyle(.bordered)
            .disabled(rightConns.isEmpty)

            Button {
                Task { await refreshAllRights() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshingAllRights { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (All Rights)")
                }
            }
            .buttonStyle(.bordered)
            .disabled(rightConns.isEmpty)
        }
        .padding(.horizontal, edgeGutter)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Table (sticky header + scroll rows)

    private var table: some View {
        let allNames = Array(Set(payload.preferenceNames)).sorted { $0.localizedCompare($1) == .orderedAscending }
        let shownNames = showOnlyDiffs ? allNames.filter { rowHasAnyDiff(name: $0) } : allNames

        return VStack(spacing: 0) {
            // ── HEADERS (split into 3 panes)
            HStack(spacing: 0) {
                // 1) Frozen: Name + Category
                HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
                    Text("Name").font(.headline)
                        .measureNameWidth { nameColWidth = max(nameColWidth, $0) }
                        .frame(width: nameColWidth, alignment: .leading)

                    Text("Category").font(.headline)
                        .measureCategoryWidth { catColWidth = max(catColWidth, $0) }
                        .frame(width: catColWidth, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.trailing, 8)
                .background(.thinMaterial)

                // 2) Frozen: Left connection column title
                Text(leftConnTitle).font(.headline)
                    .frame(width: valColWidth, alignment: .leading)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)

                // 3) Scrollable: rights + Δ
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .firstTextBaseline, spacing: rowHSpacing) {
                        ForEach(rightConns.indices, id: \.self) { idx in
                            Text(rightTitle(idx)).font(.headline)
                                .frame(width: valColWidth, alignment: .leading)
                            Text("Δ").font(.headline)
                                .frame(width: indColWidth, alignment: .center)
                                .help("Status vs Left")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(.thinMaterial)
            }

            Divider()

            // ── ROWS (shared vertical scroll; left/middle frozen, right scrollable)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shownNames.enumerated()), id: \.offset) { (rowIndex, n) in
                        HStack(spacing: 0) {
                            // 1) Frozen cells: Name + Category
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
                            }
                            .padding(.vertical, 6)
                            .padding(.trailing, 8)
                            .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))

                            // 2) Frozen cell: Left connection value
                            valueDiffCell(left: leftDB[n], right: nil)
                                .frame(width: valColWidth, alignment: .leading)
                                .padding(.vertical, 6)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.04))

                            // 3) Scrollable cells: each Right value + Δ
                            ScrollView(.horizontal, showsIndicators: false) {
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
                            }
                        }

                        Divider().opacity(0.15)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading) // left-aligned
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            // Legend
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Different").foregroundStyle(.secondary)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Same").foregroundStyle(.secondary)
            }

            Spacer()

            let total = Set(payload.preferenceNames).count
            let diffs = payload.preferenceNames.filter { rowHasAnyDiff(name: $0) }.count
            Text("Total: \(total) • Differences: \(diffs)")
                .foregroundStyle(.secondary)

            Button("Close") { NSApplication.shared.keyWindow?.close() }
        }
    }

    // MARK: Cells

    @ViewBuilder
    private func valueDiffCell(left: [String]?, right: [String]?) -> some View {
        let show = right ?? left
        let joined = (show?.isEmpty ?? true) ? "—" : show!.joined(separator: ", ")
        let isDifferent: Bool = { guard let r = right else { return false }; return decideStatus(left: left, right: r) != .same }()

        Text(joined)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDifferent ? Color.orange.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDifferent ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
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

    private func refreshLeft() async {
        guard let l = leftConn else { return }
        isRefreshingLeft = true
        leftDB = await fetchMap(from: l.url, names: payload.preferenceNames)
        isRefreshingLeft = false
    }

    private func refreshActiveRight() async {
        guard !rightConns.isEmpty, rightConns.indices.contains(activeRightIndex) else { return }
        isRefreshingActiveRight = true
        let r = rightConns[activeRightIndex]
        rightDBs[activeRightIndex] = await fetchMap(from: r.url, names: payload.preferenceNames)
        isRefreshingActiveRight = false
    }

    private func refreshAllRights() async {
        guard !rightConns.isEmpty else { return }
        isRefreshingAllRights = true
        for (idx, conn) in rightConns.enumerated() {
            rightDBs[idx] = await fetchMap(from: conn.url, names: payload.preferenceNames)
        }
        isRefreshingAllRights = false
    }
}
