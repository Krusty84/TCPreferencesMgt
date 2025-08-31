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
        
        
        let result = await tcApi.tcLoginGetSession(tcUrl: tcBaseUrl, username: username, password: password)
        if(result.code == 200){
            tcResponseCode = 200
            isLoading = false
            tcLoginValid = true
        } else if (result.code == 400){
            tcResponseCode = 400
            isLoading = false
            tcLoginValid = false
        }
            
    }
    
    func importTCPreferences(tcBaseUrl: String) async {
        tcResponseCode = nil
        tcErrorMessage = nil
        isLoading = true
        
        if let list = await tcApi.getRefreshedPreferences(tcUrl:tcBaseUrl)
        {
            preferences = list.sorted { $0.definition.name.localizedCompare($1.definition.name) == .orderedAscending }
           
        } else {
            preferences = []
        }
        
        isLoading = false
    }
}
