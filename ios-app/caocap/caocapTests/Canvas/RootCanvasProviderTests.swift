import CoreGraphics
import Foundation
import Testing
@testable import caocap

struct RootCanvasProviderTests {
    @Test func rootDefinesACenteredHelloWorldMiniApp() throws {
        let nodes = RootCanvasProvider.nodes
        #expect(nodes.count == 1)
        #expect(RootCanvasProvider.defaultViewportScale == 0.8)
        #expect(RootCanvasProvider.snapshot.viewportScale == RootCanvasProvider.defaultViewportScale)
        #expect(RootCanvasProvider.snapshot.nodes == nodes)

        let helloWorld = try #require(nodes.first)
        #expect(helloWorld.id == RootCanvasProvider.helloWorldMiniAppNodeID)
        #expect(helloWorld.type == .miniApp)
        #expect(helloWorld.position == .zero)
        #expect(helloWorld.title == "Hello World")
        #expect(helloWorld.subtitle == "Tap to open")
        #expect(helloWorld.icon == "play.circle.fill")
        #expect(helloWorld.theme == .blue)
        #expect(helloWorld.action == nil)
        #expect(helloWorld.linkedCanvasFileName == nil)

        let code = try #require(helloWorld.miniApp?.codeText)
        #expect(code == ProjectTemplateProvider.defaultCode)
        #expect(code.isEmpty)
    }

    @Test func legacyCuratedNodesRetainTheNineNodeLaunchGrid() throws {
        let nodes = RootCanvasProvider.legacyCuratedNodes
        #expect(nodes.count == 9)
        #expect(RootCanvasProvider.legacyCuratedNodeIDs.count == 9)

        let columnSpacing: CGFloat = 250
        let rowY: [CGFloat] = [-330, -110, 110, 330]

        #expect(nodes[0].id == RootCanvasProvider.proNodeID)
        #expect(nodes[0].position == CGPoint(x: -columnSpacing, y: rowY[0]))

        let tutorial = try #require(nodes.first { $0.id == RootCanvasProvider.tutorialNodeID })
        #expect(tutorial.type == .subCanvas)
        #expect(tutorial.linkedCanvasFileName == RootCanvasProvider.tutorialFileName)

        let pacManPortal = try #require(nodes.first { $0.id == RootCanvasProvider.pacManNodeID })
        #expect(pacManPortal.type == .subCanvas)
        #expect(pacManPortal.position == CGPoint(x: columnSpacing, y: rowY[1]))

        let help = try #require(nodes.first { $0.id == RootCanvasProvider.helpNodeID })
        #expect(help.position == CGPoint(x: 0, y: 550))
        #expect(help.action == .openHelp)
    }

    @Test func helloWorldLaunchMiniAppUsesEmptyPlaceholderCode() throws {
        let node = try #require(RootCanvasProvider.nodes.first)
        let code = try #require(node.miniApp?.codeText)

        #expect(node.type == .miniApp)
        #expect(node.title == "Hello World")
        #expect(code == ProjectTemplateProvider.defaultCode)
        #expect(code.isEmpty)
    }

    @Test func xoCanvasContainsPlaceholderMiniApp() throws {
        let node = try #require(XOCanvasProvider.snapshot.nodes.first)
        let code = try #require(node.miniApp?.codeText)

        #expect(node.type == .miniApp)
        #expect(node.title == "XO")
        #expect(code == XOCanvasProvider.code)
        #expect(code.isEmpty)
    }
}
