import Foundation
import OSLog

/// Owns the complete human-in-the-loop lifecycle for CoCaptain review work.
///
/// Model-output validation and timeline rendering remain outside this module.
/// Staging is side-effect free: only an explicit approval may perform an app action.
@MainActor
public final class CoCaptainReviewLifecycle {
    public struct Draft: Hashable {
        public let pendingActions: [CoCaptainAgentAction]

        public init(pendingActions: [CoCaptainAgentAction] = []) {
            self.pendingActions = pendingActions
        }

        public var isEmpty: Bool {
            pendingActions.isEmpty
        }
    }

    /// One Review Bundle in an active lifecycle session.
    ///
    /// The bundle identifier is the single identity used by the lifecycle,
    /// timeline, and node persistence.
    public struct Record: Identifiable, Hashable, Codable {
        public var id: UUID { bundle.id }
        public var bundle: ReviewBundleItem
        public let createdAt: Date

        public init(bundle: ReviewBundleItem, createdAt: Date = Date()) {
            self.bundle = bundle
            self.createdAt = createdAt
        }

        private enum CodingKeys: String, CodingKey {
            case timelineItemID
            case bundle
            case createdAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedBundle = try container.decode(ReviewBundleItem.self, forKey: .bundle)
            let legacyTimelineItemID = try container.decodeIfPresent(
                UUID.self,
                forKey: .timelineItemID
            )
            let canonicalID = legacyTimelineItemID ?? decodedBundle.id
            bundle = ReviewBundleItem(
                id: canonicalID,
                title: decodedBundle.title,
                items: decodedBundle.items
            )
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .timelineItemID)
            try container.encode(bundle, forKey: .bundle)
            try container.encode(createdAt, forKey: .createdAt)
        }
    }

    public enum Decision: Hashable {
        case approve(itemID: UUID)
        case reject(itemID: UUID)
        case approveAll
        case rejectAll
    }

    /// Ordered domain effects emitted by a successful lifecycle transition.
    public enum Effect: Hashable {
        case appActionPerformed(itemID: UUID, result: AppActionResult)
        case rejected(itemID: UUID)
        case conflicted(itemID: UUID, description: String)
    }

    public struct Transition: Hashable {
        public let record: Record
        public let effects: [Effect]

        public init(record: Record, effects: [Effect]) {
            self.record = record
            self.effects = effects
        }
    }

    /// Failures caused by invalid caller input. Operational application
    /// failures are represented as terminal conflicted review items instead.
    public enum Failure: Error, Hashable, LocalizedError {
        case bundleNotFound(UUID)
        case itemNotFound(UUID)
        case decisionNotAllowed(itemID: UUID, status: ReviewItemStatus)

        public var errorDescription: String? {
            switch self {
            case .bundleNotFound:
                return "The Review Bundle is no longer available."
            case .itemNotFound:
                return "The review item is no longer available."
            case .decisionNotAllowed:
                return "That review decision is not available for the item's current status."
            }
        }
    }

    @MainActor
    public final class Session {
        public private(set) var records: [Record]

        public var hasUnresolvedReviews: Bool {
            records.contains { record in
                record.bundle.items.contains { $0.status.isUnresolved }
            }
        }

        private let scope: CoCaptainAgentScope
        private let store: ProjectStore?
        private var dispatcher: (any AppActionPerforming)?
        private let logger = Logger(
            subsystem: "com.caocap.CoCaptainReviewLifecycle",
            category: "Session"
        )

        fileprivate init(
            scope: CoCaptainAgentScope,
            store: ProjectStore?,
            dispatcher: (any AppActionPerforming)?
        ) {
            self.scope = scope
            self.store = store
            self.dispatcher = dispatcher
            self.records = []
            restorePersistedRecords()
        }

        func updateDispatcher(_ dispatcher: (any AppActionPerforming)?) {
            self.dispatcher = dispatcher
        }

        /// Converts a validated typed draft into a Review Bundle without
        /// performing a pending app action.
        @discardableResult
        public func stage(_ draft: Draft, createdAt: Date = Date()) -> Record? {
            guard !draft.isEmpty else { return nil }

            let items = draft.pendingActions.map(stageAction)
            guard !items.isEmpty else { return nil }

            let bundle = ReviewBundleItem(
                title: reviewBundleTitle(for: items),
                items: items
            )
            let record = Record(bundle: bundle, createdAt: createdAt)
            records.append(record)
            persist(record)
            return record
        }

        /// Applies one explicit user decision. Invalid caller input leaves the
        /// record unchanged and returns a typed failure.
        @discardableResult
        public func resolve(
            _ decision: Decision,
            in bundleID: UUID
        ) -> Result<Transition, Failure> {
            guard let recordIndex = records.firstIndex(where: { $0.id == bundleID }) else {
                return .failure(.bundleNotFound(bundleID))
            }

            if case .node = scope {
                guard let persistedRecord = currentPersistedRecords()
                    .first(where: { $0.id == bundleID }) else {
                    return .failure(.bundleNotFound(bundleID))
                }
                records[recordIndex] = persistedRecord
            }

            var record = records[recordIndex]
            let result: Result<[Effect], Failure>

            switch decision {
            case .approve(let itemID):
                result = approve(
                    itemID: itemID,
                    in: &record,
                    createsCheckpoint: true
                )
            case .reject(let itemID):
                result = reject(itemID: itemID, in: &record)
            case .approveAll:
                result = approveAll(in: &record)
            case .rejectAll:
                result = rejectAll(in: &record)
            }

            switch result {
            case .failure(let failure):
                return .failure(failure)
            case .success(let effects):
                records[recordIndex] = record
                persist(record)
                return .success(Transition(record: record, effects: effects))
            }
        }

        /// Clears active records and node-scoped persisted Review Bundles.
        public func clear() {
            records.removeAll()
            replacePersistedRecords(with: [])
        }

        /// Rebinds the in-memory Review Bundles when the user switches between
        /// project conversations. Node sessions continue to restore exclusively
        /// from `NodeAgentState` so their persistence contract is unchanged.
        public func restoreProjectRecords(_ records: [Record]) {
            guard case .project = scope else { return }
            self.records = records
        }

        private func stageAction(_ action: CoCaptainAgentAction) -> PendingReviewItem {
            guard let actionID = AppActionID(rawValue: action.actionID) else {
                let reason = LocalizationManager.shared.localizedString(
                    "Unknown pending action id `%@`.",
                    arguments: [action.actionID]
                )
                return unavailableActionItem(action: action, reason: reason)
            }
            guard let definition = dispatcher?.definition(for: actionID) else {
                let reason = LocalizationManager.shared.localizedString(
                    "Pending action `%@` is not available in the current context.",
                    arguments: [action.actionID]
                )
                return unavailableActionItem(action: action, reason: reason)
            }

            return PendingReviewItem(
                targetLabel: definition.localizedTitle,
                summary: LocalizationManager.shared.localizedString(
                    "Awaiting approval to run %@.",
                    arguments: [definition.localizedTitle]
                ),
                preview: actionPreview(for: action, definition: definition),
                source: .appAction(actionID, action.args)
            )
        }

        private func unavailableActionItem(
            action: CoCaptainAgentAction,
            reason: String
        ) -> PendingReviewItem {
            PendingReviewItem(
                targetLabel: action.actionID,
                summary: LocalizationManager.shared.localizedString(
                    "The assistant proposed an action that could not be staged for review."
                ),
                preview: reason,
                status: .conflicted,
                source: .unavailableAction(actionID: action.actionID, reason: reason),
                conflictDescription: reason
            )
        }

        private func approve(
            itemID: UUID,
            in record: inout Record,
            createsCheckpoint: Bool
        ) -> Result<[Effect], Failure> {
            guard let itemIndex = record.bundle.items.firstIndex(where: { $0.id == itemID }) else {
                return .failure(.itemNotFound(itemID))
            }
            guard record.bundle.items[itemIndex].status == .pending else {
                return .failure(
                    .decisionNotAllowed(
                        itemID: itemID,
                        status: record.bundle.items[itemIndex].status
                    )
                )
            }

            if createsCheckpoint {
                store?.createCheckpoint(
                    label: "Apply Suggestion: \(record.bundle.items[itemIndex].targetLabel)"
                )
            }
            let effects = applyPendingItem(&record.bundle.items[itemIndex])
            return .success(effects)
        }

        private func reject(
            itemID: UUID,
            in record: inout Record
        ) -> Result<[Effect], Failure> {
            guard let itemIndex = record.bundle.items.firstIndex(where: { $0.id == itemID }) else {
                return .failure(.itemNotFound(itemID))
            }
            guard record.bundle.items[itemIndex].status.isUnresolved else {
                return .failure(
                    .decisionNotAllowed(
                        itemID: itemID,
                        status: record.bundle.items[itemIndex].status
                    )
                )
            }

            record.bundle.items[itemIndex].status = .rejected
            return .success([.rejected(itemID: itemID)])
        }

        private func approveAll(in record: inout Record) -> Result<[Effect], Failure> {
            let pendingItemIDs = record.bundle.items
                .filter { $0.status == .pending }
                .map(\.id)
            if !pendingItemIDs.isEmpty {
                store?.createCheckpoint(label: "Apply All Changes")
            }

            var effects: [Effect] = []
            for itemID in pendingItemIDs {
                guard let itemIndex = record.bundle.items.firstIndex(where: { $0.id == itemID }) else {
                    continue
                }
                effects.append(contentsOf: applyPendingItem(&record.bundle.items[itemIndex]))
            }
            return .success(effects)
        }

        private func rejectAll(in record: inout Record) -> Result<[Effect], Failure> {
            var effects: [Effect] = []
            for itemIndex in record.bundle.items.indices
            where record.bundle.items[itemIndex].status.isUnresolved {
                let itemID = record.bundle.items[itemIndex].id
                record.bundle.items[itemIndex].status = .rejected
                effects.append(.rejected(itemID: itemID))
            }
            return .success(effects)
        }

        private func applyPendingItem(_ item: inout PendingReviewItem) -> [Effect] {
            switch item.source {
            case .appAction(let actionID, let arguments):
                guard let dispatcher,
                      dispatcher.definition(for: actionID) != nil else {
                    return conflict(
                        &item,
                        description: LocalizationManager.shared.localizedString(
                            "This action is no longer available."
                        )
                    )
                }
                let result = dispatcher.perform(
                    actionID,
                    source: .agentApproved,
                    arguments: arguments
                )
                guard result.executed else {
                    return conflict(&item, description: result.message)
                }
                item.status = .applied
                item.conflictDescription = nil
                return [.appActionPerformed(itemID: item.id, result: result)]

            case .unavailableAction(_, let reason):
                return conflict(&item, description: reason)
            }
        }

        private func conflict(
            _ item: inout PendingReviewItem,
            description: String
        ) -> [Effect] {
            item.status = .conflicted
            item.conflictDescription = description
            return [.conflicted(itemID: item.id, description: description)]
        }

        private func actionPreview(
            for action: CoCaptainAgentAction,
            definition: AppActionDefinition
        ) -> String {
            guard let arguments = action.args, !arguments.isEmpty else {
                return definition.localizedTitle
            }
            let formattedArguments = arguments
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            return "\(definition.localizedTitle)\n\(formattedArguments)"
        }

        private func reviewBundleTitle(for items: [PendingReviewItem]) -> String {
            let base = LocalizationManager.shared.localizedString("Pending changes")
            guard items.count > 1 else { return base }
            return LocalizationManager.shared.localizedString(
                "Pending changes (%lld)",
                arguments: [Int64(items.count)]
            )
        }

        private func restorePersistedRecords() {
            guard case .node(let nodeID) = scope,
                  let store,
                  let node = store.nodes.first(where: { $0.id == nodeID }) else {
                return
            }

            let decoded = decodePersistedRecords(
                from: node.agentState.pendingReviewBundlesData
            )
            records = decoded.records
            if decoded.needsNormalization {
                replacePersistedRecords(with: records)
            }
        }

        /// Upserts only the transitioned record against the latest persisted
        /// state so independent lifecycle sessions cannot delete one another's
        /// Review Bundles. Terminal records are removed rather than encoded.
        private func persist(_ record: Record) {
            guard case .node = scope else { return }

            var persistedRecords = currentPersistedRecords()
            persistedRecords.removeAll { $0.id == record.id }
            if record.bundle.items.contains(where: { $0.status.isUnresolved }) {
                persistedRecords.append(record)
            }
            persistedRecords.sort { $0.createdAt < $1.createdAt }
            replacePersistedRecords(with: persistedRecords)
        }

        private func currentPersistedRecords() -> [Record] {
            guard case .node(let nodeID) = scope,
                  let store,
                  let node = store.nodes.first(where: { $0.id == nodeID }) else {
                return []
            }
            return decodePersistedRecords(
                from: node.agentState.pendingReviewBundlesData
            ).records
        }

        private func decodePersistedRecords(
            from encodedRecords: [Data]
        ) -> (records: [Record], needsNormalization: Bool) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var decodedRecords: [Record] = []
            var needsNormalization = false

            for data in encodedRecords {
                do {
                    let persisted = try decoder.decode(
                        CoCaptainPersistedReviewRecord.self,
                        from: data
                    )
                    let canonicalBundle = ReviewBundleItem(
                        id: persisted.timelineItemID,
                        title: persisted.bundle.title,
                        items: persisted.bundle.items
                    )
                    let record = Record(
                        bundle: canonicalBundle,
                        createdAt: persisted.createdAt
                    )
                    guard record.bundle.items.contains(where: { $0.status.isUnresolved }) else {
                        needsNormalization = true
                        continue
                    }
                    if persisted.bundle.id != record.id {
                        needsNormalization = true
                    }
                    if let existingIndex = decodedRecords.firstIndex(where: { $0.id == record.id }) {
                        decodedRecords[existingIndex] = record
                        needsNormalization = true
                    } else {
                        decodedRecords.append(record)
                    }
                } catch {
                    needsNormalization = true
                    logger.error(
                        "Skipping a corrupted persisted Review Bundle: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            return (decodedRecords, needsNormalization)
        }

        private func replacePersistedRecords(with persistedRecords: [Record]) {
            // Node-scoped review persistence was removed with legacy node actions.
        }
    }

    public init() {}

    public func session(
        scope: CoCaptainAgentScope,
        store: ProjectStore?,
        dispatcher: (any AppActionPerforming)?
    ) -> Session {
        Session(
            scope: scope,
            store: store,
            dispatcher: dispatcher
        )
    }

    /// Constant-time persistence query used by canvas rendering.
    ///
    /// The lifecycle invariant is that only unresolved records are encoded;
    /// restoration removes terminal, duplicate, legacy-misaligned, or corrupt
    /// entries before writing normalized persistence.
    nonisolated static func hasUnresolvedPersistedRecords(
        in agentState: NodeAgentState
    ) -> Bool {
        !agentState.pendingReviewBundlesData.isEmpty
    }
}

private struct CoCaptainPersistedReviewRecord: Codable {
    let timelineItemID: UUID
    let bundle: ReviewBundleItem
    let createdAt: Date

    @MainActor
    init(record: CoCaptainReviewLifecycle.Record) {
        timelineItemID = record.id
        bundle = record.bundle
        createdAt = record.createdAt
    }
}
