//
//  CompareWindowView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 23/08/2025.
//

import SwiftUI
import SwiftData
import TCSwiftBridge

struct CompareWindowView: View {
    let payload: CompareLaunchPayload
    @Environment(\.modelContext) private var context
    let tcApi = TeamcenterAPIService.shared
    // connections
    @State private var leftConn: TCConnection?
    @State private var rightConns: [TCConnection] = []
    @State private var activeRightIndex: Int = 0

    // cached DB values: name -> values
    @State private var leftDB:  [String:[String]] = [:]
    @State private var rightDBs: [[String:[String]]] = [] // parallel to rightConns

    // live in-memory rows for the ACTIVE right
    @State private var rows: [Row] = []

    // refresh UI state
    @State private var isRefreshingLeft = false
    @State private var isRefreshingAllRights = false
    @State private var isRefreshingActiveRight = false
    @State private var showOnlyDiffs = true

    private let api = TeamcenterAPIService.shared

    struct Row: Identifiable {
        var id: String { name }
        let name: String
        let category: String
        var leftValues: [String]?
        var rightValues: [String]?
        var status: Status

        enum Status { case same, different, onlyLeft, onlyRight }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            table
            footer
        }
        .padding(12)
        .frame(minWidth: 1000, minHeight: 560)
        .task { await initialLoad() }
        .onChange(of: activeRightIndex) { _ in rebuildRowsForActiveRight() }
    }

    // MARK: UI

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Preferences").font(.title3).bold()
                if let l = leftConn {
                    Text("Left: \(l.name.isEmpty ? l.url : l.name)")
                }
                if !rightConns.isEmpty {
                    HStack(spacing: 8) {
                        Text("Right:")
                        Picker("", selection: $activeRightIndex) {
                            ForEach(rightConns.indices, id: \.self) { idx in
                                let c = rightConns[idx]
                                Text(c.name.isEmpty ? c.url : c.name).tag(idx)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 520)
                    }
                }
            }

            Spacer()

            Toggle("Show only differences", isOn: $showOnlyDiffs)
                .toggleStyle(.switch)

            Divider().frame(height: 24)

            Button {
                Task { await refreshLeft() }
            } label: {
                HStack {
                    if isRefreshingLeft { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (Left)")
                }
            }
            .disabled(isRefreshingLeft || leftConn == nil)

            Button {
                Task { await refreshActiveRight() }
            } label: {
                HStack {
                    if isRefreshingActiveRight { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (Right)")
                }
            }
            .disabled(isRefreshingActiveRight || rightConns.isEmpty)

            Button {
                Task { await refreshAllRights() }
            } label: {
                HStack {
                    if isRefreshingAllRights { ProgressView().controlSize(.small) }
                    Text("Fetch Fresh (All Rights)")
                }
            }
            .disabled(isRefreshingAllRights || rightConns.isEmpty)
        }
    }

    private var table: some View {
        let data = showOnlyDiffs ? rows.filter { $0.status != .same } : rows
        return Table(data) {
            TableColumn("Name")      { r in Text(r.name).textSelection(.enabled) }.width(min: 260)
            TableColumn("Category")  { r in Text(r.category).foregroundStyle(.secondary) }.width(min: 160)
            TableColumn("Left Values")  { r in Text(joinVals(r.leftValues)).textSelection(.enabled) }
            TableColumn("Right Values") { r in Text(joinVals(r.rightValues)).textSelection(.enabled) }
            TableColumn("Status")    { r in statusBadge(r.status) }.width(120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Total: \(rows.count) • Differences: \(rows.filter { $0.status != .same }.count)")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { NSApplication.shared.keyWindow?.close() }
        }
    }

    private func statusBadge(_ s: Row.Status) -> some View {
        switch s {
        case .same:       return Label("Same", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .different:  return Label("Different", systemImage: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
        case .onlyLeft:   return Label("Only Left", systemImage: "arrow.left.circle.fill").foregroundStyle(.blue)
        case .onlyRight:  return Label("Only Right", systemImage: "arrow.right.circle.fill").foregroundStyle(.purple)
        }
    }

    // MARK: Load + Refresh

    private func initialLoad() async {
        // Load connections
        leftConn = try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == payload.leftConnectionID })
        ).first

        rightConns = (try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { payload.rightConnectionIDs.contains($0.id) })
        )) ?? []

        // DB snapshot for left
        leftDB = snapshotFromDB(connID: payload.leftConnectionID, names: payload.preferenceNames)

        // DB snapshots for each right (parallel array to rightConns)
        rightDBs = rightConns.map { snapshotFromDB(connID: $0.id, names: payload.preferenceNames) }

        rebuildRowsForActiveRight()
    }

    private func snapshotFromDB(connID: UUID, names: [String]) -> [String:[String]] {
        let nameSet = Set(names)
        let d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == connID && nameSet.contains($0.name) }
        )
        let list = (try? context.fetch(d)) ?? []
        var map: [String:[String]] = [:]
        for p in list {
            map[p.name] = p.values ?? []
        }
        return map
    }

    private func rebuildRowsForActiveRight() {
        let names = Array(Set(payload.preferenceNames))
            .sorted { $0.localizedCompare($1) == .orderedAscending }
        let rightMap = (activeRightIndex < rightDBs.count) ? rightDBs[activeRightIndex] : [:]

        func category(for name: String) -> String {
            let nameConst = name

            do {
                // Try LEFT connection first
                let leftID = payload.leftConnectionID
                var d = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == leftID && $0.name == nameConst }
                )
                d.fetchLimit = 1
                if let p = try context.fetch(d).first { return p.category }

                // Fallback: scan RIGHT connections
                for rc in rightConns {
                    let cid = rc.id
                    var d2 = FetchDescriptor<TCPreference>(
                        predicate: #Predicate { $0.connectionID == cid && $0.name == nameConst }
                    )
                    d2.fetchLimit = 1
                    if let p2 = try context.fetch(d2).first { return p2.category }
                }
            } catch {
                // silently ignore; return empty
            }
            return ""
        }

        rows = names.map { n in
            let lvals = leftDB[n]
            let rvals = rightMap[n]
            return Row(
                name: n,
                category: category(for: n),
                leftValues: lvals,
                rightValues: rvals,
                status: decideStatus(left: lvals, right: rvals)
            )
        }
    }

    private func decideStatus(left: [String]?, right: [String]?) -> Row.Status {
        switch (left, right) {
        case (nil, nil): return .same
        case (nil, _):   return .onlyRight
        case (_, nil):   return .onlyLeft
        default:
            return (left == right) ? .same : .different
        }
    }

    private func joinVals(_ v: [String]?) -> String {
        guard let v, !v.isEmpty else { return "—" }
        return v.joined(separator: ", ")
    }

    // --- Fresh fetchers (do not persist; only update view) ---

    private func fetchMap(from baseUrl: String, names: [String]) async -> [String:[String]] {
        guard let list = await tcApi.getPreferences(tcEndpointUrl: APIConfig.tcGetPreferencesUrl(tcUrl: baseUrl),
                                                  preferenceNames: names,
                                                  includeDescriptions: true)
        else { return [:] }
        var map: [String:[String]] = [:]
        for e in list {
            map[e.definition.name] = e.values?.values ?? []
        }
        return map
    }

    private func refreshLeft() async {
        guard let l = leftConn else { return }
        isRefreshingLeft = true
        let fresh = await fetchMap(from: l.url, names: payload.preferenceNames)
        leftDB = fresh
        // Rebuild rows for the active right
        rebuildRowsForActiveRight()
        isRefreshingLeft = false
    }

    private func refreshActiveRight() async {
        guard !rightConns.isEmpty else { return }
        let r = rightConns[activeRightIndex]
        isRefreshingActiveRight = true
        let fresh = await fetchMap(from: r.url, names: payload.preferenceNames)
        if activeRightIndex < rightDBs.count {
            rightDBs[activeRightIndex] = fresh
        }
        rebuildRowsForActiveRight()
        isRefreshingActiveRight = false
    }

    private func refreshAllRights() async {
        guard !rightConns.isEmpty else { return }
        isRefreshingAllRights = true
        // fetch sequentially (safe); you can parallelize if you like
        for (idx, conn) in rightConns.enumerated() {
            let fresh = await fetchMap(from: conn.url, names: payload.preferenceNames)
            if idx < rightDBs.count {
                rightDBs[idx] = fresh
            }
        }
        rebuildRowsForActiveRight()
        isRefreshingAllRights = false
    }
}
