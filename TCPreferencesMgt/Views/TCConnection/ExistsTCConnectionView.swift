//
//  ConnectionView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI
import SwiftData

struct ExistsTCConnectionView: View {
    @Query(sort: \TCConnection.name, order: .forward) private var connections: [TCConnection]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    // Use UUID because TCConnection has `id: UUID`
    @State private var selection: Set<UUID> = []

    // Exactly one selected
    private var selectedOne: TCConnection? {
        guard selection.count == 1, let uid = selection.first else { return nil }
        return connections.first { $0.id == uid }
    }

    // Keep current list order for left→right
    private var orderedSelectedConnections: [TCConnection] {
        connections.filter { selection.contains($0.id) }
    }

    private var canOpenSingle: Bool {
        guard let c = selectedOne else { return false }
        return !c.preferences.isEmpty
    }

    private var canCompare: Bool {
        let ordered = orderedSelectedConnections
        return ordered.count >= 2 && !ordered.first!.preferences.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Existing connections to Teamcenter")
                .font(.title2)

            Group {
                if connections.isEmpty {
                    VStack(spacing: 12) {
                        Text("No connections yet").font(.title2)
                        Text("Use Settings to add connections.\nUse File → Open… to choose one.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 520, minHeight: 320)
                } else {
                    List(selection: $selection) {
                        ForEach(connections) { conn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(conn.name.isEmpty ? "(No name)" : conn.name)
                                            .font(.headline)
                                        if !conn.desc.isEmpty {
                                            Text("(\(conn.desc))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(conn.url)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if conn.preferences.isEmpty {
                                    Text("No preferences (Import before open)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(conn.preferences.count) preferences")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(conn.id) // TAG WITH UUID (matches selection type)
                            .onTapGesture(count: 2) {
                                if canOpenSingle, let one = selectedOne {
                                    openSingle(one.id)
                                } else if canCompare {
                                    openCompare()
                                }
                            }
                            .contextMenu {
                                Button("Open") {
                                    if canOpenSingle, let one = selectedOne {
                                        openSingle(one.id)
                                    }
                                }.disabled(!canOpenSingle)

                                Button("Compare…") {
                                    if canCompare { openCompare() }
                                }.disabled(!canCompare)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .frame(minWidth: 520, minHeight: 320)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }

                Button("Compare…") { openCompare() }
                    .disabled(!canCompare)
                    .help(canCompare ? "Compare selected connections"
                                     : "Select at least two connections; the first must have preferences")

                Button("Open") {
                    if canOpenSingle, let one = selectedOne { openSingle(one.id) }
                }
                .disabled(!canOpenSingle)
                .help(canOpenSingle ? "Open Preferences browser"
                                    : "Select a single connection with preferences")
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func openSingle(_ id: UUID) {
        openWindow(id: "connection", value: id)
        dismiss()
    }

    private func openCompare() {
        let ordered = orderedSelectedConnections
        guard ordered.count >= 2 else { return }
        let left = ordered[0]
        let rights = Array(ordered.dropFirst())

        let names = left.preferences.map(\.name)
            .sorted { $0.localizedCompare($1) == .orderedAscending }

        let payload = CompareLaunchPayload(
            leftConnectionID: left.id,
            rightConnectionIDs: rights.map(\.id),
            preferenceNames: names
        )
        openWindow(id: "compare", value: payload)
        dismiss()
    }
}
