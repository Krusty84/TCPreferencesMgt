//
//  TCConnection.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import Foundation
import SwiftData

@Model
final class TCConnection {
    @Attribute(.unique) var id: UUID
    var name: String
    var url: String
    var desc: String
    var username: String
    var password: String
    
    // Audit
    var lastImportStartedAt: Date?
    var lastImportCompletedAt: Date?

    // Relationship: a connection owns preferences
    @Relationship(deleteRule: .cascade, inverse: \TCPreference.connection)
    var preferences: [TCPreference] = []

    // Relationship: a connection owns collections
    @Relationship(deleteRule: .cascade, inverse: \TCPreferenceCollection.connection)
    var collections: [TCPreferenceCollection] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        url: String = "",
        desc: String = "",
        username: String = "",
        password: String = ""
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.desc = desc
        self.username = username
        self.password = password
        
    }
}
