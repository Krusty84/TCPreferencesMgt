//
//  PreferencesImporter.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 13/08/2025.
//

import Foundation
import CryptoKit
import SwiftData
import TCSwiftBridge

@MainActor
enum PreferencesImporter {
    static let tcApi = TeamcenterAPIService.shared
    static let vm4Login = SettingsViewModel()
    /// Imports all preferences for `connection` from Teamcenter and persists them in SwiftData.
    /// - Parameters:
    ///   - context: SwiftData model context
    ///   - connection: target connection
    ///   - baseUrl: Teamcenter base URL
    ///   - batchSize: insert/save batch size (to keep memory low)
    static func importAll(
            context: ModelContext,
            connection: TCConnection,
            baseUrl: String,
            batchSize: Int = 2_000
        ) async throws -> Int {
            // --- A) Start run window
            let runStart = Date()
            connection.lastImportStartedAt = runStart
            try? context.save()
            
           await vm4Login.tcLogin(
                    tcBaseUrl: baseUrl,
                    username: connection.username,
                    password: connection.password
                )
            
            guard vm4Login.tcLoginValid else {
                    throw TCImportError.loginFailed
            }
            
            guard let list = await tcApi.getPreferences(
                tcEndpointUrl: APIConfig.tcGetPreferencesUrl(tcUrl: baseUrl),
                preferenceNames: ["*"],
                includeDescriptions: true
            ) else {
                throw TCImportError.fetchFailed
            }

            let sorted = list.sorted {
                $0.definition.name.localizedCompare($1.definition.name) == .orderedAscending
            }

            // Track which existing keys we did NOT see (to mark Missing later)
            let idConst = connection.id
            let fetchAll = FetchDescriptor<TCPreference>(
                predicate: #Predicate { $0.connectionID == idConst }
            )
            let existingAll = try context.fetch(fetchAll)
            var unseenKeys = Set(existingAll.map(\.key))

            var processed = 0
            var pending = 0

            for entry in sorted {
                let def = entry.definition
                let val = entry.values

                let key = "\(connection.id.uuidString)|\(def.name)"
                let fp = preferenceFingerprint(
                    name: def.name,
                    category: def.category,
                    prefDescription: def.description,
                    type: def.type,
                    isArray: def.isArray,
                    isDisabled: def.isDisabled,
                    protectionScope: def.protectionScope,
                    isEnvEnabled: def.isEnvEnabled,
                    isOOTBPreference: def.isOOTBPreference,
                    valueOrigination: val?.valueOrigination,
                    values: val?.values
                )

                let keyConst = key
                let fetchOne = FetchDescriptor<TCPreference>(
                    predicate: #Predicate { $0.key == keyConst }
                )
                let existing = try context.fetch(fetchOne).first

                if let pref = existing {
                    // Seen this run
                    unseenKeys.remove(pref.key)

                    // Always stamp lastImportedAt now; lastSeenAt will be set to runEnd below
                    pref.lastImportedAt = Date()

                    if pref.fingerprint != fp {
                        // CHANGED
                        pref.name = def.name
                        pref.category = def.category
                        pref.prefDescription = def.description
                        pref.type = def.type
                        pref.isArray = def.isArray
                        pref.isDisabled = def.isDisabled
                        pref.protectionScope = def.protectionScope
                        pref.isEnvEnabled = def.isEnvEnabled
                        pref.isOOTBPreference = def.isOOTBPreference
                        pref.valueOrigination = val?.valueOrigination
                        pref.values = val?.values
                        pref.fingerprint = fp
                        pref.lastChangedAt = Date()

                        let rev = TCPreferenceRevision(
                            preference: pref,
                            capturedAt: Date(),
                            name: pref.name,
                            category: pref.category,
                            prefDescription: pref.prefDescription,
                            type: pref.type,
                            isArray: pref.isArray,
                            isDisabled: pref.isDisabled,
                            protectionScope: pref.protectionScope,
                            isEnvEnabled: pref.isEnvEnabled,
                            isOOTBPreference: pref.isOOTBPreference,
                            valueOrigination: pref.valueOrigination,
                            values: pref.values,
                            fingerprint: fp
                        )
                        context.insert(rev)
                    }

                } else {
                    // NEW
                    let now = Date()
                    let pref = TCPreference(
                        key: key,
                        connection: connection,
                        connectionID: connection.id,
                        name: def.name,
                        category: def.category,
                        prefDescription: def.description,
                        type: def.type,
                        isArray: def.isArray,
                        isDisabled: def.isDisabled,
                        protectionScope: def.protectionScope,
                        isEnvEnabled: def.isEnvEnabled,
                        isOOTBPreference: def.isOOTBPreference,
                        valueOrigination: val?.valueOrigination,
                        values: val?.values,
                        comment: nil,
                        firstSeenAt: now,
                        lastImportedAt: now,
                        lastChangedAt: now,
                        fingerprint: fp
                    )
                    context.insert(pref)

                    let rev = TCPreferenceRevision(
                        preference: pref,
                        capturedAt: now,
                        name: def.name,
                        category: def.category,
                        prefDescription: def.description,
                        type: def.type,
                        isArray: def.isArray,
                        isDisabled: def.isDisabled,
                        protectionScope: def.protectionScope,
                        isEnvEnabled: def.isEnvEnabled,
                        isOOTBPreference: def.isOOTBPreference,
                        valueOrigination: val?.valueOrigination,
                        values: val?.values,
                        fingerprint: fp
                    )
                    context.insert(rev)
                }

                processed += 1
                pending += 1
                if pending >= batchSize {
                    try context.save()
                    pending = 0
                }
            }

            if pending > 0 { try context.save() }

            // --- B) End run window; stamp "seen" items to runEnd
            let runEnd = Date()
            connection.lastImportCompletedAt = runEnd

            // Mark everything we actually saw during this run
            let seenFetch = FetchDescriptor<TCPreference>(
                predicate: #Predicate { $0.connectionID == idConst && $0.lastImportedAt >= runStart }
            )
            let seen = try context.fetch(seenFetch)
            for p in seen {
                p.lastSeenAt = runEnd
            }

            // Anything still in unseenKeys is "Missing" (we leave its lastSeenAt untouched)
            try context.save()
            return processed
        }
    

    /// Deletes all preferences linked to the connection (fast path).
    @MainActor
    private func clearExisting(context: ModelContext, connection: TCConnection) throws {
        let connID = connection.id // capture as a plain constant

        let desc = FetchDescriptor<TCPreference>(
            predicate: #Predicate<TCPreference> { pref in
                pref.connectionID == connID
            }
        )
        // (Optional) batch if you want:
        // desc.fetchLimit = 2_000

        let existing = try context.fetch(desc)
        for p in existing { context.delete(p) }
        try context.save()
    }
    
    /// preferenceFingerprint - has for track changed preferences
    private static func preferenceFingerprint(
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
        values: [String]?
    ) -> String {
        // normalize values to a consistent string
        let joinedValues = (values ?? []).joined(separator: "\u{241F}") // unit separator
        let base = [
            name, category, prefDescription,
            String(type), String(isArray), String(isDisabled),
            protectionScope, String(isEnvEnabled), String(isOOTBPreference),
            valueOrigination ?? "", joinedValues
        ].joined(separator: "\u{241E}") // record separator

        let digest = Insecure.MD5.hash(data: base.data(using: .utf8)!)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
