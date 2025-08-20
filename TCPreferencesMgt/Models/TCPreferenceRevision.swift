//
//  TCPreferenceRevision.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 14/08/2025.
//

import SwiftData
import Foundation

@Model
final class TCPreferenceRevision {
    // Back link
    var preference: TCPreference?

    // When we captured this from Teamcenter
    var capturedAt: Date

    // Server data at that time
    var name: String
    var category: String
    var prefDescription: String
    var type: Int
    var isArray: Bool
    var isDisabled: Bool
    var protectionScope: String
    var isEnvEnabled: Bool
    var isOOTBPreference: Bool
    var valueOrigination: String?
    var values: [String]?

    // For quick comparisons
    var fingerprint: String

    init(
        preference: TCPreference?,
        capturedAt: Date = .now,
        name: String,
        category: String,
        prefDescription: String,
        type: Int,
        isArray: Bool,
        isDisabled: Bool,
        protectionScope: String,
        isEnvEnabled: Bool,
        isOOTBPreference: Bool,
        valueOrigination: String?,
        values: [String]?,
        fingerprint: String
    ) {
        self.preference = preference
        self.capturedAt = capturedAt
        self.name = name
        self.category = category
        self.prefDescription = prefDescription
        self.type = type
        self.isArray = isArray
        self.isDisabled = isDisabled
        self.protectionScope = protectionScope
        self.isEnvEnabled = isEnvEnabled
        self.isOOTBPreference = isOOTBPreference
        self.valueOrigination = valueOrigination
        self.values = values
        self.fingerprint = fingerprint
    }
}
