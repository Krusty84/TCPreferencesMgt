//
//  StartView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 13/08/2025.
//

import SwiftUI

struct StartView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("TCPreferencesMgt")
                .font(.largeTitle)
            Text("Use Settings to add connections.\nUse File → Open… to choose one.")
                .multilineTextAlignment(.center)
            Button("Open…") { openWindow(id: "openChooser") }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 240)
    }
}
