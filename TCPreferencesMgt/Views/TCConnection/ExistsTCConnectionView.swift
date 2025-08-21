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

    @State private var selectionID: UUID? = nil

    // Resolve selected connection from ID
    private var selectedConnection: TCConnection? {
        guard let id = selectionID else { return nil }
        return connections.first(where: { $0.id == id })
    }

    // Can we open? Only if a connection is selected AND it has preferences
    private var canOpen: Bool {
        guard let conn = selectedConnection else { return false }
        return !conn.preferences.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Existing connections to Teamcenter")
                .font(.title2)

            Group {
                if connections.isEmpty {
                    VStack(spacing: 12) {
                        Text("No connections yet")
                            .font(.title2)
                        Text("Use Settings to add connections.\nUse File → Open… to choose one.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 520, minHeight: 320)
                } else {
                    List(selection: $selectionID) {
                        ForEach(connections) { conn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(conn.name.isEmpty ? "(No name)" : conn.name)
                                            .font(.headline)
                                        if !conn.desc.isEmpty {
                                            Text("(\(conn.desc))")
                                                .font(.caption)               // tiny font
                                                .foregroundStyle(.secondary)  // subtle style
                                        }
                                    }
                                    Text(conn.url)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 2) {
                                    // Show how many preferences the connection has
                                    if conn.preferences.isEmpty {
                                        Text("No preferences (Import before open)")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(conn.preferences.count) preferences")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                    
                            }
                            .tag(conn.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectionID = conn.id
                            }
                            .onTapGesture(count: 2) {
                                // Only open if the connection has preferences
                                if !conn.preferences.isEmpty {
                                    open(conn.id)
                                }
                            }
                            .listRowBackground(
                                (selectionID == conn.id)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                            )
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .frame(minWidth: 520, minHeight: 320)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open") {
                    if let id = selectionID, canOpen { open(id) }
                }
                //.keyboardShortcut(.defaultAction)
                .disabled(!canOpen) // disable when none selected or no prefs
                .help(canOpen ? "Open Preferences browser" : "This connection has no preferences yet")
            }
        }
        .padding(16)
    }

    private func open(_ id: UUID) {
        openWindow(id: "connection", value: id)
        dismiss()
    }
}
