//
//  CompareWindowViewModel.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 30/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import TCSwiftBridge

@MainActor
final class CompareWindowViewModel: ObservableObject {
    // Input
    let payload: CompareLaunchPayload

    // SwiftData context (injected)
    private(set) var context: ModelContext?

    // Connections
    @Published var primaryConnection: TCConnection?
    @Published var secondaryConnections: [TCConnection] = []
    @Published var activeSecondaryIndex: Int = 0

    // Per-connection snapshot timestamps
    @Published var connSnapshotTS: [UUID: Date] = [:]

    // Snapshots: name -> values
    @Published var primaryDB:  [String:[String]] = [:]
    @Published var secondaryDBs: [[String:[String]]] = []

    // Refresh/UI state
    @Published var isRefreshingPrimary = false
    @Published var isRefreshingAllSecondary = false
    @Published var isRefreshingActiveSecondary = false

    @Published var primaryIsFresh: Bool = false
    @Published var secondaryIsFresh: [Bool] = []

    // animated progress per column
    @Published var primaryIsUpdating: Bool = false
    @Published var secondaryIsUpdating: [Bool] = []

    // Errors
    @Published var lastError: String = ""
    @Published var primaryUpdateError: String? = nil
    @Published var secondaryUpdateErrors: [UUID: String] = [:]

    // MARK: - Lifecycle

    init(payload: CompareLaunchPayload) {
        self.payload = payload
    }

    func setContext(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
    }

    // MARK: - Public helpers for the View

    var isBusy: Bool {
        isRefreshingPrimary
        || isRefreshingAllSecondary
        || primaryIsUpdating
        || secondaryIsUpdating.contains(true)
    }

    var primaryTitle: String {
        guard let c = primaryConnection else { return "Primary" }
        return c.name.isEmpty ? c.url : c.name
    }

    func secondaryTitle(_ idx: Int) -> String {
        guard secondaryConnections.indices.contains(idx) else { return "Secondary \(idx+1)" }
        let c = secondaryConnections[idx]
        return c.name.isEmpty ? c.url : c.name
    }

    enum RowStatus { case same, different, onlyPrimary, onlySecondary }

    func decideStatus(primary: [String]?, secondary: [String]?) -> RowStatus {
        switch (primary, secondary) {
        case (nil, nil): return .same
        case (nil, _):   return .onlySecondary
        case (_, nil):   return .onlyPrimary
        default:         return (primary == secondary) ? .same : .different
        }
    }

    func rowHasAnyDiff(name: String) -> Bool {
        let p = primaryDB[name]
        for idx in secondaryConnections.indices {
            let s = secondaryDBs[safe: idx]?[name]
            if decideStatus(primary: p, secondary: s) != .same { return true }
        }
        return false
    }

    func category(for name: String) -> String {
        guard let context else { return "" }
        let n = name
        do {
            if let pid = primaryConnection?.id {
                var d = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == pid && $0.name == n }
                )
                d.fetchLimit = 1
                if let p = try context.fetch(d).first { return p.category }
            }
            for rc in secondaryConnections {
                let cid = rc.id
                var d2 = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.connectionID == cid && $0.name == n }
                )
                d2.fetchLimit = 1
                if let p2 = try context.fetch(d2).first { return p2.category }
            }
        } catch { }
        return ""
    }

    func matchesSearch(name: String, filter: String) -> Bool {
        let raw = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return true }

        let tokens = raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        let cat = category(for: name)
        let pVals = (primaryDB[name] ?? []).joined(separator: " ")
        let sValsJoined = secondaryConnections.indices.compactMap { idx in
            secondaryDBs[safe: idx]?[name]?.joined(separator: " ")
        }.joined(separator: " ")

        let haystack = [name, cat, pVals, sValsJoined]
            .joined(separator: " ")
            .lowercased()

        return tokens.allSatisfy { haystack.contains($0) }
    }

    func tsString(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return d.formatted(date: .numeric, time: .shortened)
    }

    func columnHelp(_ name: String, isFresh: Bool, ts: Date?) -> String {
        let when = tsString(ts)
        return isFresh
            ? "\(name)\nUpdated from Teamcenter just now.\nSnapshot: \(when)"
            : "\(name)\nUsing stored snapshot.\nSnapshot: \(when)"
    }

    // MARK: - Loading

    func initialLoad() async {
        guard let context else { return }

        primaryConnection = try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == payload.leftConnectionID })
        ).first

        secondaryConnections = (try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { payload.rightConnectionIDs.contains($0.id) })
        )) ?? []

        primaryDB   = snapshotFromDB(connID: payload.leftConnectionID, names: payload.preferenceNames)
        secondaryDBs = secondaryConnections.map { snapshotFromDB(connID: $0.id, names: payload.preferenceNames) }

        if let pid = primaryConnection?.id {
            connSnapshotTS[pid] = computeSnapshotTime(for: pid)
        }
        for c in secondaryConnections {
            connSnapshotTS[c.id] = computeSnapshotTime(for: c.id)
        }

        primaryIsFresh = false
        secondaryIsFresh = Array(repeating: false, count: secondaryConnections.count)
        primaryIsUpdating = false
        secondaryIsUpdating = Array(repeating: false, count: secondaryConnections.count)
    }

    // MARK: - Refresh

    func refreshPrimary() async {
        guard let p = primaryConnection else { return }
        isRefreshingPrimary = true
        primaryIsUpdating   = true
        primaryUpdateError  = nil
        do {
            let snap = try await importAndResnapshot(conn: p)
            primaryDB = snap
            primaryIsFresh = true
            connSnapshotTS[p.id] = computeSnapshotTime(for: p.id) ?? Date()
            primaryUpdateError = nil
        } catch {
            print("Update Primary failed:", error)
            primaryUpdateError = readableUpdateError(error)
            primaryIsFresh = false
        }
        primaryIsUpdating   = false
        isRefreshingPrimary = false
    }

    func refreshAllSecondary() async {
        guard !secondaryConnections.isEmpty else { return }
        isRefreshingAllSecondary = true
        secondaryIsUpdating = Array(repeating: true, count: secondaryConnections.count)
        for c in secondaryConnections { secondaryUpdateErrors[c.id] = nil }

        for (idx, conn) in secondaryConnections.enumerated() {
            do {
                let snap = try await importAndResnapshot(conn: conn)
                if idx < secondaryDBs.count { secondaryDBs[idx] = snap } else { secondaryDBs.append(snap) }
                secondaryIsFresh[idx] = true
                connSnapshotTS[conn.id] = computeSnapshotTime(for: conn.id) ?? Date()
                secondaryUpdateErrors[conn.id] = nil
            } catch {
                print("Update Secondary[\(idx)] failed:", error)
                secondaryIsFresh[idx] = false
                secondaryUpdateErrors[conn.id] = readableUpdateError(error)
            }
        }

        secondaryIsUpdating = Array(repeating: false, count: secondaryConnections.count)
        isRefreshingAllSecondary = false
    }

    func refreshActiveSecondary() async {
        guard !secondaryConnections.isEmpty,
              secondaryConnections.indices.contains(activeSecondaryIndex) else { return }
        isRefreshingActiveSecondary = true
        let sc = secondaryConnections[activeSecondaryIndex]
        secondaryDBs[activeSecondaryIndex] = await fetchMap(from: sc.url, names: payload.preferenceNames)
        isRefreshingActiveSecondary = false
    }

    // MARK: - Internals

    private func snapshotFromDB(connID: UUID, names: [String]) -> [String:[String]] {
        guard let context else { return [:] }
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

    private func computeSnapshotTime(for connID: UUID) -> Date? {
        guard let context else { return nil }
        let nameSet = Set(payload.preferenceNames)
        let d = FetchDescriptor<TCPreference>(
            predicate: #Predicate { $0.connectionID == connID && nameSet.contains($0.name) }
        )
        if let prefs = try? context.fetch(d), !prefs.isEmpty {
            return prefs.map(\.lastImportedAt).max()
        }
        if let c = try? context.fetch(
            FetchDescriptor<TCConnection>(predicate: #Predicate { $0.id == connID })
        ).first {
            return c.lastImportCompletedAt
        }
        return nil
    }

    private func importAndResnapshot(conn: TCConnection) async throws -> [String:[String]] {
        guard let context else { return [:] }
        _ = try await PreferencesImporter.importAll(
            context: context,
            connection: conn,
            baseUrl: conn.url,
            batchSize: 2_000
        )
        return snapshotFromDB(connID: conn.id, names: payload.preferenceNames)
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
}

// MARK: - Safe array subscript used by VM too
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
