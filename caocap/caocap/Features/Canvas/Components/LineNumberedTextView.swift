import SwiftUI
import UIKit

struct LineNumberedTextView: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> CodeEditorContainer {
        let container = CodeEditorContainer()
        container.delegate = context.coordinator
        container.text = text
        return container
    }
    
    func updateUIView(_ uiView: CodeEditorContainer, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CodeEditorContainerDelegate {
        var parent: LineNumberedTextView
        
        init(_ parent: LineNumberedTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ text: String) {
            self.parent.text = text
        }
    }
}

protocol CodeEditorContainerDelegate: AnyObject {
    func textDidChange(_ text: String)
}

class CodeEditorContainer: UIView, UITextViewDelegate {
    weak var delegate: CodeEditorContainerDelegate?
    
    private let gutterView = UITextView()
    private let textView = UITextView()
    
    private let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private let gutterWidth: CGFloat = 45
    
    var text: String {
        get { textView.text }
        set {
            if textView.text != newValue {
                textView.text = newValue
                updateLineNumbers()
                highlightSyntax()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0) // VS Code Dark+ Background
        
        // Setup Gutter
        gutterView.isEditable = false
        gutterView.isSelectable = false
        gutterView.showsVerticalScrollIndicator = false
        gutterView.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0)
        gutterView.textColor = UIColor.darkGray
        gutterView.font = font
        gutterView.textAlignment = .right
        gutterView.textContainerInset = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: 8)
        
        // Setup Main Text View
        textView.delegate = self
        textView.font = font
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.backgroundColor = .clear
        textView.textColor = UIColor(white: 0.9, alpha: 1.0)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 8, bottom: 16, right: 16)
        textView.keyboardAppearance = .dark
        
        addSubview(gutterView)
        addSubview(textView)
        
        updateLineNumbers()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        textView.frame = CGRect(x: gutterWidth, y: 0, width: bounds.width - gutterWidth, height: bounds.height)
    }
    
    // MARK: - Sync Scrolling
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == textView {
            gutterView.contentOffset = textView.contentOffset
        }
    }
    
    // MARK: - Text Change
    func textViewDidChange(_ textView: UITextView) {
        delegate?.textDidChange(textView.text)
        updateLineNumbers()
        highlightSyntax()
    }
    
    private func updateLineNumbers() {
        // Calculate number of lines based on newline characters
        let components = textView.text.components(separatedBy: .newlines)
        let lineCount = max(components.count, 1)
        
        var numbers = ""
        for i in 1...lineCount {
            numbers += "\(i)\n"
        }
        gutterView.text = numbers
    }
    
    // MARK: - Syntax Highlighting
    private func highlightSyntax() {
        let textStorage = textView.textStorage
        let string = textStorage.string
        let fullRange = NSRange(location: 0, length: string.utf16.count)
        
        textStorage.beginEditing()
        
        // Reset base style
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: UIColor(white: 0.9, alpha: 1.0)
        ], range: fullRange)
        
        // Multi-line Comments: /* ... */
        if let regex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/") {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: match.range) }
        }
        
        // Single-line Comments: // ...
        if let regex = try? NSRegularExpression(pattern: "//.*") {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: match.range) }
        }
        
        // HTML Tags: <...>
        if let regex = try? NSRegularExpression(pattern: "</?[a-zA-Z0-9]+[^>]*>") {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor(red: 0.34, green: 0.61, blue: 0.84, alpha: 1.0), range: match.range) }
        }
        
        // Strings: "..." or '...'
        if let regex = try? NSRegularExpression(pattern: "(\"[^\"]*\")|('[^']*')") {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor(red: 0.81, green: 0.57, blue: 0.40, alpha: 1.0), range: match.range) }
        }
        
        // Keywords
        let keywords = ["const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "import", "export", "true", "false", "new", "document", "window", "=>"]
        let keywordPattern = "\\b(\(keywords.joined(separator: "|")))\\b"
        if let regex = try? NSRegularExpression(pattern: keywordPattern) {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor(red: 0.77, green: 0.52, blue: 0.75, alpha: 1.0), range: match.range) }
        }
        
        // CSS Properties (e.g. background-color:, margin:)
        if let regex = try? NSRegularExpression(pattern: "\\b[a-zA-Z-]+:") {
            let matches = regex.matches(in: string, range: fullRange)
            for match in matches { textStorage.addAttribute(.foregroundColor, value: UIColor(red: 0.61, green: 0.86, blue: 0.99, alpha: 1.0), range: match.range) }
        }
        
        textStorage.endEditing()
    }
}
