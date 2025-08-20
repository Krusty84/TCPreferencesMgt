//
//  TCPreferenceJoinTCPreferenceCollection.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 18/08/2025.
//

import SwiftData
import Foundation

//@Model
//final class TCPreferenceJoinTCPreferenceCollection {
//    var connectionID: UUID
//
//    @Relationship var preference: TCPreference?
//    @Relationship var collection: TCPreferenceCollection?
//
//    init(preference: TCPreference, collection: TCPreferenceCollection, connectionID: UUID) {
//        self.preference = preference
//        self.collection = collection
//        self.connectionID = connectionID
//    }
//}


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
