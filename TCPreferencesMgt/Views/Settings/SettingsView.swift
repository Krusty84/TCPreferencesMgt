//
//  SettingsView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TCConnection.name, order: .forward) private var connections: [TCConnection]

    @State private var draft = DraftConnection()
    @State private var selection: TCConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teamcenter Connections").font(.title2)

            HStack(alignment: .top, spacing: 16) {
                // Left pane, list of connections
                List(selection: $selection) {
                    ForEach(connections) { conn in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conn.name.isEmpty ? "(No name)" : conn.name)
                                    .font(.headline)
                                Text(conn.url).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .tag(conn)
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(conn)
                                try? context.save()
                                if selection?.id == conn.id { selection = nil }
                            } label: { Text("Delete") }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.map { connections[$0] }.forEach(context.delete)
                        try? context.save()
                        if let sel = selection, !connections.contains(where: { $0.id == sel.id }) {
                            selection = nil
                        }
                    }
                }
                .frame(width: 200, height: 320)

                // Right pane
                if let conn = selection {
                    TCConnectionEditorView(connection: conn)
                        .frame(minWidth: 360, minHeight: 320, alignment: .topLeading)
                } else {
                    Form {
                        Section {
                            TCConnectionFieldsView(b: .init(
                                name: $draft.name,
                                url: $draft.url,
                                desc: $draft.desc,
                                username: $draft.username,
                                password: $draft.password
                            ))

                            HStack {
                                Spacer()
                                Button("Add") {
                                    let item = TCConnection(
                                        name: draft.name.trimmed,
                                        url: draft.url.trimmed,
                                        desc: draft.desc,
                                        username: draft.username.trimmed,
                                        password: draft.password
                                    )
                                    context.insert(item)
                                    try? context.save()
                                    draft = DraftConnection()
                                    selection = item
                                }
                                .disabled(draft.name.trimmed.isEmpty || draft.url.trimmed.isEmpty)
                            }
                        } header: { Text("New Connection").font(.headline) }
                    }
                    .frame(minWidth: 360, minHeight: 320, alignment: .topLeading)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 380)
    }
}

private struct DraftConnection {
    var name = ""
    var url = ""
    var desc = ""
    var username = ""
    var password = ""
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
