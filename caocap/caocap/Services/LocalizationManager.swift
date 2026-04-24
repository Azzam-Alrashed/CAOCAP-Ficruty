import SwiftUI

public class LocalizationManager {
    public static let shared = LocalizationManager()
    
    private init() {}
    
    public func locale(for language: String) -> Locale {
        switch language {
        case "Arabic":
            return Locale(identifier: "ar")
        case "French":
            return Locale(identifier: "fr")
        case "German":
            return Locale(identifier: "de")
        case "Spanish":
            return Locale(identifier: "es")
        default:
            return Locale(identifier: "en")
        }
    }
    
    public func layoutDirection(for language: String) -> LayoutDirection {
        return language == "Arabic" ? .rightToLeft : .leftToRight
    }
}
