//
//  TCPreferencesMgtApp.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI
import SwiftData

@main
struct TCPreferencesMgtApp: App {
    // SwiftData container
    var body: some Scene {
        // Main “document-style” window (empty for now; we open connection windows separately)
        WindowGroup {
            //StartView()
            ExistsTCConnectionView()
        }
        .modelContainer(for: TCConnection.self)
        .commands {
            // Replace standard File → Open… with our connection picker
            CommandGroup(replacing: .importExport) {
                OpenConnectionCommand()
            }
        }

        // Settings window (standard macOS Settings menu)
        Settings {
            SettingsView()
        }
        .modelContainer(for: TCConnection.self)

        // Window that lists saved connections to pick from (shown by File → Open…)
        WindowGroup("Open Connection", id: "openChooser") {
            ExistsTCConnectionView()
        }
        .modelContainer(for: TCConnection.self)

        // A window per opened connection
        WindowGroup("Connection", id: "connection", for: UUID.self) { $connectionID in
            if let id = connectionID {
                TCConnectionWrapperView(connectionID: id)
            } else {
                Text("No connection selected.").padding()
            }
        }
        .modelContainer(for: [TCConnection.self, TCPreference.self])
    }
}

// The menu item that triggers our chooser window
struct OpenConnectionCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open…", action: { openWindow(id: "openChooser") })
            .keyboardShortcut("o", modifiers: [.command])
    }
}
