import SwiftUI

struct CoCaptainView: View {
    @ObservedObject var viewModel: CoCaptainViewModel
    @State private var text: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat History
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages, id: \.self) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Input Area
                HStack(spacing: 12) {
                    TextField("Ask anything...", text: $text)
                        .padding(12)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(12)
                    
                    Button(action: {
                        if !text.isEmpty {
                            viewModel.messages.append(text)
                            text = ""
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.02))
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
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: String
    
    var body: some View {
        Text(message)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .font(.system(size: 16))
    }
}

#Preview {
    CoCaptainView(viewModel: CoCaptainViewModel())
}
