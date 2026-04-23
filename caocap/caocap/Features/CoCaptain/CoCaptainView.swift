import SwiftUI

struct CoCaptainView: View {
    var viewModel: CoCaptainViewModel
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                // Chat History
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isThinking {
                                HStack(alignment: .bottom, spacing: 8) {
                                    // AI Avatar for thinking state
                                    Image("cocaptain")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                        .shadow(color: .blue.opacity(0.5), radius: 4, x: 0, y: 0)
                                    
                                    ThinkingIndicator()
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    
                                    Spacer()
                                }
                                .id("thinking_indicator")
                            }
                        }
                        .padding()
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $viewModel.lastScrollPosition)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.isThinking) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isFocused) { _, newValue in
                        if newValue {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }
                    .onAppear {
                        // Restore position if it exists, otherwise scroll to bottom
                        if let lastPos = viewModel.lastScrollPosition {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation {
                                    proxy.scrollTo(lastPos, anchor: .top)
                                }
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }
                }
                
                VStack(spacing: 0) {
                    Divider().opacity(0.5)
                    HStack(alignment: .bottom, spacing: 8) {
                        // Leading Attachment Button
                        Button(action: {
                            // Attachment action placeholder
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.blue)
                                .shadow(color: .blue.opacity(0.2), radius: 4)
                        }
                        .padding(.bottom, 6)
                        
                        // Pill-shaped TextField
                        HStack(spacing: 0) {
                            TextField("Ask CoCaptain...", text: $text, axis: .vertical)
                                .lineLimit(1...5)
                                .focused($isFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isFocused ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                        
                        let isInputValid = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        
                        // Dynamic Send/Mic Button
                        Button(action: {
                            if isInputValid {
                                viewModel.sendMessage(text.trimmingCharacters(in: .whitespacesAndNewlines))
                                text = ""
                                isFocused = false
                            }
                        }) {
                            ZStack {
                                if isInputValid {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 38))
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 22))
                                        .transition(.scale.combined(with: .opacity))
                                        .frame(width: 38, height: 38)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                }
                            }
                            .foregroundColor(.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 6, y: 3)
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isInputValid)
                        .padding(.bottom, 5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.02))
                }
            }
            .navigationTitle("Co-Captain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.setPresented(false)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        viewModel.clearHistory()
                    }) {
                        Text("Clear")
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isThinking {
            withAnimation {
                proxy.scrollTo("thinking_indicator", anchor: .bottom)
            }
        } else if let lastMessage = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

struct ThinkingIndicator: View {
    @State private var dotScale: CGFloat = 0.5
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScale)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: dotScale
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
        .onAppear {
            dotScale = 1.0
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer()
            } else {
                // AI Avatar Icon
                Image("cocaptain")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .shadow(color: .blue.opacity(0.5), radius: 4, x: 0, y: 0)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.attributedText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if message.isUser {
                                MessageBubbleShape(isUser: true)
                                    .fill(LinearGradient(colors: [Color(hex: "007AFF"), Color(hex: "0051FF")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            } else {
                                let aiGradient = ColorScheme.light == colorScheme ? 
                                    [Color(white: 1.0), Color(white: 0.96)] : 
                                    [Color(white: 0.18), Color(white: 0.14)]
                                
                                MessageBubbleShape(isUser: false)
                                    .fill(
                                        LinearGradient(
                                            colors: aiGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        MessageBubbleShape(isUser: false)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        Color.blue.opacity(0.3),
                                                        Color.cyan.opacity(0.1)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.8
                                            )
                                    )
                            }
                        }
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .font(.system(size: 15, weight: .regular))
                    .shadow(color: message.isUser ? .blue.opacity(0.2) : .clear, radius: 5, y: 2)
            }
            
            if message.isUser {
                // User Avatar Icon (SF Symbol placeholder)
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(0.6))
                }
            } else {
                Spacer()
            }
        }
    }
}


struct MessageBubbleShape: Shape {
    var isUser: Bool
    var radius: CGFloat = 18
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Define corners: pointy tail at bottom-right for User, bottom-left for AI
        let tl = radius
        let tr = radius
        let bl = isUser ? radius : 4
        let br = isUser ? 4 : radius
        
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        return path
    }
}

#Preview {
    CoCaptainView(viewModel: CoCaptainViewModel())
}
