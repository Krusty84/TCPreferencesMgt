//
//  TCPreferencesMgtApp.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftUI

@main
struct TCPreferencesMgtApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TCPreferencesMgtDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
