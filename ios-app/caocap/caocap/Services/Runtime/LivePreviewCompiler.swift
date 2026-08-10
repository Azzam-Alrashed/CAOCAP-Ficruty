import Foundation

public struct LivePreviewCompilation: Hashable {
    public let miniAppNodeID: UUID
    public let html: String
}

/// Produces each Mini-App's runnable preview payload from its embedded source.
public struct LivePreviewCompiler {
    public init() {}

    public func compile(nodes: [SpatialNode]) -> LivePreviewCompilation? {
        guard let node = nodes.first(where: { $0.type == .miniApp }) else { return nil }
        return compile(node: node)
    }

    public func compile(node: SpatialNode) -> LivePreviewCompilation? {
        guard node.type == .miniApp, let miniApp = node.miniApp else {
            return nil
        }

        var compiledHTML = miniApp.codeText
        injectViewportMeta(into: &compiledHTML)
        return LivePreviewCompilation(miniAppNodeID: node.id, html: compiledHTML)
    }

    private func injectViewportMeta(into html: inout String) {
        if html.localizedCaseInsensitiveContains("name=\"viewport\"") || html.localizedCaseInsensitiveContains("name='viewport'") {
            return
        }
        
        let metaTag = "\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        if let headStart = html.range(of: "<head", options: .caseInsensitive),
           let headOpenEnd = html.range(of: ">", range: headStart.upperBound..<html.endIndex) {
            html.insert(contentsOf: metaTag, at: headOpenEnd.upperBound)
        } else if let htmlStart = html.range(of: "<html", options: .caseInsensitive),
                  let htmlOpenEnd = html.range(of: ">", range: htmlStart.upperBound..<html.endIndex) {
            html.insert(contentsOf: "<head>\(metaTag)</head>", at: htmlOpenEnd.upperBound)
        } else {
            html = """
            <!DOCTYPE html>
            <html><head>\(metaTag)</head><body>
            \(html)
            </body></html>
            """
        }
    }
}
