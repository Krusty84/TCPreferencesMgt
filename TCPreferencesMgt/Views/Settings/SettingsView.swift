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
    
    // Tabs: 0 = General, 1 = Teamcenter
    @State private var selectedTab: Int = 0
    
    @StateObject private var vm = SettingsViewModel()
    
    // Resolve live model from ID
    private var selection: TCConnection? {
        guard let id = selectedID else { return nil }
        return connections.first(where: { $0.id == id })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Segmented tabs
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Teamcenter").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            Divider().padding(.top, 12)
            
            // Content by tab
            Group {
                switch selectedTab {
                    case 0: generalSettingsTab
                    case 1: teamcenterTab
                    default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: connections) { _, conns in
            if let id = selectedID, conns.first(where: { $0.id == id }) == nil {
                selectedID = nil
                draft = DraftConnection()
            }
        }
    }
    
    // MARK: - Tab: General
    private var generalSettingsTab: some View {
        // Use Form for native settings look
        ScrollView {
            VStack(spacing: 10) {
                Section {
                    HStack(spacing: 20) {
                        Toggle("Application Logging", isOn: $vm.appLoggingEnabled)
                            .toggleStyle(.switch)
                            .help("Enable/disable application logging")
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                } header: {
                    // If you already have SectionHeader in your project, this will work.
                    // If not, replace with: Text("Application Preferences")
                    SectionHeader(title: "Application Preferences",
                                  systemImage: "gearshape.fill",
                                  isExpanded: true)
                }
            }
            .padding(20)
        }
        
        
    }
    
    // MARK: - Tab: Teamcenter (your existing UI)
    private var teamcenterTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connections").font(.title2)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            
            HStack(alignment: .top, spacing: 0) {
                leftSide
                    .frame(width: 260, alignment: .topLeading)
                Divider()
                rightSide
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
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
                    .tag(conn.id)
                }
                .onDelete(perform: deleteConnections)
            }
            .frame(width: 240, height: 320)
            .listStyle(.inset)
            
            // BUTTONS
            HStack(spacing: 8) {
                Button {
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
                    onDeleted: { selectedID = nil }
                )
            } else {
                ConnectionFormView(
                    title: "New Connection",
                    connBind: .init(
                        name: $draft.name,
                        url: $draft.url,
                        desc: $draft.desc,
                        username: $draft.username,
                        password: $draft.password
                    ),
                    rightTop: { EmptyView() },
                    footer: { isValidTCURL in
                        Spacer()
                        Button("Add") { addConnection() }
                            .disabled(draft.name.trimmed.isEmpty ||
                                      draft.url.trimmed.isEmpty ||
                                      !isValidTCURL)
                    }
                )
                .padding(.leading, 8) // small left gap for nicer look
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

// Custom SectionHeader view that shows disclosure indicator
struct SectionHeader: View {
    let title: String
    let systemImage: String
    var isExpanded: Bool
    
    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
    }
}
