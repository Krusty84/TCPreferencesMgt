//
//  TCPreference.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import SwiftData
import Foundation

@Model
final class TCPreference {
    // Identity
    @Attribute(.unique) var key: String
    var connection: TCConnection?
    var connectionID: UUID

    // Definition (current snapshot)
    var name: String
    var category: String
    var prefDescription: String
    var type: Int
    var isArray: Bool
    var isDisabled: Bool
    var protectionScope: String
    var isEnvEnabled: Bool
    var isOOTBPreference: Bool

    // Values (current snapshot)
    var valueOrigination: String?
    var values: [String]?

    // User note
    var comment: String?

    // Timestamps for current snapshot
    var firstSeenAt: Date          // when we first imported this pref
    var lastImportedAt: Date       // when we last refreshed it from Teamcenter
    var lastChangedAt: Date?        // when values/definition last changed
    var lastSeenAt: Date? // set to current run's completion time

    // Quick change detection
    var fingerprint: String? = nil        // hash of relevant fields to detect changes

    // Full history (append-only)
    @Relationship(deleteRule: .cascade, inverse: \TCPreferenceRevision.preference)
    var revisions: [TCPreferenceRevision] = []
    
    // User preference collection
    @Relationship(inverse: \TCPreferenceJoinTCPreferenceCollection.preference)
    var prefCollections: [TCPreferenceJoinTCPreferenceCollection] = []

    init(
        key: String,
        connection: TCConnection?,
        connectionID: UUID,
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
        comment: String? = nil,
        firstSeenAt: Date = Date(),
        lastImportedAt: Date = Date(),
        lastChangedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        fingerprint: String? = nil
    ) {
        self.key = key
        self.connection = connection
        self.connectionID = connectionID
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
        self.comment = comment
        self.firstSeenAt = firstSeenAt
        self.lastImportedAt = lastImportedAt
        self.lastChangedAt = lastChangedAt
        self.lastSeenAt = lastSeenAt
        self.fingerprint = fingerprint
    }
}
