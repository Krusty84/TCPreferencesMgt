//
//  TCConnectionEditor.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 13/08/2025.
//

import SwiftUI

struct TCConnectionEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var connection: TCConnection

    @StateObject private var vm = SettingsViewModel()
    
    var onDeleted: () -> Void = {}
    @State private var confirmDeleteConnection = false
    @State private var confirmDeletePrefs = false
    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private var verifyReady: Bool {
        !connection.url.isEmpty && !connection.username.isEmpty && !connection.password.isEmpty
    }

    var body: some View {
        ConnectionFormView(
            title: "Edit Connection",
            connBind: .init(
                name: $connection.name,
                url: $connection.url,
                desc: $connection.desc,
                username: $connection.username,
                password: $connection.password
            ),
            rightTop: {                      // status + Verify button
                HStack(spacing: 6) {
                    tcStatusIndicator
                    Button("Verify") {
                        Task { await vm.tcLogin(tcBaseUrl: connection.url,
                                                username: connection.username,
                                                password: connection.password) }
                    }
                    .help("Check Teamcenter connection")
                    .disabled(isBusy)
                    .frame(minWidth: 70)
                }
            },
            footer: { isValidTCURL in  // Save / Delete / Import Buttons
                HStack {
                    Spacer()   // pushes everything to the right

                    HStack(spacing: 10) {
                        Button {
                            importPreferences()
                        } label: {
                            if isBusy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Importing…")
                                }
                            } else {
                                Text("Initial Import")
                            }
                        }
                        .help("Initial import of Preferences")
                        .disabled(isBusy)

                        Button("Save Changes") { try? context.save() }
                            .keyboardShortcut(.defaultAction)
                            .help("Save changes")
                            .disabled(isBusy || connection.name.trimmed.isEmpty || connection.url.trimmed.isEmpty || !isValidTCURL)
                    }
                }
                .padding(.top, 6)
                
            }
        )
        // dialogs and alerts stay unchanged
        .confirmationDialog("Delete this connection?",
                            isPresented: $confirmDeleteConnection,
                            titleVisibility: .visible) {
            Button("OK", role: .destructive) {
                context.delete(connection)
                try? context.save()
                onDeleted()
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Info", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func importPreferences() {
        isBusy = true
        Task { @MainActor in
            do {
                let imported = try await PreferencesImporter.importAll(
                    context: context,
                    connection: connection,
                    baseUrl: connection.url,
                    batchSize: 2_000
                )
                alertMessage = "Preferences imported successfully"
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
            }
            isBusy = false
            showAlert = true
        }
    }

    // Status view
    private var tcStatusIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            if vm.isLoading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").font(.caption).foregroundColor(.gray)
                }
            } else if let code = vm.tcResponseCode {
                HStack(spacing: 4) {
                    Image(systemName: (200...299).contains(code) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor((200...299).contains(code) ? .green : .red)
                    Text(tcStatusMessage(for: code))
                        .font(.caption)
                        .foregroundColor((200...299).contains(code) ? .green : .red)
                }
            } else if let error = vm.tcErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.orange)
                }
            }
        }
    }

    private func tcStatusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Unauthorized"
        default:  return "HTTP \(code)"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
