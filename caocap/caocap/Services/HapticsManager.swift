import SwiftUI
import UIKit

@MainActor
public class HapticsManager {
    public static let shared = HapticsManager()
    
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("haptics_intensity") private var hapticsIntensity = "Medium"
    
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    
    private init() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        soft.prepare()
        rigid.prepare()
    }
    
    public func trigger(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticsEnabled else { return }
        
        let adjustedStyle: UIImpactFeedbackGenerator.FeedbackStyle
        
        switch hapticsIntensity {
        case "Subtle":
            adjustedStyle = .light
        case "Sharp":
            adjustedStyle = .rigid
        default:
            adjustedStyle = style
        }
        
        switch adjustedStyle {
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .heavy: heavy.impactOccurred()
        case .soft: soft.impactOccurred()
        case .rigid: rigid.impactOccurred()
        @unknown default:
            medium.impactOccurred()
        }
    }
    
    public func selectionChanged() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    
    public func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
