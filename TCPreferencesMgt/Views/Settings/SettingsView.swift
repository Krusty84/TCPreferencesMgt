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
    @State private var selectedID: UUID? = nil
    @State private var showDeleteConfirm = false
    
    // Resolve live model from ID
    private var selection: TCConnection? {
        guard let id = selectedID else { return nil }
        return connections.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Teamcenter Connections").font(.title2)

            HStack(alignment: .top, spacing: 0) {
                leftSide
                    .frame(width: 260, alignment: .topLeading)
                Divider()
                rightSide
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    //.padding(.leading, 8)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 380)
        // If selected model disappears after delete, clear selection and reset draft
        .onChange(of: connections) { _, conns in
            if let id = selectedID, conns.first(where: { $0.id == id }) == nil {
                selectedID = nil
                draft = DraftConnection()
            }
        }
    }

    // MARK: - Left
    private var leftSide: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LIST
            List(selection: $selectedID) {
                ForEach(connections) { conn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conn.name.isEmpty ? "(No name)" : conn.name)
                            .font(.headline)
                        Text(conn.url)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .tag(conn.id) // selection by UUID
                }
                .onDelete(perform: deleteConnections) // ⌫ key works too
            }
            .frame(width: 240, height: 320)
            .listStyle(.inset)

            // BUTTONS just under the list
            HStack(spacing: 8) {
                Button {
                    // Open blank form on right
                    selectedID = nil
                    draft = DraftConnection()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .help("Create a new connection")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .disabled(selection == nil)
                .help("Delete selected connection")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .confirmationDialog("Delete selected connection?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { confirmedRemoveSelected() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Right
    private var rightSide: some View {
        Group {
            if let conn = selection {
                TCConnectionEditorView(
                    connection: conn,
                    onDeleted: { selectedID = nil } // notify parent to clear selection
                )
              //  .frame(minWidth: 360, minHeight: 320, alignment: .topLeading)
            } else {
                ConnectionFormView(
                    title: "New Connection",
                    b: .init(
                        name: $draft.name,
                        url: $draft.url,
                        desc: $draft.desc,
                        username: $draft.username,
                        password: $draft.password
                    ),
                    rightTop: { EmptyView() },       // no status/verify for create
                    footer: {
                        Spacer()
                        Button("Add") { addConnection() }
                            .disabled(draft.name.trimmed.isEmpty || draft.url.trimmed.isEmpty)
                    }
                )
            }
        }
    }

    // MARK: - Actions
    private func addConnection() {
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
        selectedID = item.id
    }

    private func removeSelected() {
        guard let sel = selection else { return }
        context.delete(sel)
        try? context.save()
        selectedID = nil
    }

    private func deleteConnections(_ indexSet: IndexSet) {
        let toDelete = indexSet.map { connections[$0] }
        toDelete.forEach(context.delete)
        try? context.save()
        // selection will auto-clear via onChange if needed
    }
    
    private func confirmedRemoveSelected() {
        guard let sel = selection else { return }
        context.delete(sel)
        try? context.save()
        selectedID = nil
        draft = DraftConnection()
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

