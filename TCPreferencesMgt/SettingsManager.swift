//
//  SettingsManager.swift
//  TCPreferencesMgt
//
//  Created by Sedoykin Alexey on 01/09/2025.
//

import Foundation
import Combine
import SwiftUI

class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    
    private let appLoggingEnabledKey = "com.krusty84.settings.appLoggingEnabled"
    
    var appLoggingEnabled: Bool {
        get { defaults.bool(forKey: appLoggingEnabledKey) }
        set { defaults.set(newValue, forKey: appLoggingEnabledKey) }
    }
}
