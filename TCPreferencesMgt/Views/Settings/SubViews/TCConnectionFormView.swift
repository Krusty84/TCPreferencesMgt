//
//  TCConnectionFieldsView.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 13/08/2025.
//

import SwiftUI
import Combine

struct ConnectionFormView<RightTop: View, Footer: View>: View {
    let title: String
    let connBind: ConnectionBindings
    @ViewBuilder var rightTop: () -> RightTop
    @ViewBuilder var footer: () -> Footer

    private let labelWidth: CGFloat = 80   // label width

    // Проверка валидности URL
    private var isValidTCURL: Bool {
        let pattern = #"^https?://(?:(?:\d{1,3}\.){3}\d{1,3}|(?:[A-Za-z0-9]+\.)*[A-Za-z0-9]+):\d{1,5}/[A-Za-z0-9]+$"#
        return connBind.url.wrappedValue.range(of: pattern, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
                .padding(.bottom, 4)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name").frame(width: labelWidth, alignment: .trailing)
                    TextField("", text: connBind.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("TC URL").frame(width: labelWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                            TextField("http(s)://ip-or-name-tc-webtier:port/webtier-name-typically tc", text: connBind.url)
                                .textFieldStyle(.roundedBorder)
                                .onReceive(Just(connBind.url.wrappedValue)) { newValue in
                                    let filtered = newValue.unicodeScalars.filter { allowedUrlCharacters.contains($0) }
                                    let clean = String(filtered)
                                    if clean != newValue {
                                        connBind.url.wrappedValue = clean
                                    }
                                }
                            if !connBind.url.wrappedValue.isEmpty && !isValidTCURL {
                                Text("⚠️ Must be http://…:port/… or https://…:port/…")
                                    .font(.footnote)
                                    .foregroundColor(.red)
                            }
                        }
                }
                GridRow {
                    Text("Description").frame(width: labelWidth, alignment: .trailing)
                    TextField("", text: connBind.desc)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Username").frame(width: labelWidth, alignment: .trailing)
                    HStack(spacing: 10) {
                        TextField("", text: connBind.username)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                        SecureField("", text: connBind.password)
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

/// A small helper to pass a group of bindings
struct ConnectionBindings {
    var name: Binding<String>
    var url: Binding<String>
    var desc: Binding<String>
    var username: Binding<String>
    var password: Binding<String>
}

let allowedUrlCharacters = CharacterSet(charactersIn:
    "abcdefghijklmnopqrstuvwxyz" +
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
    "0123456789" +
    "-._~:/?#[]@!$&'()*+,;=%"
)
