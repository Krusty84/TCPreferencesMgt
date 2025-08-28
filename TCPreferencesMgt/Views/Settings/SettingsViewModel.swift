//
//  SettingsViewModel.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 12/08/2025.
//

import Foundation
import Combine
import TCSwiftBridge

@MainActor
class SettingsViewModel: ObservableObject {
    private let tcApi = TeamcenterAPIService.shared
    @Published var tcLoginValid: Bool = false
    @Published var isLoading: Bool = false
    @Published var tcSessionId: String?
    @Published var tcResponseCode: Int?
    @Published var tcErrorMessage: String?
    @Published var preferences: [PreferenceEntry] = []
    
    func tcLogin(tcBaseUrl: String, username: String, password: String) async  {
        tcSessionId = nil
        tcResponseCode = nil
        tcErrorMessage = nil
        isLoading = true
        
        let sessionId = await tcApi.tcLogin(
            tcEndpointUrl: APIConfig.tcLoginUrl(tcUrl: tcBaseUrl),
            userName: username,
            userPassword: password
        )
        
        guard let validSession = sessionId else {
            isLoading = false
            tcResponseCode = 401
            tcErrorMessage = "Teamcenter login failed"
            //LoggerHelper.error("TC login failed; no JSESSIONID returned.")
            return
        }
        
        tcSessionId = validSession
        
        if (await tcApi.getTcSessionInfo(
            tcEndpointUrl: APIConfig.tcSessionInfoUrl(tcUrl: tcBaseUrl)
        )) != nil {
            tcResponseCode = 200
            isLoading = false
            tcLoginValid = true
        } else {
            tcResponseCode = 200
            tcErrorMessage = "Could not fetch session info"
            isLoading = false
            tcLoginValid = false
            //LoggerHelper.error("getSessionInfo returned nil")
        }
    
    }
    
    func importTCPreferences(tcBaseUrl: String) async {
        tcResponseCode = nil
        tcErrorMessage = nil
        isLoading = true
        
        if let list = await tcApi.getPreferences(
            tcEndpointUrl: APIConfig.tcGetPreferencesUrl(tcUrl: tcBaseUrl),
            preferenceNames:["*"],
            includeDescriptions: true
        ){
            preferences = list.sorted { $0.definition.name.localizedCompare($1.definition.name) == .orderedAscending }
           
        } else {
            preferences = []
        }
        
        isLoading = false
    }
}
