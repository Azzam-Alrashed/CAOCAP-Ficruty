import SwiftUI

public class CoCaptainViewModel: ObservableObject {
    @Published public var isPresented: Bool = false
    @Published public var messages: [String] = ["Hello! I'm your Co-Captain. How can I help you build today?"]
    
    public init() {}
    
    public func setPresented(_ presented: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = presented
        }
    }
}
