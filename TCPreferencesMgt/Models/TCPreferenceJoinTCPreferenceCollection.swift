//
//  TCPreferenceJoinTCPreferenceCollection.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 18/08/2025.
//

import SwiftData
import Foundation

@Model
final class TCPreferenceJoinTCPreferenceCollection {
     var preference: TCPreference?
     var collection: TCPreferenceCollection?
     var connectionID: UUID

     init(preference: TCPreference, collection: TCPreferenceCollection, connectionID: UUID) {
         self.preference = preference
         self.collection = collection
         self.connectionID = connectionID
     }
}
