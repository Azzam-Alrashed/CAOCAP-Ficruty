import XCTest
import SwiftUI
@testable import caocap

@MainActor
final class NodeMutationEngineTests: XCTestCase {
    var engine: NodeMutationEngine!

    override func setUp() async throws {
        engine = NodeMutationEngine()
    }

    func testAddNodeCreatesMiniAppByDefault() {
        var nodes: [SpatialNode] = []

        engine.addNode(nodes: &nodes)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].type, .miniApp)
        XCTAssertEqual(nodes[0].theme, .blue)
        XCTAssertEqual(nodes[0].title, "Mini-App")
        XCTAssertEqual(nodes[0].icon, NodeType.miniApp.defaultIcon)
        XCTAssertEqual(nodes[0].subtitle, "Tap to run, build, and configure this mini-app.")
        XCTAssertNotNil(nodes[0].miniApp)
    }

    func testAddNodeAcceptsTitleAndPosition() {
        var nodes: [SpatialNode] = []
        let position = CGPoint(x: 120, y: -40)

        engine.addNode(nodes: &nodes, type: .miniApp, title: "Cafe Menu", position: position)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].title, "Cafe Menu")
        XCTAssertEqual(nodes[0].position, position)
        XCTAssertEqual(nodes[0].type, .miniApp)
    }

    func testAddNodeDeduplicatesRequestedTitle() {
        var nodes = [
            SpatialNode(type: .miniApp, position: .zero, title: "Cafe Menu", miniApp: MiniAppState())
        ]

        engine.addNode(nodes: &nodes, title: "Cafe Menu", position: CGPoint(x: 10, y: 10))

        XCTAssertEqual(nodes.count, 2)
        XCTAssertNotEqual(nodes[1].title, "Cafe Menu")
        XCTAssertTrue(nodes[1].title.hasPrefix("Cafe Menu"))
    }

    func testUpdateMiniAppCodeTriggersExpectedCallbacks() {
        var nodes = [
            SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", miniApp: MiniAppState())
        ]

        var saveCalled = false
        engine.onRequestSave = { _ in saveCalled = true }

        engine.updateMiniAppCode(nodes: &nodes, id: nodes[0].id, text: "<h1>Updated</h1>", persist: true)
        XCTAssertEqual(nodes[0].miniApp?.codeText, "<h1>Updated</h1>")
        XCTAssertTrue(saveCalled)
    }

    func testApplyingCanonicalThemeRepairsMiniAppTheme() {
        let miniApp = SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", theme: .orange)

        XCTAssertEqual(miniApp.applyingCanonicalThemeIfNeeded().theme, .orange)
    }

    func testDeleteNodeCleansUpConnections() {
        let node1 = SpatialNode(type: .miniApp, position: .zero, title: "1")
        var node2 = SpatialNode(type: .miniApp, position: .zero, title: "2")

        node2.connectedNodeIds = [node1.id]
        node2.nextNodeId = node1.id

        var nodes = [node1, node2]

        engine.deleteNode(nodes: &nodes, id: node1.id)

        XCTAssertEqual(nodes.count, 1)
        let updatedNode2 = nodes[0]

        XCTAssertNil(updatedNode2.connectedNodeIds)
        XCTAssertNil(updatedNode2.nextNodeId)
    }

    func testConnectNodesSetsNextAndConnectedLinks() {
        let from = SpatialNode(type: .miniApp, position: .zero, title: "From", miniApp: MiniAppState())
        let to = SpatialNode(type: .miniApp, position: CGPoint(x: 100, y: 0), title: "To", miniApp: MiniAppState())
        var nodes = [from, to]
        var saveCount = 0
        engine.onRequestSave = { _ in saveCount += 1 }

        engine.connectNodes(nodes: &nodes, fromID: from.id, toID: to.id, kind: .next)
        XCTAssertEqual(nodes[0].nextNodeId, to.id)

        engine.connectNodes(nodes: &nodes, fromID: from.id, toID: to.id, kind: .connected)
        XCTAssertEqual(nodes[0].connectedNodeIds, [to.id])
        XCTAssertEqual(saveCount, 2)
    }

    func testDisconnectNodesClearsSelectedKinds() {
        var from = SpatialNode(type: .miniApp, position: .zero, title: "From", miniApp: MiniAppState())
        let to = SpatialNode(type: .miniApp, position: CGPoint(x: 100, y: 0), title: "To", miniApp: MiniAppState())
        from.nextNodeId = to.id
        from.connectedNodeIds = [to.id]
        var nodes = [from, to]

        engine.disconnectNodes(nodes: &nodes, fromID: from.id, toID: to.id, kind: .next)
        XCTAssertNil(nodes[0].nextNodeId)
        XCTAssertEqual(nodes[0].connectedNodeIds, [to.id])

        engine.disconnectNodes(nodes: &nodes, fromID: from.id, toID: to.id, kind: .connected)
        XCTAssertNil(nodes[0].connectedNodeIds)

        nodes[0].nextNodeId = to.id
        nodes[0].connectedNodeIds = [to.id]
        engine.disconnectNodes(nodes: &nodes, fromID: from.id, toID: to.id, kind: nil)
        XCTAssertNil(nodes[0].nextNodeId)
        XCTAssertNil(nodes[0].connectedNodeIds)
    }

    func testConnectNodesIgnoresSelfAndMissingEndpoints() {
        let node = SpatialNode(type: .miniApp, position: .zero, title: "Solo", miniApp: MiniAppState())
        var nodes = [node]
        var saveCalled = false
        engine.onRequestSave = { _ in saveCalled = true }

        engine.connectNodes(nodes: &nodes, fromID: node.id, toID: node.id, kind: .next)
        engine.connectNodes(nodes: &nodes, fromID: node.id, toID: UUID(), kind: .connected)

        XCTAssertNil(nodes[0].nextNodeId)
        XCTAssertNil(nodes[0].connectedNodeIds)
        XCTAssertFalse(saveCalled)
    }
}
