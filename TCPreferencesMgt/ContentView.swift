//
//  ContentView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: TCPreferencesMgtDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(TCPreferencesMgtDocument()))
}
