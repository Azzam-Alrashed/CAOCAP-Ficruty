import CoreGraphics
import Foundation
import Testing
@testable import caocap

struct ProjectMigrationTests {

    @MainActor
    @Test func loadThrowsForMissingSchemaVersion() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "legacy.json"
        let legacyJSON = """
        {
            "projectName": "Legacy Project",
            "viewportOffset": {"width": 0, "height": 0},
            "viewportScale": 1.0,
            "nodes": []
        }
        """

        try legacyJSON.data(using: .utf8)!.write(to: persistence.fileURL(for: fileName))

        #expect(throws: ProjectPersistenceError.unsupportedSchemaVersion(nil, current: ProjectPersistenceService.currentSchemaVersion)) {
            try persistence.load(fileName: fileName)
        }
    }

    @MainActor
    @Test func loadingCurrentVersionSucceeds() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "v4.json"
        let original = ProjectSnapshot(
            schemaVersion: ProjectPersistenceService.currentSchemaVersion,
            projectName: "V4 Project",
            nodes: [],
            viewportOffset: CGSize(width: 10, height: 20),
            viewportScale: 0.5
        )
        try persistence.save(original, fileName: fileName)

        let snapshot = try persistence.load(fileName: fileName)

        #expect(snapshot.schemaVersion == ProjectPersistenceService.currentSchemaVersion)
        #expect(snapshot.projectName == "V4 Project")
        #expect(snapshot.viewportScale == 0.5)
        #expect(snapshot.viewportOffset == CGSize(width: 10, height: 20))
    }

    @MainActor
    @Test func loadThrowsForOldSchemaVersion() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "v1.json"
        let v1JSON = """
        {
            "schemaVersion": 1,
            "projectName": "V1 Project",
            "viewportOffset": {"width": 0, "height": 0},
            "viewportScale": 1.0,
            "nodes": []
        }
        """

        try v1JSON.data(using: .utf8)!.write(to: persistence.fileURL(for: fileName))

        #expect(throws: ProjectPersistenceError.unsupportedSchemaVersion(1, current: ProjectPersistenceService.currentSchemaVersion)) {
            try persistence.load(fileName: fileName)
        }
    }

    @MainActor
    @Test func loadingNewerVersionAbortsToPreventDataLoss() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "future.json"
        let v99JSON = """
        {
            "schemaVersion": 99,
            "projectName": "Future Project",
            "viewportOffset": {"width": 0, "height": 0},
            "viewportScale": 1.0,
            "nodes": []
        }
        """

        try v99JSON.data(using: .utf8)!.write(to: persistence.fileURL(for: fileName))

        #expect(throws: ProjectPersistenceError.unsupportedSchemaVersion(99, current: ProjectPersistenceService.currentSchemaVersion)) {
            try persistence.load(fileName: fileName)
        }
    }

    @MainActor
    @Test func storeFallsBackToInitialNodesWhenProjectFileIsCorrupted() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "corrupted.json"
        try Data("{not-json}".utf8).write(to: persistence.fileURL(for: fileName))

        let fallbackNode = SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", miniApp: MiniAppState(codeText: "<h1>Fallback</h1>"))
        let store = ProjectStore(
            fileName: fileName,
            projectName: "Fallback Project",
            initialNodes: [fallbackNode],
            persistence: persistence
        )

        #expect(store.nodes.count == 1)
        #expect(store.nodes[0].id == fallbackNode.id)
        #expect(store.nodes[0].title == fallbackNode.title)
        #expect(store.nodes[0].miniApp?.codeText == fallbackNode.miniApp?.codeText)
        #expect(store.projectName == "Fallback Project")
    }

    @MainActor
    @Test func storeFallsBackForUnsupportedSchemaWithoutSaving() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "v1-on-disk.json"
        let v1JSON = """
        {
            "schemaVersion": 1,
            "projectName": "V1 Project",
            "viewportOffset": {"width": 0, "height": 0},
            "viewportScale": 1.0,
            "nodes": []
        }
        """
        try v1JSON.data(using: .utf8)!.write(to: persistence.fileURL(for: fileName))

        let fallbackNode = SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", miniApp: MiniAppState(codeText: "<h1>Fallback</h1>"))
        _ = ProjectStore(
            fileName: fileName,
            projectName: "Fallback Project",
            initialNodes: [fallbackNode],
            persistence: persistence
        )

        let diskData = try Data(contentsOf: persistence.fileURL(for: fileName))
        let diskJSON = String(data: diskData, encoding: .utf8) ?? ""
        #expect(diskJSON.contains("\"schemaVersion\" : 1") || diskJSON.contains("\"schemaVersion\": 1"))
    }

    @MainActor
    @Test func storeFallsBackForMissingSchemaWithoutSaving() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "missing-schema.json"
        let legacyJSON = """
        {
            "projectName": "Legacy Project",
            "viewportOffset": {"width": 0, "height": 0},
            "viewportScale": 1.0,
            "nodes": []
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: persistence.fileURL(for: fileName))

        let fallbackNode = SpatialNode(type: .miniApp, position: .zero, title: "Mini-App", miniApp: MiniAppState(codeText: "<h1>Fallback</h1>"))
        _ = ProjectStore(
            fileName: fileName,
            projectName: "Fallback Project",
            initialNodes: [fallbackNode],
            persistence: persistence
        )

        let diskJSON = String(data: try Data(contentsOf: persistence.fileURL(for: fileName)), encoding: .utf8) ?? ""
        #expect(!diskJSON.contains("schemaVersion"))
    }

    @Test func persistenceSaveLoadRoundTrip() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let fileName = "roundtrip.json"
        let snapshot = ProjectSnapshot(
            projectName: "Round Trip",
            nodes: [
                SpatialNode(type: .miniApp, position: CGPoint(x: 12, y: 24), title: "Mini-App", miniApp: MiniAppState(codeText: "<h1>Hello</h1>"))
            ],
            viewportOffset: CGSize(width: 10, height: 20),
            viewportScale: 0.75
        )

        try persistence.save(snapshot, fileName: fileName)
        let loaded = try persistence.load(fileName: fileName)

        #expect(loaded == snapshot)
        #expect(loaded.schemaVersion == ProjectPersistenceService.currentSchemaVersion)
    }

    @Test func legacyNodeActionStringDecodesToNil() throws {
        let original = SpatialNode(type: .standard, position: .zero, title: "Launcher", action: nil)
        var data = try JSONEncoder().encode(original)
        var jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        jsonObject["action"] = "createNewProject"
        data = try JSONSerialization.data(withJSONObject: jsonObject)
        let decoded = try JSONDecoder().decode(SpatialNode.self, from: data)
        #expect(decoded.action == nil)
    }

    @Test func canvasFileNamingMigratesLegacyFileNames() {
        #expect(CanvasFileNaming.migrateLegacyFileName("project_abc12345.json") == "canvas_abc12345.json")
        #expect(CanvasFileNaming.migrateLegacyFileName("canvas_abc12345.json") == "canvas_abc12345.json")
    }

    @Test func canvasFileNamingResolvesLegacyFallback() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let legacy = "project_deadbeef.json"
        try persistence.save(
            ProjectSnapshot(projectName: "Legacy", nodes: [], viewportOffset: .zero, viewportScale: 1.0),
            fileName: legacy
        )

        let resolved = CanvasFileNaming.resolveExistingFileName("canvas_deadbeef.json", persistence: persistence)
        #expect(resolved == legacy)
    }

    @MainActor
    @Test func canvasWorkspaceMigrationRenamesFilesAndRewritesLinks() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let migrationKey = "canvasWorkspaceMigration_v1_complete"
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }
        UserDefaults.standard.removeObject(forKey: migrationKey)

        let legacyLinked = "project_abc12345.json"
        let subCanvasNode = SpatialNode(
            type: .subCanvas,
            position: .zero,
            title: "Child",
            linkedCanvasFileName: legacyLinked
        )
        let launcher = SpatialNode(type: .standard, position: .zero, title: "Settings", action: .openSettings)
        let rootSnapshot = ProjectSnapshot(
            projectName: "Root",
            nodes: [subCanvasNode, launcher],
            viewportOffset: .zero,
            viewportScale: 1.0
        )
        try persistence.save(rootSnapshot, fileName: CanvasFileNaming.rootFileName)
        try persistence.save(
            ProjectSnapshot(projectName: "Child", nodes: [], viewportOffset: .zero, viewportScale: 1.0),
            fileName: legacyLinked
        )

        #expect(persistence.projectExists(fileName: legacyLinked))
        #expect(!persistence.projectExists(fileName: "canvas_abc12345.json"))

        CanvasWorkspaceMigration.runIfNeeded(persistence: persistence)

        #expect(!persistence.projectExists(fileName: legacyLinked))
        #expect(persistence.projectExists(fileName: "canvas_abc12345.json"))

        let root = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(root.nodes.first(where: { $0.title == "Child" })?.linkedCanvasFileName == "canvas_abc12345.json")
        #expect(root.nodes.first(where: { $0.title == "Settings" })?.action == .openSettings)
    }

    @Test func curatedRootMigrationResetsRootOnceAndSeedsChildCanvases() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let defaults = try #require(UserDefaults(suiteName: "CuratedRootCanvasMigrationTests.reset"))
        defer { defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.reset") }
        defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.reset")

        try persistence.save(
            ProjectSnapshot(
                projectName: "Old Root",
                nodes: [SpatialNode(position: .zero, title: "Old Node")],
                viewportOffset: CGSize(width: 42, height: 24),
                viewportScale: 1
            ),
            fileName: CanvasFileNaming.rootFileName
        )

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes == RootCanvasProvider.nodes)
        #expect(migratedRoot.viewportOffset == .zero)
        #expect(migratedRoot.viewportScale == RootCanvasProvider.defaultViewportScale)
        #expect(persistence.projectExists(fileName: RootCanvasProvider.tutorialFileName))
        #expect(persistence.projectExists(fileName: RootCanvasProvider.xoFileName))

        let customizedRoot = ProjectSnapshot(
            projectName: "Customized",
            nodes: [SpatialNode(position: .zero, title: "My Node")],
            viewportOffset: .zero,
            viewportScale: 1
        )
        try persistence.save(customizedRoot, fileName: CanvasFileNaming.rootFileName)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)
        let preservedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(preservedRoot == customizedRoot)
    }

    @Test func curatedRootMigrationPreservesExistingChildCanvases() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let defaults = try #require(UserDefaults(suiteName: "CuratedRootCanvasMigrationTests.children"))
        defer { defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.children") }
        defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.children")

        let customizedPacMan = ProjectSnapshot(
            projectName: "Customized Pac-Man",
            nodes: [SpatialNode(position: .zero, title: "Keep Me")],
            viewportOffset: .zero,
            viewportScale: 1
        )
        try persistence.save(customizedPacMan, fileName: RootCanvasProvider.pacManFileName)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let preservedPacMan = try persistence.load(fileName: RootCanvasProvider.pacManFileName)
        #expect(preservedPacMan == customizedPacMan)
    }

    @Test func activityMigrationNoLongerAppendsActivityNodeToCustomizedRoot() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.activity.custom"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let customNode = SpatialNode(
            position: CGPoint(x: 125, y: 700),
            title: "My Custom Root Node"
        )
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: [customNode],
                viewportOffset: .zero,
                viewportScale: 0.5
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migrated = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        let preserved = try #require(migrated.nodes.first(where: { $0.id == customNode.id }))

        #expect(preserved.position == customNode.position)
        #expect(!migrated.nodes.contains(where: { $0.id == RootCanvasProvider.activityNodeID }))
        #expect(!migrated.nodes.contains(where: { $0.id == RootCanvasProvider.dailyNodeID }))
    }

    @Test func curatedRootMigrationUpdatesLegacyConstellationToVerticalLayout() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let defaults = try #require(UserDefaults(suiteName: "CuratedRootCanvasMigrationTests.vertical"))
        defer { defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.vertical") }
        defaults.removePersistentDomain(forName: "CuratedRootCanvasMigrationTests.vertical")

        let legacyNodes = [
            SpatialNode(
                id: RootCanvasProvider.tutorialNodeID,
                type: .subCanvas,
                position: .zero,
                title: "Tutorial",
                subtitle: "Learn CAOCAP by using it",
                icon: "graduationcap.fill",
                theme: .green,
                linkedCanvasFileName: RootCanvasProvider.tutorialFileName
            ),
            SpatialNode(
                id: RootCanvasProvider.proNodeID,
                position: CGPoint(x: 0, y: -300),
                title: "Pro Subscription",
                subtitle: "Unlock CoCaptain & Premium Features",
                icon: "crown.fill",
                theme: .indigo,
                action: .proSubscription
            ),
            SpatialNode(
                id: RootCanvasProvider.profileNodeID,
                position: CGPoint(x: -250, y: -150),
                title: "Profile",
                subtitle: "Account & Preferences",
                icon: "person.crop.circle.fill",
                theme: .blue,
                action: .openProfile
            ),
            SpatialNode(
                id: RootCanvasProvider.pacManNodeID,
                type: .subCanvas,
                position: CGPoint(x: 250, y: -150),
                title: "Pac-Man",
                subtitle: "A mobile-ready Mini-App",
                icon: "gamecontroller.fill",
                theme: .purple,
                linkedCanvasFileName: RootCanvasProvider.pacManFileName
            ),
            SpatialNode(
                id: RootCanvasProvider.settingsNodeID,
                position: CGPoint(x: -250, y: 150),
                title: "Settings",
                subtitle: "App Tools & Config",
                icon: "gearshape.fill",
                theme: .orange,
                action: .openSettings
            )
        ]

        try persistence.save(
            ProjectSnapshot(projectName: "Root", nodes: legacyNodes, viewportOffset: .zero, viewportScale: 0.5),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        let positionsByID = Dictionary(uniqueKeysWithValues: migratedRoot.nodes.map { ($0.id, $0.position) })
        let expectedPositions = Dictionary(
            uniqueKeysWithValues: legacyNodes.enumerated().map { index, node in
                (node.id, RootCanvasProvider.verticalColumnPosition(index: index, count: legacyNodes.count))
            }
        )
        #expect(positionsByID == expectedPositions)
    }

    @Test func curatedRootMigrationUpdatesActivityFirstLayoutToLaunchLayout() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.launch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let count = 6
        let spacing: CGFloat = 220
        let startY = -CGFloat(count - 1) * spacing / 2
        let previousNodes = [
            SpatialNode(
                id: RootCanvasProvider.activityNodeID,
                position: CGPoint(x: 0, y: startY),
                title: "Activity",
                subtitle: "Saved changes across all canvases",
                icon: "chart.bar.xaxis",
                theme: .green
            ),
            SpatialNode(
                id: RootCanvasProvider.profileNodeID,
                position: CGPoint(x: 0, y: startY + spacing),
                title: "Profile",
                subtitle: "Account & Preferences",
                icon: "person.crop.circle.fill",
                theme: .blue,
                action: .openProfile
            ),
            SpatialNode(
                id: RootCanvasProvider.proNodeID,
                position: CGPoint(x: 0, y: startY + spacing * 2),
                title: "Pro Subscription",
                subtitle: "Unlock CoCaptain & Premium Features",
                icon: "crown.fill",
                theme: .indigo,
                action: .proSubscription
            ),
            SpatialNode(
                id: RootCanvasProvider.settingsNodeID,
                position: CGPoint(x: 0, y: startY + spacing * 3),
                title: "Settings",
                subtitle: "App Tools & Config",
                icon: "gearshape.fill",
                theme: .orange,
                action: .openSettings
            ),
            SpatialNode(
                id: RootCanvasProvider.tutorialNodeID,
                type: .subCanvas,
                position: CGPoint(x: 0, y: startY + spacing * 4),
                title: "Tutorial",
                subtitle: "Learn CAOCAP by using it",
                icon: "graduationcap.fill",
                theme: .green,
                linkedCanvasFileName: RootCanvasProvider.tutorialFileName
            ),
            SpatialNode(
                id: RootCanvasProvider.pacManNodeID,
                type: .subCanvas,
                position: CGPoint(x: 0, y: startY + spacing * 5),
                title: "Pac-Man",
                subtitle: "A mobile-ready Mini-App",
                icon: "gamecontroller.fill",
                theme: .purple,
                linkedCanvasFileName: RootCanvasProvider.pacManFileName
            )
        ]

        try persistence.save(
            ProjectSnapshot(projectName: "Root", nodes: previousNodes, viewportOffset: .zero, viewportScale: 0.5),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        let expectedNodes = [
            RootCanvasProvider.proNodeID,
            RootCanvasProvider.settingsNodeID,
            RootCanvasProvider.profileNodeID,
            RootCanvasProvider.tutorialNodeID,
            RootCanvasProvider.pacManNodeID
        ].compactMap { id in
            RootCanvasProvider.legacyCuratedNodes.first(where: { $0.id == id })
        }
        #expect(migratedRoot.nodes.map(\.id) == expectedNodes.map(\.id))
        #expect(migratedRoot.nodes.map(\.position) == expectedNodes.map(\.position))
        #expect(migratedRoot.nodes.map(\.theme) == expectedNodes.map(\.theme))
    }

    @Test func curatedRootMigrationRemovesDailyAndActivityNodes() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.daily.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retained = RootCanvasProvider.legacyCuratedNodes.filter {
            $0.id != RootCanvasProvider.xoNodeID
        }
        var nodes = retained
        nodes.append(
            SpatialNode(
                id: RootCanvasProvider.activityNodeID,
                position: CGPoint(x: -250, y: 330),
                title: "Activity",
                icon: "chart.bar.xaxis",
                theme: .cyan
            )
        )
        nodes.append(
            SpatialNode(
                id: RootCanvasProvider.dailyNodeID,
                position: CGPoint(x: 250, y: 330),
                title: "Daily",
                icon: "rosette",
                theme: .indigo
            )
        )
        try persistence.save(
            ProjectSnapshot(projectName: "Root", nodes: nodes, viewportOffset: .zero, viewportScale: 0.5),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(!migratedRoot.nodes.contains(where: { $0.id == RootCanvasProvider.activityNodeID }))
        #expect(!migratedRoot.nodes.contains(where: { $0.id == RootCanvasProvider.dailyNodeID }))
        #expect(Set(migratedRoot.nodes.map(\.id)) == Set(retained.map(\.id)))
    }

    @Test func curatedRootMigrationUpdatesVerticalColumnToConstellationLayout() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.constellation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preGridNodes = RootCanvasProvider.legacyCuratedNodes.filter {
            $0.id != RootCanvasProvider.xoNodeID &&
                $0.id != RootCanvasProvider.whatsAppNodeID &&
                $0.id != RootCanvasProvider.helpNodeID &&
                $0.id != RootCanvasProvider.appIconNodeID
        }
        let verticalNodes = preGridNodes.enumerated().map { index, node -> SpatialNode in
            var updated = node
            updated.position = RootCanvasProvider.verticalColumnPosition(
                index: index,
                count: preGridNodes.count
            )
            return updated
        }
        try persistence.save(
            ProjectSnapshot(projectName: "Root", nodes: verticalNodes, viewportOffset: .zero, viewportScale: 0.5),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.count == preGridNodes.count)
        #expect(migratedRoot.nodes.map(\.id) == preGridNodes.map(\.id))
        #expect(
            Dictionary(uniqueKeysWithValues: migratedRoot.nodes.map { ($0.id, $0.position) }) ==
                Dictionary(uniqueKeysWithValues: preGridNodes.compactMap { node in
                    guard let position = RootCanvasProvider.legacyConstellationPosition(for: node.id) else {
                        return nil
                    }
                    return (node.id, position)
                })
        )
    }

    @Test func curatedRootMigrationInstallsXOAndGridLayoutFromConstellation() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.grid.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let constellationNodes = RootCanvasProvider.legacyCuratedNodes
            .filter {
                $0.id != RootCanvasProvider.xoNodeID &&
                    $0.id != RootCanvasProvider.whatsAppNodeID &&
                    $0.id != RootCanvasProvider.helpNodeID &&
                    $0.id != RootCanvasProvider.appIconNodeID
            }
            .map { node -> SpatialNode in
                var updated = node
                updated.position = RootCanvasProvider.legacyConstellationPosition(for: node.id) ?? node.position
                return updated
            }
        try persistence.save(
            ProjectSnapshot(projectName: "Root", nodes: constellationNodes, viewportOffset: .zero, viewportScale: 0.5),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.map(\.id) == RootCanvasProvider.legacyCuratedNodes.map(\.id))
        #expect(migratedRoot.nodes.map(\.position) == RootCanvasProvider.legacyCuratedNodes.map(\.position))
        #expect(persistence.projectExists(fileName: RootCanvasProvider.xoFileName))
    }

    @Test func curatedRootMigrationUpdatesDefaultViewportScaleOnCanonicalGrid() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.viewport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: RootCanvasProvider.nodes,
                viewportOffset: .zero,
                viewportScale: 0.5
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes == RootCanvasProvider.nodes)
        #expect(migratedRoot.viewportScale == RootCanvasProvider.defaultViewportScale)
        #expect(migratedRoot.viewportOffset == .zero)
    }

    @Test func curatedRootMigrationInstallsHelpNodeOnCanonicalGridWithWhatsApp() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.help.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preHelpNodes = RootCanvasProvider.legacyCuratedNodes.filter { $0.id != RootCanvasProvider.helpNodeID }
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: preHelpNodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.map(\.id) == RootCanvasProvider.legacyCuratedNodes.map(\.id))
        #expect(migratedRoot.nodes.map(\.position) == RootCanvasProvider.legacyCuratedNodes.map(\.position))
    }

    @Test func curatedRootMigrationRepositionsLegacyBottomAnchorsToTopAndBottom() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.anchors.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyNodes = RootCanvasProvider.legacyCuratedNodes.map { node -> SpatialNode in
            var updated = node
            if node.id == RootCanvasProvider.whatsAppNodeID {
                updated.position = CGPoint(x: 0, y: 550)
            } else if node.id == RootCanvasProvider.helpNodeID {
                updated.position = CGPoint(x: -125, y: 550)
            }
            return updated
        }
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: legacyNodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.map(\.position) == RootCanvasProvider.legacyCuratedNodes.map(\.position))
    }

    @Test func curatedRootMigrationInstallsAppIconNodeOnCanonicalGridWithAnchors() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.appIcon.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preAppIconNodes = RootCanvasProvider.legacyCuratedNodes.filter { $0.id != RootCanvasProvider.appIconNodeID }
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: preAppIconNodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(Set(migratedRoot.nodes.map(\.id)) == RootCanvasProvider.legacyCuratedNodeIDs)
        #expect(
            Dictionary(uniqueKeysWithValues: migratedRoot.nodes.map { ($0.id, $0.position) }) ==
                Dictionary(uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes.map { ($0.id, $0.position) })
        )
    }

    @Test func curatedRootMigrationRepositionsProfileAndAppIconOnLegacyLayout() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.profileAppIcon.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyNodes = RootCanvasProvider.legacyCuratedNodes.map { node -> SpatialNode in
            var updated = node
            if node.id == RootCanvasProvider.profileNodeID {
                updated.position = RootCanvasProvider.gridPosition(column: 0, row: 2)
            } else if node.id == RootCanvasProvider.appIconNodeID {
                updated.position = CGPoint(x: -250, y: RootCanvasProvider.topAnchorY)
            }
            return updated
        }
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: legacyNodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.map(\.position) == RootCanvasProvider.legacyCuratedNodes.map(\.position))
    }

    @Test func curatedRootMigrationRepositionsWhatsAppFromTopCenterToTopRight() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.whatsAppTopRight.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyNodes = RootCanvasProvider.legacyCuratedNodes.map { node -> SpatialNode in
            var updated = node
            if node.id == RootCanvasProvider.whatsAppNodeID {
                updated.position = CGPoint(x: 0, y: RootCanvasProvider.topAnchorY)
            }
            return updated
        }
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: legacyNodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey)

        defaults.set(true, forKey: CuratedRootCanvasMigration.removeDailyActivityCompleteKey)
        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        let whatsApp = try #require(
            migratedRoot.nodes.first { $0.id == RootCanvasProvider.whatsAppNodeID }
        )
        #expect(whatsApp.position == CGPoint(x: 250, y: RootCanvasProvider.topAnchorY))
        #expect(migratedRoot.nodes.map(\.position) == RootCanvasProvider.legacyCuratedNodes.map(\.position))
        #expect(defaults.bool(forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey))
    }


    @Test func curatedRootMigrationReplacesLegacyGridWithPacManOnly() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.pacManOnly.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: RootCanvasProvider.legacyCuratedNodes,
                viewportOffset: .zero,
                viewportScale: 0.45
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes == RootCanvasProvider.nodes)
        #expect(migratedRoot.viewportScale == RootCanvasProvider.defaultViewportScale)
        #expect(migratedRoot.viewportOffset == .zero)
        #expect(defaults.bool(forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey))
    }

    @Test func curatedRootMigrationPreservesUserNodesWhenInstallingPacManOnly() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let persistence = ProjectPersistenceService(baseDirectory: tempDirectory)
        let suiteName = "CuratedRootCanvasMigrationTests.pacManOnly.user.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userNode = SpatialNode(position: CGPoint(x: 80, y: 120), title: "My Canvas Node")
        var mixed = RootCanvasProvider.legacyCuratedNodes
        mixed.append(userNode)
        try persistence.save(
            ProjectSnapshot(
                projectName: "Root",
                nodes: mixed,
                viewportOffset: .zero,
                viewportScale: 0.45
            ),
            fileName: CanvasFileNaming.rootFileName
        )
        defaults.set(true, forKey: CuratedRootCanvasMigration.migrationCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.verticalLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.activityNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.dailyNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.constellationLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.xoGridLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchViewportScaleCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.helpNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.launchAnchorLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.appIconNodeCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.profileAppIconLayoutCompleteKey)
        defaults.set(true, forKey: CuratedRootCanvasMigration.whatsAppTopRightLayoutCompleteKey)

        CuratedRootCanvasMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let migratedRoot = try persistence.load(fileName: CanvasFileNaming.rootFileName)
        #expect(migratedRoot.nodes.map(\.id) == mixed.map(\.id))
        #expect(migratedRoot.nodes.contains(where: { $0.id == userNode.id }))
        #expect(defaults.bool(forKey: CuratedRootCanvasMigration.pacManOnlyRootCompleteKey))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("caocap-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
