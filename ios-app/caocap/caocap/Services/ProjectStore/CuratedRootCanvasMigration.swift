import Foundation
import OSLog

/// Installs the launch-ready root constellation once while leaving subsequent
/// user edits to the root and curated child canvases untouched.
enum CuratedRootCanvasMigration {
    static let migrationCompleteKey = "curatedRootCanvas_v1_complete"
    static let verticalLayoutCompleteKey = "curatedRootCanvas_v2_vertical_layout_complete"
    static let activityNodeCompleteKey = "curatedRootCanvas_v3_activity_complete"
    static let launchLayoutCompleteKey = "curatedRootCanvas_v4_launch_layout_complete"
    static let dailyNodeCompleteKey = "curatedRootCanvas_v5_daily_node_complete"
    static let constellationLayoutCompleteKey = "curatedRootCanvas_v6_constellation_layout_complete"
    static let xoGridLayoutCompleteKey = "curatedRootCanvas_v7_xo_grid_layout_complete"
    static let launchViewportScaleCompleteKey = "curatedRootCanvas_v8_launch_viewport_scale_complete"
    static let whatsAppNodeCompleteKey = "curatedRootCanvas_v9_whatsapp_node_complete"
    static let helpNodeCompleteKey = "curatedRootCanvas_v10_help_node_complete"
    static let launchAnchorLayoutCompleteKey = "curatedRootCanvas_v11_launch_anchor_layout_complete"
    static let appIconNodeCompleteKey = "curatedRootCanvas_v12_app_icon_node_complete"
    static let profileAppIconLayoutCompleteKey = "curatedRootCanvas_v13_profile_app_icon_layout_complete"
    static let whatsAppTopRightLayoutCompleteKey = "curatedRootCanvas_v14_whatsapp_top_right_layout_complete"
    static let pacManOnlyRootCompleteKey = "curatedRootCanvas_v15_pacman_only_complete"
    static let removeDailyActivityCompleteKey = "curatedRootCanvas_v16_remove_daily_activity_complete"
    private static let logger = Logger(subsystem: "com.caocap.app", category: "CuratedRootCanvasMigration")

    static func runIfNeeded(
        persistence: ProjectPersistenceService = ProjectPersistenceService(),
        defaults: UserDefaults = .standard
    ) {
        if !defaults.bool(forKey: migrationCompleteKey) {
            do {
                try seedIfMissing(
                    TutorialCanvasProvider.snapshot,
                    fileName: RootCanvasProvider.tutorialFileName,
                    persistence: persistence
                )
                try seedIfMissing(
                    XOCanvasProvider.snapshot,
                    fileName: RootCanvasProvider.xoFileName,
                    persistence: persistence
                )

                // This release intentionally replaces the old home workspace once.
                try persistence.save(RootCanvasProvider.snapshot, fileName: CanvasFileNaming.rootFileName)
                defaults.set(true, forKey: migrationCompleteKey)
                markLegacyLayoutMigrationsComplete(defaults: defaults)
                defaults.set(true, forKey: pacManOnlyRootCompleteKey)
                logger.info("Installed the curated root canvas.")
            } catch {
                logger.error("Failed to install the curated root canvas: \(error.localizedDescription)")
            }
        }

        if isPacManOnlyRoot(persistence: persistence) {
            markLegacyLayoutMigrationsComplete(defaults: defaults)
        }

        if !defaults.bool(forKey: verticalLayoutCompleteKey) {
            do {
                try refreshVerticalRootLayout(persistence: persistence)
                defaults.set(true, forKey: verticalLayoutCompleteKey)
                logger.info("Updated the curated root canvas to the vertical layout.")
            } catch {
                logger.error("Failed to update the curated root canvas layout: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: activityNodeCompleteKey) {
            // Activity node seeding retired — mark complete without installing.
            defaults.set(true, forKey: activityNodeCompleteKey)
        }

        if !defaults.bool(forKey: launchLayoutCompleteKey) {
            do {
                try refreshLaunchRootLayout(persistence: persistence)
                defaults.set(true, forKey: launchLayoutCompleteKey)
                logger.info("Updated the curated root canvas to the launch layout.")
            } catch {
                logger.error("Failed to update the curated root canvas launch layout: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: dailyNodeCompleteKey) {
            // Daily node seeding retired — mark complete without installing.
            defaults.set(true, forKey: dailyNodeCompleteKey)
        }

        if !defaults.bool(forKey: constellationLayoutCompleteKey) {
            do {
                try refreshConstellationRootLayout(persistence: persistence)
                defaults.set(true, forKey: constellationLayoutCompleteKey)
                logger.info("Updated the curated root canvas to the constellation layout.")
            } catch {
                logger.error("Failed to update the curated root canvas constellation layout: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: xoGridLayoutCompleteKey) {
            do {
                try installXOGridLayout(persistence: persistence)
                defaults.set(true, forKey: xoGridLayoutCompleteKey)
                logger.info("Installed the root XO node and grid layout.")
            } catch {
                logger.error("Failed to install the root XO node and grid layout: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: launchViewportScaleCompleteKey) {
            do {
                try refreshLaunchViewportScale(persistence: persistence)
                defaults.set(true, forKey: launchViewportScaleCompleteKey)
                logger.info("Updated the curated root canvas launch viewport scale.")
            } catch {
                logger.error("Failed to update the curated root canvas launch viewport scale: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: whatsAppNodeCompleteKey) {
            do {
                try installWhatsAppNode(persistence: persistence)
                defaults.set(true, forKey: whatsAppNodeCompleteKey)
                logger.info("Installed the root WhatsApp node.")
            } catch {
                logger.error("Failed to install the root WhatsApp node: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: helpNodeCompleteKey) {
            do {
                try installHelpNode(persistence: persistence)
                defaults.set(true, forKey: helpNodeCompleteKey)
                logger.info("Installed the root Help node.")
            } catch {
                logger.error("Failed to install the root Help node: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: launchAnchorLayoutCompleteKey) {
            do {
                try refreshLaunchAnchorLayout(persistence: persistence)
                defaults.set(true, forKey: launchAnchorLayoutCompleteKey)
                logger.info("Updated the curated root canvas launch anchor layout.")
            } catch {
                logger.error("Failed to update the curated root canvas launch anchor layout: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: appIconNodeCompleteKey) {
            do {
                try installAppIconNode(persistence: persistence)
                defaults.set(true, forKey: appIconNodeCompleteKey)
                logger.info("Installed the root App Icon node.")
            } catch {
                logger.error("Failed to install the root App Icon node: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: profileAppIconLayoutCompleteKey) {
            do {
                try refreshProfileAppIconLayout(persistence: persistence)
                defaults.set(true, forKey: profileAppIconLayoutCompleteKey)
                logger.info("Repositioned the root Profile and App Icon nodes.")
            } catch {
                logger.error("Failed to reposition the root Profile and App Icon nodes: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: whatsAppTopRightLayoutCompleteKey) {
            do {
                try refreshWhatsAppTopRightLayout(persistence: persistence)
                defaults.set(true, forKey: whatsAppTopRightLayoutCompleteKey)
                logger.info("Repositioned the root WhatsApp node to the top-right anchor.")
            } catch {
                logger.error("Failed to reposition the root WhatsApp node: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: pacManOnlyRootCompleteKey) {
            do {
                try refreshPacManOnlyRoot(persistence: persistence)
                defaults.set(true, forKey: pacManOnlyRootCompleteKey)
                logger.info("Replaced the curated root canvas with the Hello World Mini-App.")
            } catch {
                logger.error("Failed to install the Hello World launch root canvas: \(error.localizedDescription)")
            }
        }

        if !defaults.bool(forKey: removeDailyActivityCompleteKey) {
            do {
                try removeDailyAndActivityNodes(persistence: persistence)
                defaults.set(true, forKey: removeDailyActivityCompleteKey)
                logger.info("Removed Daily and Activity nodes from the root canvas.")
            } catch {
                logger.error("Failed to remove Daily and Activity nodes: \(error.localizedDescription)")
            }
        }
    }

    private static func refreshVerticalRootLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let constellationPositions: [UUID: CGPoint] = [
            RootCanvasProvider.tutorialNodeID: .zero,
            RootCanvasProvider.proNodeID: CGPoint(x: 0, y: -300),
            RootCanvasProvider.profileNodeID: CGPoint(x: -250, y: -150),
            RootCanvasProvider.pacManNodeID: CGPoint(x: 250, y: -150),
            RootCanvasProvider.settingsNodeID: CGPoint(x: -250, y: 150)
        ]
        let constellationIDs = Set(constellationPositions.keys)
        let isLegacyConstellation =
            Set(snapshot.nodes.map(\.id)) == constellationIDs &&
            snapshot.nodes.allSatisfy { constellationPositions[$0.id] == $0.position }
        guard isLegacyConstellation else { return }

        let positionsByID = Dictionary(
            uniqueKeysWithValues: snapshot.nodes.enumerated().map { index, node in
                (node.id, RootCanvasProvider.verticalColumnPosition(index: index, count: snapshot.nodes.count))
            }
        )
        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            var updated = node
            if let position = positionsByID[node.id] {
                updated.position = position
            }
            return updated
        }

        let updatedSnapshot = ProjectSnapshot(
            schemaVersion: snapshot.schemaVersion,
            projectName: snapshot.projectName,
            nodes: updatedNodes,
            viewportOffset: snapshot.viewportOffset,
            viewportScale: snapshot.viewportScale,
            checkpointLabel: snapshot.checkpointLabel
        )

        try persistence.save(updatedSnapshot, fileName: rootFileName)
    }

    /// Removes retired Daily and Activity action nodes from any root canvas that still has them.
    private static func removeDailyAndActivityNodes(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let removedIDs: Set<UUID> = [
            RootCanvasProvider.activityNodeID,
            RootCanvasProvider.dailyNodeID
        ]
        let updatedNodes = snapshot.nodes.filter { !removedIDs.contains($0.id) }
        guard updatedNodes.count != snapshot.nodes.count else { return }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Reorders the curated six-node column and refreshes launch themes when the
    /// root still matches the prior activity-first vertical layout.
    private static func refreshLaunchRootLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let launchLayoutIDs = Set(launchLayoutNodeIDs())
        guard Set(snapshot.nodes.map(\.id)) == launchLayoutIDs else { return }

        let previousPositions = activityFirstVerticalPositions()
        let hasPreviousLayout = snapshot.nodes.allSatisfy {
            previousPositions[$0.id] == $0.position
        }
        guard hasPreviousLayout else { return }

        let canonicalByID = Dictionary(uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes.map { ($0.id, $0) })
        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            guard let canonical = canonicalByID[node.id] else { return node }
            var updated = node
            updated.position = canonical.position
            updated.theme = canonical.theme
            return updated
        }
        let orderedNodes = RootCanvasProvider.legacyCuratedNodes.compactMap { canonical in
            updatedNodes.first(where: { $0.id == canonical.id })
        }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: orderedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    private static func activityFirstVerticalPositions() -> [UUID: CGPoint] {
        let count = 6
        let orderedIDs = [
            RootCanvasProvider.activityNodeID,
            RootCanvasProvider.profileNodeID,
            RootCanvasProvider.proNodeID,
            RootCanvasProvider.settingsNodeID,
            RootCanvasProvider.tutorialNodeID,
            RootCanvasProvider.pacManNodeID
        ]
        return Dictionary(
            uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
                (id, RootCanvasProvider.verticalColumnPosition(index: index, count: count))
            }
        )
    }

    private static func launchLayoutNodeIDs() -> [UUID] {
        [
            RootCanvasProvider.proNodeID,
            RootCanvasProvider.settingsNodeID,
            RootCanvasProvider.profileNodeID,
            RootCanvasProvider.activityNodeID,
            RootCanvasProvider.tutorialNodeID,
            RootCanvasProvider.pacManNodeID
        ]
    }

    private static func preGridRootNodeIDs() -> Set<UUID> {
        Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter {
                    $0.id != RootCanvasProvider.xoNodeID &&
                        $0.id != RootCanvasProvider.whatsAppNodeID &&
                        $0.id != RootCanvasProvider.helpNodeID &&
                        $0.id != RootCanvasProvider.appIconNodeID
                }
                .map(\.id)
        )
    }

    /// Repositions the seven-node vertical column into the centered two-column constellation.
    private static func refreshConstellationRootLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let preGridIDs = preGridRootNodeIDs()
        guard Set(snapshot.nodes.map(\.id)) == preGridIDs else { return }

        let preGridNodes = RootCanvasProvider.legacyCuratedNodes.filter {
            $0.id != RootCanvasProvider.xoNodeID &&
                $0.id != RootCanvasProvider.whatsAppNodeID &&
                $0.id != RootCanvasProvider.helpNodeID &&
                $0.id != RootCanvasProvider.appIconNodeID
        }
        let verticalPositions = Dictionary(
            uniqueKeysWithValues: preGridNodes.enumerated().map { index, node in
                (node.id, RootCanvasProvider.verticalColumnPosition(index: index, count: preGridNodes.count))
            }
        )
        let hasVerticalLayout = snapshot.nodes.allSatisfy { verticalPositions[$0.id] == $0.position }
        guard hasVerticalLayout else { return }

        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            var updated = node
            if let position = RootCanvasProvider.legacyConstellationPosition(for: node.id) {
                updated.position = position
            }
            return updated
        }
        let orderedNodes = preGridNodes.compactMap { canonical in
            updatedNodes.first(where: { $0.id == canonical.id })
        }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: orderedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Seeds the XO child canvas and upgrades the seven-node constellation to the launch grid.
    private static func installXOGridLayout(persistence: ProjectPersistenceService) throws {
        try seedIfMissing(
            XOCanvasProvider.snapshot,
            fileName: RootCanvasProvider.xoFileName,
            persistence: persistence
        )

        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        guard !snapshot.nodes.contains(where: { $0.id == RootCanvasProvider.xoNodeID }) else {
            return
        }

        let preGridIDs = preGridRootNodeIDs()
        guard Set(snapshot.nodes.map(\.id)) == preGridIDs else { return }

        let hasConstellationLayout = snapshot.nodes.allSatisfy {
            RootCanvasProvider.legacyConstellationPosition(for: $0.id) == $0.position
        }
        guard hasConstellationLayout else { return }

        let orderedNodes = RootCanvasProvider.legacyCuratedNodes.map { canonical -> SpatialNode in
            if let existing = snapshot.nodes.first(where: { $0.id == canonical.id }) {
                var updated = existing
                updated.position = canonical.position
                return updated
            }
            return canonical
        }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: orderedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Reframes the canonical eight-node grid when the root still uses the prior 0.5 launch zoom.
    private static func refreshLaunchViewportScale(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let canonicalIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.whatsAppNodeID }
                .map(\.id)
        )
        guard Set(snapshot.nodes.map(\.id)) == canonicalIDs else { return }

        let gridPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.whatsAppNodeID }
                .map { ($0.id, $0.position) }
        )
        let hasGridLayout = snapshot.nodes.allSatisfy { gridPositions[$0.id] == $0.position }
        guard hasGridLayout else { return }

        let hadDefaultViewport = snapshot.viewportScale == 0.5 && snapshot.viewportOffset == .zero
        guard hadDefaultViewport else { return }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: snapshot.nodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Appends the WhatsApp contact node when the root still matches the eight-node launch grid.
    private static func installWhatsAppNode(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        guard !snapshot.nodes.contains(where: { $0.id == RootCanvasProvider.whatsAppNodeID }) else {
            return
        }

        let gridNodeIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.whatsAppNodeID }
                .map(\.id)
        )
        guard Set(snapshot.nodes.map(\.id)) == gridNodeIDs else { return }

        let gridPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.whatsAppNodeID }
                .map { ($0.id, $0.position) }
        )
        let hasGridLayout = snapshot.nodes.allSatisfy { gridPositions[$0.id] == $0.position }
        guard hasGridLayout else { return }

        guard let whatsAppNode = RootCanvasProvider.legacyCuratedNodes.first(where: {
            $0.id == RootCanvasProvider.whatsAppNodeID
        }) else {
            return
        }

        var updatedNodes = snapshot.nodes
        updatedNodes.append(whatsAppNode)

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Appends the Help node when the root still matches the nine-node launch grid with WhatsApp.
    private static func installHelpNode(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        guard !snapshot.nodes.contains(where: { $0.id == RootCanvasProvider.helpNodeID }) else {
            return
        }

        let preHelpIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.helpNodeID }
                .map(\.id)
        )
        guard Set(snapshot.nodes.map(\.id)) == preHelpIDs else { return }

        let canonicalPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.helpNodeID }
                .map { ($0.id, $0.position) }
        )
        let hasCanonicalLayout = snapshot.nodes.allSatisfy { canonicalPositions[$0.id] == $0.position }
        guard hasCanonicalLayout else { return }

        guard let helpNode = RootCanvasProvider.legacyCuratedNodes.first(where: {
            $0.id == RootCanvasProvider.helpNodeID
        }) else {
            return
        }

        var updatedNodes = snapshot.nodes
        updatedNodes.append(helpNode)

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Appends the App Icon node when the root still matches the ten-node launch grid with anchors.
    private static func installAppIconNode(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        guard !snapshot.nodes.contains(where: { $0.id == RootCanvasProvider.appIconNodeID }) else {
            return
        }

        let preAppIconIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.appIconNodeID }
                .map(\.id)
        )
        guard Set(snapshot.nodes.map(\.id)) == preAppIconIDs else { return }

        let canonicalPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { $0.id != RootCanvasProvider.appIconNodeID }
                .map { ($0.id, $0.position) }
        )
        let hasCanonicalLayout = snapshot.nodes.allSatisfy { canonicalPositions[$0.id] == $0.position }
        guard hasCanonicalLayout else { return }

        guard let appIconNode = RootCanvasProvider.legacyCuratedNodes.first(where: {
            $0.id == RootCanvasProvider.appIconNodeID
        }) else {
            return
        }

        var updatedNodes = snapshot.nodes
        updatedNodes.append(appIconNode)

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Moves Profile to the top anchor beside WhatsApp and App Icon into the former Profile grid slot.
    private static func refreshProfileAppIconLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let canonicalByID = Dictionary(uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes.map { ($0.id, $0) })
        let canonicalIDs = Set(canonicalByID.keys)
        guard Set(snapshot.nodes.map(\.id)) == canonicalIDs else { return }

        let legacyProfilePosition = RootCanvasProvider.gridPosition(column: 0, row: 2)
        let legacyAppIconPosition = CGPoint(x: -250, y: RootCanvasProvider.topAnchorY)
        let profile = snapshot.nodes.first(where: { $0.id == RootCanvasProvider.profileNodeID })
        let appIcon = snapshot.nodes.first(where: { $0.id == RootCanvasProvider.appIconNodeID })
        guard profile?.position == legacyProfilePosition,
              appIcon?.position == legacyAppIconPosition else {
            return
        }

        let unmovedNodeIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter {
                    $0.id != RootCanvasProvider.profileNodeID &&
                        $0.id != RootCanvasProvider.appIconNodeID
                }
                .map(\.id)
        )
        let canonicalPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { unmovedNodeIDs.contains($0.id) }
                .map { ($0.id, $0.position) }
        )
        let hasCanonicalUnmovedLayout = snapshot.nodes
            .filter { unmovedNodeIDs.contains($0.id) }
            .allSatisfy { canonicalPositions[$0.id] == $0.position }
        guard hasCanonicalUnmovedLayout else { return }

        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            guard let canonical = canonicalByID[node.id] else { return node }
            var updated = node
            updated.position = canonical.position
            return updated
        }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Moves WhatsApp from the top-center anchor to the top-right, mirroring Profile.
    private static func refreshWhatsAppTopRightLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let legacyWhatsAppPosition = CGPoint(x: 0, y: RootCanvasProvider.topAnchorY)
        let targetPosition = RootCanvasProvider.gridPosition(for: RootCanvasProvider.whatsAppNodeID)

        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            guard node.id == RootCanvasProvider.whatsAppNodeID,
                  node.position == legacyWhatsAppPosition else {
                return node
            }
            var updated = node
            updated.position = targetPosition
            return updated
        }

        guard updatedNodes != snapshot.nodes else { return }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Repositions WhatsApp above the grid and Help below when anchors still use the prior bottom-row layout.
    private static func refreshLaunchAnchorLayout(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let canonicalByID = Dictionary(uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes.map { ($0.id, $0) })
        let canonicalIDs = Set(canonicalByID.keys)
        guard Set(snapshot.nodes.map(\.id)).isSubset(of: canonicalIDs) else { return }

        let gridNodeIDs = Set(
            RootCanvasProvider.legacyCuratedNodes
                .filter {
                    $0.id != RootCanvasProvider.whatsAppNodeID &&
                        $0.id != RootCanvasProvider.profileNodeID &&
                        $0.id != RootCanvasProvider.helpNodeID
                }
                .map(\.id)
        )
        let gridPositions: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: RootCanvasProvider.legacyCuratedNodes
                .filter { gridNodeIDs.contains($0.id) }
                .map { ($0.id, $0.position) }
        )
        let hasCanonicalGrid = snapshot.nodes
            .filter { gridNodeIDs.contains($0.id) }
            .allSatisfy { gridPositions[$0.id] == $0.position }
        guard hasCanonicalGrid else { return }

        let legacyBottomAnchorY = RootCanvasProvider.anchorRowYOffset
        let whatsApp = snapshot.nodes.first(where: { $0.id == RootCanvasProvider.whatsAppNodeID })
        let help = snapshot.nodes.first(where: { $0.id == RootCanvasProvider.helpNodeID })
        let hadLegacyWhatsApp = whatsApp?.position == CGPoint(x: 0, y: legacyBottomAnchorY)
        let hadLegacyHelp =
            help?.position == CGPoint(x: -125, y: legacyBottomAnchorY) ||
            help?.position == CGPoint(x: 0, y: legacyBottomAnchorY)
        guard hadLegacyWhatsApp || hadLegacyHelp else { return }

        let updatedNodes = snapshot.nodes.map { node -> SpatialNode in
            guard let canonical = canonicalByID[node.id] else { return node }
            var updated = node
            updated.position = canonical.position
            return updated
        }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: updatedNodes,
                viewportOffset: snapshot.viewportOffset,
                viewportScale: snapshot.viewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    /// Replaces a curated-only root with the single centered Hello World Mini-App.
    /// Skips roots that contain any user-created (non-curated) node ids.
    private static func refreshPacManOnlyRoot(persistence: ProjectPersistenceService) throws {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return }

        let snapshot = try persistence.load(fileName: rootFileName)
        let curatedIDs = RootCanvasProvider.legacyCuratedNodeIDs
        let launchMiniAppIDs = Set(RootCanvasProvider.nodes.map(\.id))

        // Already on the Hello World launch template.
        if Set(snapshot.nodes.map(\.id)) == launchMiniAppIDs,
           snapshot.nodes == RootCanvasProvider.nodes,
           snapshot.viewportScale == RootCanvasProvider.defaultViewportScale,
           snapshot.viewportOffset == .zero {
            return
        }

        // Preserve roots that include any user-created nodes.
        let rootIDs = Set(snapshot.nodes.map(\.id))
        guard rootIDs.isSubset(of: curatedIDs.union(launchMiniAppIDs)) else { return }

        try persistence.save(
            ProjectSnapshot(
                schemaVersion: snapshot.schemaVersion,
                projectName: snapshot.projectName,
                nodes: RootCanvasProvider.nodes,
                viewportOffset: .zero,
                viewportScale: RootCanvasProvider.defaultViewportScale,
                checkpointLabel: snapshot.checkpointLabel
            ),
            fileName: rootFileName
        )
    }

    private static func isPacManOnlyRoot(persistence: ProjectPersistenceService) -> Bool {
        let rootFileName = CanvasFileNaming.rootFileName
        guard persistence.projectExists(fileName: rootFileName) else { return false }
        guard let snapshot = try? persistence.load(fileName: rootFileName) else { return false }
        return Set(snapshot.nodes.map(\.id)) == Set(RootCanvasProvider.nodes.map(\.id))
    }

    private static func markLegacyLayoutMigrationsComplete(defaults: UserDefaults) {
        let keys = [
            verticalLayoutCompleteKey,
            activityNodeCompleteKey,
            launchLayoutCompleteKey,
            dailyNodeCompleteKey,
            constellationLayoutCompleteKey,
            xoGridLayoutCompleteKey,
            launchViewportScaleCompleteKey,
            whatsAppNodeCompleteKey,
            helpNodeCompleteKey,
            launchAnchorLayoutCompleteKey,
            appIconNodeCompleteKey,
            profileAppIconLayoutCompleteKey,
            whatsAppTopRightLayoutCompleteKey,
            removeDailyActivityCompleteKey
        ]
        for key in keys {
            defaults.set(true, forKey: key)
        }
    }

    private static func seedIfMissing(
        _ snapshot: ProjectSnapshot,
        fileName: String,
        persistence: ProjectPersistenceService
    ) throws {
        guard !persistence.projectExists(fileName: fileName) else { return }
        try persistence.save(snapshot, fileName: fileName)
    }
}
