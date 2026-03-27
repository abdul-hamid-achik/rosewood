import Foundation
import SwiftUI
import TOMLKit

protocol ConfigurationServiceProtocol: ObservableObject {
    var settings: AppSettings { get }
    var currentThemeColors: ThemeColors { get }
    var currentTheme: ThemeDefinition { get }
    
    func loadSettings()
    func saveSettings() throws
    func updateSettings(_ settings: AppSettings)
    func resetSettingsToDefaults()
}
