import Foundation

public enum AcquisitionSourceKind: String, Codable, Sendable, CaseIterable {
  case nativeEventKit = "native_eventkit"
  case shortcut = "shortcut"
}

public enum IdentityStatus: String, Codable, Sendable, CaseIterable {
  case canonicalExternal = "canonical_external"
  case localOnlyUnstable = "local_only_unstable"
  case shortcutUnresolved = "shortcut_unresolved"
  case collisionUnresolved = "collision_unresolved"
}

public enum QueryConfidence: String, Codable, Sendable, CaseIterable {
  case high
  case medium
  case low
}

public enum QueryExecutionStatus: String, Codable, Sendable, CaseIterable {
  case ok
  case empty
  case unsupported
  case sourceError = "source_error"
}

public enum GTDDueFilter: String, Codable, Sendable, CaseIterable {
  case any
  case overdue
  case today
  case none
}

public enum ValidationGateID: String, Codable, CaseIterable, Sendable {
  case g1TagVisibility = "G1"
  case g2HierarchyVisibility = "G2"
  case g3ShortcutIdentifier = "G3"
  case g4ExternalIDReliability = "G4"
  case g5LastModifiedReliability = "G5"

  public var title: String {
    switch self {
    case .g1TagVisibility:
      return "Tag visibility gate"
    case .g2HierarchyVisibility:
      return "Hierarchy visibility gate"
    case .g3ShortcutIdentifier:
      return "Shortcut identifier gate"
    case .g4ExternalIDReliability:
      return "External-ID reliability gate"
    case .g5LastModifiedReliability:
      return "Last-modified reliability gate"
    }
  }

  public var summary: String {
    switch self {
    case .g1TagVisibility:
      return "Required before tag-based semantic queries may ship."
    case .g2HierarchyVisibility:
      return "Required before hierarchy-derived diagnostics may ship."
    case .g3ShortcutIdentifier:
      return "Controls whether Shortcut payloads may be promoted into canonical joins."
    case .g4ExternalIDReliability:
      return "Controls whether external identifiers may be preferred over local IDs."
    case .g5LastModifiedReliability:
      return "Controls whether native updated-at logic may be trusted."
    }
  }
}

public enum ValidationGateState: String, Codable, CaseIterable, Sendable {
  case pending
  case passed
  case failed
}

public struct ValidationGateRecord: Codable, Sendable, Equatable {
  public let gateID: ValidationGateID
  public let state: ValidationGateState
  public let updatedAt: Date
  public let evidence: String?

  public init(
    gateID: ValidationGateID,
    state: ValidationGateState,
    updatedAt: Date,
    evidence: String?
  ) {
    self.gateID = gateID
    self.state = state
    self.updatedAt = updatedAt
    self.evidence = evidence
  }
}

public enum ShortcutContractID: String, Codable, CaseIterable, Sendable {
  case activeProjects = "shortcut.active_projects.v1"
  case nextActions = "shortcut.next_actions.v1"
  case waitingOns = "shortcut.waiting_ons.v1"
  case productivityHierarchy = "shortcut.productivity_hierarchy.v1"
  case productivityRecentlyUpdated = "shortcut.productivity_recently_updated.v1"

  public static let requiredV1Contracts: [ShortcutContractID] = [
    .activeProjects,
    .nextActions,
    .waitingOns,
    .productivityHierarchy,
  ]

  public var deployedShortcutName: String {
    switch self {
    case .activeProjects:
      return "OC GTD: Active Projects"
    case .nextActions:
      return "OC GTD: Next Actions"
    case .waitingOns:
      return "OC GTD: Waiting-Ons"
    case .productivityHierarchy:
      return "OC GTD: Productivity Hierarchy"
    case .productivityRecentlyUpdated:
      return "OC GTD: Productivity Recently Updated"
    }
  }

  public var fixtureBaseName: String {
    switch self {
    case .activeProjects:
      return "shortcut.active_projects.v1"
    case .nextActions:
      return "shortcut.next_actions.v1"
    case .waitingOns:
      return "shortcut.waiting_ons.v1"
    case .productivityHierarchy:
      return "shortcut.productivity_hierarchy.v1"
    case .productivityRecentlyUpdated:
      return "shortcut.productivity_recently_updated.v1"
    }
  }

  public var sourceQueryFamily: String {
    switch self {
    case .activeProjects:
      return "active-projects"
    case .nextActions:
      return "next-actions"
    case .waitingOns:
      return "waiting-ons"
    case .productivityHierarchy:
      return "productivity-hierarchy"
    case .productivityRecentlyUpdated:
      return "productivity-recently-updated"
    }
  }
}

public enum ShortcutContractRunStatus: String, Codable, Sendable, CaseIterable {
  case ok
  case empty
  case error
}

public struct ContractDiagnostic: Codable, Sendable, Equatable {
  public let code: String
  public let message: String
  public let retryable: Bool?

  public init(code: String, message: String, retryable: Bool? = nil) {
    self.code = code
    self.message = message
    self.retryable = retryable
  }
}

public struct NativeReminderRecord: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let sourceKind: AcquisitionSourceKind
  public let sourceScopeID: String
  public let calendarID: String
  public let listTitle: String
  public let title: String
  public let notes: String?
  public let isCompleted: Bool
  public let completionDate: Date?
  public let priority: ReminderPriority
  public let dueDate: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let url: String?
  public let nativeCalendarItemIdentifier: String
  public let nativeExternalIdentifier: String?

  public init(
    id: String,
    sourceKind: AcquisitionSourceKind = .nativeEventKit,
    sourceScopeID: String,
    calendarID: String,
    listTitle: String,
    title: String,
    notes: String?,
    isCompleted: Bool,
    completionDate: Date?,
    priority: ReminderPriority,
    dueDate: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    url: String?,
    nativeCalendarItemIdentifier: String,
    nativeExternalIdentifier: String?
  ) {
    self.id = id
    self.sourceKind = sourceKind
    self.sourceScopeID = sourceScopeID
    self.calendarID = calendarID
    self.listTitle = listTitle
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.priority = priority
    self.dueDate = dueDate
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.url = url
    self.nativeCalendarItemIdentifier = nativeCalendarItemIdentifier
    self.nativeExternalIdentifier = nativeExternalIdentifier
  }
}

public struct CanonicalIdentity: Sendable, Equatable {
  public let canonicalID: String
  public let identityStatus: IdentityStatus

  public init(canonicalID: String, identityStatus: IdentityStatus) {
    self.canonicalID = canonicalID
    self.identityStatus = identityStatus
  }
}

public struct ShortcutContractItem: Codable, Sendable, Equatable {
  public let sourceItemID: String
  public let nativeCalendarItemIdentifier: String?
  public let nativeExternalIdentifier: String?
  public let title: String
  public let notes: String?
  public let listTitle: String
  public let isCompleted: Bool
  public let priority: ReminderPriority
  public let dueAt: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let url: String?
  public let matchedSemantics: [String]
  public let observedTags: [String]?
  public let parentSourceItemID: String?
  public let childSourceItemIDs: [String]

  public init(
    sourceItemID: String,
    nativeCalendarItemIdentifier: String?,
    nativeExternalIdentifier: String?,
    title: String,
    notes: String?,
    listTitle: String,
    isCompleted: Bool,
    priority: ReminderPriority,
    dueAt: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    url: String?,
    matchedSemantics: [String],
    observedTags: [String]?,
    parentSourceItemID: String?,
    childSourceItemIDs: [String]
  ) {
    self.sourceItemID = sourceItemID
    self.nativeCalendarItemIdentifier = nativeCalendarItemIdentifier
    self.nativeExternalIdentifier = nativeExternalIdentifier
    self.title = title
    self.notes = notes
    self.listTitle = listTitle
    self.isCompleted = isCompleted
    self.priority = priority
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.url = url
    self.matchedSemantics = matchedSemantics
    self.observedTags = observedTags
    self.parentSourceItemID = parentSourceItemID
    self.childSourceItemIDs = childSourceItemIDs
  }
}

public struct ValidatedShortcutContractPayload: Codable, Sendable, Equatable {
  public let contractID: ShortcutContractID
  public let contractVersion: String
  public let generatedAt: Date
  public let status: ShortcutContractRunStatus
  public let items: [ShortcutContractItem]
  public let warnings: [ContractDiagnostic]
  public let errors: [ContractDiagnostic]

  public init(
    contractID: ShortcutContractID,
    contractVersion: String,
    generatedAt: Date,
    status: ShortcutContractRunStatus,
    items: [ShortcutContractItem],
    warnings: [ContractDiagnostic],
    errors: [ContractDiagnostic]
  ) {
    self.contractID = contractID
    self.contractVersion = contractVersion
    self.generatedAt = generatedAt
    self.status = status
    self.items = items
    self.warnings = warnings
    self.errors = errors
  }
}

public struct CanonicalReminderRecord: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let canonicalID: String
  public let identityStatus: IdentityStatus
  public let sourceScopeID: String
  public let calendarID: String
  public let listTitle: String
  public let title: String
  public let notes: String?
  public let isCompleted: Bool
  public let completionDate: Date?
  public let priority: ReminderPriority
  public let dueDate: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let url: String?
  public let nativeCalendarItemIdentifier: String?
  public let nativeExternalIdentifier: String?
  public let matchedSemantics: [String]
  public let observedTags: [String]
  public let acquisitionSources: [String]
  public let lastNativeSyncAt: Date?
  public let lastSemanticSyncAt: Date?

  public init(
    id: String,
    canonicalID: String,
    identityStatus: IdentityStatus,
    sourceScopeID: String,
    calendarID: String,
    listTitle: String,
    title: String,
    notes: String?,
    isCompleted: Bool,
    completionDate: Date?,
    priority: ReminderPriority,
    dueDate: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    url: String?,
    nativeCalendarItemIdentifier: String?,
    nativeExternalIdentifier: String?,
    matchedSemantics: [String],
    observedTags: [String],
    acquisitionSources: [String],
    lastNativeSyncAt: Date?,
    lastSemanticSyncAt: Date?
  ) {
    self.id = id
    self.canonicalID = canonicalID
    self.identityStatus = identityStatus
    self.sourceScopeID = sourceScopeID
    self.calendarID = calendarID
    self.listTitle = listTitle
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.priority = priority
    self.dueDate = dueDate
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.url = url
    self.nativeCalendarItemIdentifier = nativeCalendarItemIdentifier
    self.nativeExternalIdentifier = nativeExternalIdentifier
    self.matchedSemantics = matchedSemantics
    self.observedTags = observedTags
    self.acquisitionSources = acquisitionSources
    self.lastNativeSyncAt = lastNativeSyncAt
    self.lastSemanticSyncAt = lastSemanticSyncAt
  }
}

public struct UnresolvedShortcutRecord: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let contractID: ShortcutContractID
  public let sourceItemID: String
  public let identityStatus: IdentityStatus
  public let nativeCalendarItemIdentifier: String?
  public let nativeExternalIdentifier: String?
  public let title: String
  public let notes: String?
  public let listTitle: String
  public let isCompleted: Bool
  public let priority: ReminderPriority
  public let dueAt: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let url: String?
  public let matchedSemantics: [String]
  public let observedTags: [String]
  public let parentSourceItemID: String?
  public let childSourceItemIDs: [String]
  public let insertedAt: Date

  public init(
    id: String,
    contractID: ShortcutContractID,
    sourceItemID: String,
    identityStatus: IdentityStatus,
    nativeCalendarItemIdentifier: String?,
    nativeExternalIdentifier: String?,
    title: String,
    notes: String?,
    listTitle: String,
    isCompleted: Bool,
    priority: ReminderPriority,
    dueAt: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    url: String?,
    matchedSemantics: [String],
    observedTags: [String],
    parentSourceItemID: String?,
    childSourceItemIDs: [String],
    insertedAt: Date
  ) {
    self.id = id
    self.contractID = contractID
    self.sourceItemID = sourceItemID
    self.identityStatus = identityStatus
    self.nativeCalendarItemIdentifier = nativeCalendarItemIdentifier
    self.nativeExternalIdentifier = nativeExternalIdentifier
    self.title = title
    self.notes = notes
    self.listTitle = listTitle
    self.isCompleted = isCompleted
    self.priority = priority
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.url = url
    self.matchedSemantics = matchedSemantics
    self.observedTags = observedTags
    self.parentSourceItemID = parentSourceItemID
    self.childSourceItemIDs = childSourceItemIDs
    self.insertedAt = insertedAt
  }
}

public struct QueryFreshness: Codable, Sendable, Equatable {
  public let evaluatedAt: Date
  public let nativeSyncedAt: Date?
  public let shortcutGeneratedAt: Date?

  public init(evaluatedAt: Date, nativeSyncedAt: Date?, shortcutGeneratedAt: Date?) {
    self.evaluatedAt = evaluatedAt
    self.nativeSyncedAt = nativeSyncedAt
    self.shortcutGeneratedAt = shortcutGeneratedAt
  }
}

public struct GTDQueryItem: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let sourceItemID: String?
  public let canonicalID: String?
  public let identityStatus: IdentityStatus
  public let title: String
  public let notes: String?
  public let listTitle: String
  public let isCompleted: Bool
  public let priority: ReminderPriority
  public let dueAt: Date?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let matchedSemantics: [String]
  public let observedTags: [String]
  public let acquisitionSources: [String]
  public let parentSourceItemID: String?
  public let parentCanonicalID: String?
  public let childSourceItemIDs: [String]
  public let childCanonicalIDs: [String]

  public init(
    id: String,
    sourceItemID: String? = nil,
    canonicalID: String?,
    identityStatus: IdentityStatus,
    title: String,
    notes: String?,
    listTitle: String,
    isCompleted: Bool,
    priority: ReminderPriority,
    dueAt: Date?,
    createdAt: Date?,
    updatedAt: Date?,
    matchedSemantics: [String],
    observedTags: [String],
    acquisitionSources: [String],
    parentSourceItemID: String? = nil,
    parentCanonicalID: String? = nil,
    childSourceItemIDs: [String] = [],
    childCanonicalIDs: [String] = []
  ) {
    self.id = id
    self.sourceItemID = sourceItemID
    self.canonicalID = canonicalID
    self.identityStatus = identityStatus
    self.title = title
    self.notes = notes
    self.listTitle = listTitle
    self.isCompleted = isCompleted
    self.priority = priority
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.matchedSemantics = matchedSemantics
    self.observedTags = observedTags
    self.acquisitionSources = acquisitionSources
    self.parentSourceItemID = parentSourceItemID
    self.parentCanonicalID = parentCanonicalID
    self.childSourceItemIDs = childSourceItemIDs
    self.childCanonicalIDs = childCanonicalIDs
  }
}

public struct GTDQueryResult: Codable, Sendable, Equatable {
  public let queryFamily: String
  public let status: QueryExecutionStatus
  public let confidence: QueryConfidence
  public let freshness: QueryFreshness
  public let acquisitionSources: [String]
  public let identityStatuses: [IdentityStatus]
  public let warnings: [String]
  public let items: [GTDQueryItem]

  public init(
    queryFamily: String,
    status: QueryExecutionStatus,
    confidence: QueryConfidence,
    freshness: QueryFreshness,
    acquisitionSources: [String],
    identityStatuses: [IdentityStatus],
    warnings: [String],
    items: [GTDQueryItem]
  ) {
    self.queryFamily = queryFamily
    self.status = status
    self.confidence = confidence
    self.freshness = freshness
    self.acquisitionSources = acquisitionSources
    self.identityStatuses = identityStatuses
    self.warnings = warnings
    self.items = items
  }
}

public struct MirrorSyncSummary: Codable, Sendable, Equatable {
  public let databasePath: String
  public let nativeReminderCount: Int
  public let canonicalReminderCount: Int
  public let unresolvedShortcutCount: Int
  public let contractRunCount: Int
  public let completedAt: Date

  public init(
    databasePath: String,
    nativeReminderCount: Int,
    canonicalReminderCount: Int,
    unresolvedShortcutCount: Int,
    contractRunCount: Int,
    completedAt: Date
  ) {
    self.databasePath = databasePath
    self.nativeReminderCount = nativeReminderCount
    self.canonicalReminderCount = canonicalReminderCount
    self.unresolvedShortcutCount = unresolvedShortcutCount
    self.contractRunCount = contractRunCount
    self.completedAt = completedAt
  }
}
