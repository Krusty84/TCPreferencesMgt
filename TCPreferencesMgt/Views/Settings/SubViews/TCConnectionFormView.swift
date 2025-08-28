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

struct ConnectionFormView<RightTop: View, Footer: View>: View {
    let title: String
    let b: ConnectionBindings
    @ViewBuilder var rightTop: () -> RightTop
    @ViewBuilder var footer: () -> Footer

    private let labelWidth: CGFloat = 80   // label width

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
                .padding(.bottom, 4)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name").frame(width: labelWidth, alignment: .trailing)
                    TextField("", text: b.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("TC URL").frame(width: labelWidth, alignment: .trailing)
                    TextField("", text: b.url)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Description").frame(width: labelWidth, alignment: .trailing)
                    TextField("", text: b.desc)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Username").frame(width: labelWidth, alignment: .trailing)
                    HStack(spacing: 10) {
                        TextField("", text: b.username)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                        SecureField("", text: b.password)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                        rightTop()
                        Spacer(minLength: 0)
                    }
                }
            }

            HStack(spacing: 10) {
                footer()
            }
            .padding(.top, 6)
        }
        .padding(.leading, 16) // small left gap for breathing room
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
