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

    // Use UUID for selection (Hashable)
    @State private var selectionID: UUID? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("Exists Teamcenter Connections")
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
                                    Text(conn.name.isEmpty ? "(No name)" : conn.name)
                                        .font(.headline)
                                    Text(conn.url)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(conn.desc).foregroundStyle(.secondary)
                            }
                            .tag(conn.id) // tag with UUID for List(selection:)
                            .contentShape(Rectangle()) // make the whole row clickable
                            .onTapGesture {            // single click selects
                                selectionID = conn.id
                            }
                            .onTapGesture(count: 2) {  // double-click opens
                                open(conn.id)
                            }
                            // Optional: subtle selected background
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
                    if let id = selectionID { open(id) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectionID == nil)            // <-- enable only when selected
            }
        }
        .padding(16)
    }

    private func open(_ id: UUID) {
        openWindow(id: "connection", value: id)          // <-- pass UUID value
        dismiss()
    }
}
