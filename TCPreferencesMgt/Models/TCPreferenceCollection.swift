//
//  TCPreferenceCollection.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 19/08/2025.
//


import SwiftData
import Foundation

//@Model
//final class TCPreferenceCollection {
//    // Unique per connection + name
//    @Attribute(.unique) var key: String
//    var name: String
//    var connectionID: UUID
//
//    // Inverse points to TCPreference.collections
//    @Relationship(inverse: \TCPreferenceJoinTCPreferenceCollection.collection)
//    var prefCollections: [TCPreferenceJoinTCPreferenceCollection] = []
//
//    init(name: String, connectionID: UUID) {
//        self.name = name
//        self.connectionID = connectionID
//        self.key = "\(connectionID.uuidString)|\(name.lowercased())"
//    }
//}


 @Model
 final class TCPreferenceCollection {
     @Attribute(.unique) var key: String
     var connection: TCConnection?
     var connectionID: UUID
     var name: String

     @Relationship(deleteRule: .cascade, inverse: \TCPreferenceJoinTCPreferenceCollection.collection)
     var prefCollections: [TCPreferenceJoinTCPreferenceCollection] = []

     init(name: String, connectionID: UUID) {
         self.name = name
         self.connectionID = connectionID
         self.key = "\(connectionID.uuidString)|\(name.lowercased())"
     }
 }

