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

    @State private var confirmDeleteConnection = false
    @State private var confirmDeletePrefs = false
    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private var verifyReady: Bool {
        !connection.url.isEmpty && !connection.username.isEmpty && !connection.password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name + URL
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit Connection").font(.headline)
                TextField("Name", text: $connection.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("TC URL", text: $connection.url)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Description", text: $connection.desc)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            // Username + Password + Status + Verify
            HStack(spacing: 10) {
                TextField("Username", text: $connection.username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 140)
                SecureField("Password", text: $connection.password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 140)
                tcStatusIndicator
                Button("Verify") { Task {await vm.tcLogin(tcBaseUrl: connection.url, username: connection.username, password: connection.password)} }
                    .frame(minWidth: 70)
                Spacer()
            }

            // Buttons
            HStack(spacing: 10) {
                Button("Import Preferences") { importPreferences() }
                Button(role: .destructive) { confirmDeletePrefs = true } label: {
                    Text("Delete Preferences")
                }
                Spacer()
                Button("Save Changes") { try? context.save() }
                                   .keyboardShortcut(.defaultAction)
                                   .disabled(connection.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                                             connection.url.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(role: .destructive) { confirmDeleteConnection = true } label: {
                    Text("Delete Connection")
                }
            }
            .padding(.top, 6)
        }
        // dialogs and alerts stay unchanged
        .confirmationDialog("Delete all preferences for this connection?",
                            isPresented: $confirmDeletePrefs,
                            titleVisibility: .visible) {
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this connection?",
                            isPresented: $confirmDeleteConnection,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(connection)
                try? context.save()
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
                alertMessage = "Imported \(imported) preferences."
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
        case 401: return "Unauthorized"
        default:  return "HTTP \(code)"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
