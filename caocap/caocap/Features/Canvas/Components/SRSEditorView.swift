import SwiftUI

struct SRSEditorView: View {
    let node: SpatialNode
    let store: ProjectStore
    @Environment(\.dismiss) var dismiss
    @State private var text: String
    
    init(node: SpatialNode, store: ProjectStore) {
        self.node = node
        self.store = store
        self._text = State(initialValue: node.textContent ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Top Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(node.theme.color)
                    Text("Requirements")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.leading, 20)
                
                Spacer()
                
                Button(action: {
                    store.updateNodeTextContent(id: node.id, text: text, persist: true)
                    dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(node.theme.color)
                        .cornerRadius(16)
                }
                .padding(.trailing, 20)
            }
            .frame(height: 56)
            .background(Color(uiColor: .systemBackground))
            
            Divider()
            
            // Notion-like Editor
            TextEditor(text: $text)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .lineSpacing(8)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}
