//
//  DynamicTable.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 30/08/2025.
//

import SwiftUICore

// 1) PreferenceKeys
// was: private struct NameWidthKey ...
struct NameWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// was: private struct CategoryWidthKey ...
struct CategoryWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// 2) Measuring helpers
// was: private extension View { ... }
extension View {
    func measureNameWidth(_ assign: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: NameWidthKey.self, value: g.size.width)
            }
        )
        .onPreferenceChange(NameWidthKey.self, perform: assign)
    }

    func measureCategoryWidth(_ assign: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: CategoryWidthKey.self, value: g.size.width)
            }
        )
        .onPreferenceChange(CategoryWidthKey.self, perform: assign)
    }
}
