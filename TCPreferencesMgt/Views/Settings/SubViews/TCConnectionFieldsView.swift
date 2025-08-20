//
//  TCConnectionFieldsView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 13/08/2025.
//

import SwiftUI

/// A small helper to pass a group of bindings
struct ConnectionBindings {
    var name: Binding<String>
    var url: Binding<String>
    var desc: Binding<String>
    var username: Binding<String>
    var password: Binding<String>
}

struct TCConnectionFieldsView: View {
    let b: ConnectionBindings

    var body: some View {
        Group {
            TextField("", text: b.name, prompt: Text("Name"))
                .textFieldStyle(.roundedBorder)
            TextField("", text: b.url, prompt: Text("TC URL"))
                .textFieldStyle(.roundedBorder)
            TextField("", text: b.desc, prompt: Text("Description"))
                .textFieldStyle(.roundedBorder)
            TextField("", text: b.username, prompt: Text("Username"))
                .textFieldStyle(.roundedBorder)
            SecureField("", text: b.password, prompt: Text("Password"))
                .textFieldStyle(.roundedBorder)
        }
    }
}
