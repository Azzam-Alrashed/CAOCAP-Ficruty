import SwiftUI
import StoreKit

struct PurchaseView: View {
    @Environment(\.dismiss) var dismiss
    @State private var manager = SubscriptionManager.shared
    @State private var selectedProductID: String = "com.caocap.pro.yearly"
    @State private var isPurchasing = false
    @State private var appearAnimation = false
    
    // Mock features based on CAOCAP Pro
    let features = [
        FeatureItem(icon: "sparkles", title: "AI Co-Captain", subtitle: "Unlimited intelligent design suggestions", color: Color(hex: "A855F7")),
        FeatureItem(icon: "cloud.fill", title: "Cloud Sync", subtitle: "Access your projects from any device", color: Color(hex: "10B981")),
        FeatureItem(icon: "paintpalette.fill", title: "Custom Themes", subtitle: "Exclusive premium UI themes and colors", color: Color(hex: "F59E0B")),
    ]
    
    var body: some View {
        ZStack {
            // MARK: - Background
            Color(hex: "050505").ignoresSafeArea()
            
            // Animated Mesh Background
            MeshBackgroundView()
                .opacity(0.6)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 48) {
                    // MARK: - Header
                    VStack(spacing: 20) {
                        ZStack {
                            // Pulsing Glow
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 100, height: 100)
                                .blur(radius: appearAnimation ? 30 : 10)
                                .scaleEffect(appearAnimation ? 1.2 : 0.8)
                                .opacity(0.4)
                                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: appearAnimation)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 48, weight: .black))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .white.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 5)
                                .scaleEffect(appearAnimation ? 1.0 : 0.5)
                                .rotationEffect(.degrees(appearAnimation ? 0 : -20))
                        }
                        
                        VStack(spacing: 8) {
                            Text("CAOCAP PRO")
                                .font(.system(size: 14, weight: .black))
                                .kerning(4)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "A855F7"), Color(hex: "3B82F6")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Unlimited Creativity")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("The ultimate toolkit for spatial designers and vibecoders.")
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 20)
                    }
                    .padding(.top, 60)
                    
                    // MARK: - Features
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            FeatureRow(feature: feature)
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(x: appearAnimation ? 0 : -20)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: appearAnimation)
                        }
                    }
                    
                    // MARK: - Plans
                    VStack(spacing: 16) {
                        PlanCard(
                            id: "com.caocap.pro.monthly",
                            title: "Monthly",
                            price: "$9.99",
                            subtitle: "Billed monthly",
                            isSelected: selectedProductID == "com.caocap.pro.monthly",
                            action: { withAnimation(.spring()) { selectedProductID = "com.caocap.pro.monthly" } }
                        )
                        
                        PlanCard(
                            id: "com.caocap.pro.yearly",
                            title: "Yearly",
                            price: "$79.99",
                            subtitle: "Billed annually • Save 33%",
                            isSelected: selectedProductID == "com.caocap.pro.yearly",
                            isBestValue: true,
                            action: { withAnimation(.spring()) { selectedProductID = "com.caocap.pro.yearly" } }
                        )
                    }
                    .padding(.horizontal, 50)
                    .opacity(appearAnimation ? 1 : 0)
                    .offset(y: appearAnimation ? 0 : 30)
                    .animation(.spring().delay(0.5), value: appearAnimation)
                    
                    // MARK: - Action
                    VStack(spacing: 20) {
                        Button(action: purchaseAction) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "7C3AED"), Color(hex: "3B82F6")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 64)
                                    .shadow(color: Color(hex: "7C3AED").opacity(0.4), radius: 20, x: 0, y: 10)
                                
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    HStack {
                                        Text("Unlock Everything")
                                            .font(.system(size: 20, weight: .bold))
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 50)
                        .scaleEffect(isPurchasing ? 0.95 : 1.0)
                        .animation(.spring(), value: isPurchasing)
                        
                        // Footer Links
                        HStack(spacing: 20) {
                            Button("Restore Purchases") {
                                Task { try? await manager.restorePurchases() }
                            }
                            Circle().frame(width: 3, height: 3)
                            Link("Terms", destination: URL(string: "https://caocap.app/terms")!)
                            Circle().frame(width: 3, height: 3)
                            Link("Privacy", destination: URL(string: "https://caocap.app/privacy")!)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 60)
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeIn.delay(0.7), value: appearAnimation)
                }
            }
            .padding(.horizontal, 20)
            
            // Close Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(12)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                appearAnimation = true
            }
        }
        .task {
            await manager.fetchProducts()
        }
        .preferredColorScheme(.dark)
    }
    
    private func purchaseAction() {
        // UI Feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        guard let product = manager.products.first(where: { $0.id == selectedProductID }) else {
            isPurchasing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isPurchasing = false
                dismiss()
            }
            return
        }
        
        isPurchasing = true
        Task {
            do {
                _ = try await manager.purchase(product)
                isPurchasing = false
                dismiss()
            } catch {
                print("Purchase failed: \(error)")
                isPurchasing = false
            }
        }
    }
}



#Preview {
    PurchaseView()
        .preferredColorScheme(.dark)
}
