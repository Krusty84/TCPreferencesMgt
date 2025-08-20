//
//  ConnectionWindowView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI
import SwiftData

struct TCConnectionWrapperView: View {
    let connectionID: UUID
    @Environment(\.modelContext) private var context

    @State private var connection: TCConnection?
    @State private var prefCount: Int = 0

    private var windowTitle: String {
           if let c = connection, !c.name.isEmpty {
               return "Preferences from: \(c.name)  (\(c.desc))"
           } else {
               return "Connection"
           }
       }
    
    var body: some View {
           VStack(alignment: .leading, spacing: 12) {
               if let _ = connection {
                   TCPreferencesBrowserView(connectionID: connectionID)
               } else {
                   VStack(spacing: 10) {
                       ProgressView()
                       Text("Loading connection…")
                           .foregroundStyle(.secondary)
                   }
                   .frame(minWidth: 520, minHeight: 320)
               }
           }
           .padding(16)
           .frame(minWidth: 800, minHeight: 520)
           .navigationTitle(windowTitle) //update window title
           .onAppear(perform: loadConnection)
       }

       private func loadConnection() {
           let idConst = connectionID
           let d = FetchDescriptor<TCConnection>(
               predicate: #Predicate { $0.id == idConst }
           )
           do {
               connection = try context.fetch(d).first
           } catch {
               print("Fetch connection error:", error)
           }
       }
   }
