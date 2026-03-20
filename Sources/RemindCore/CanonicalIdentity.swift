import Foundation

public struct CanonicalizationPolicy: Sendable, Equatable {
  public let externallyValidatedSourceScopes: Set<String>

  public init(externallyValidatedSourceScopes: Set<String> = []) {
    self.externallyValidatedSourceScopes = externallyValidatedSourceScopes
  }

  public func canonicalIdentity(for reminder: NativeReminderRecord) -> CanonicalIdentity {
    if externallyValidatedSourceScopes.contains(reminder.sourceScopeID),
      let externalID = reminder.nativeExternalIdentifier,
      !externalID.isEmpty
    {
      return CanonicalIdentity(
        canonicalID: "external::\(reminder.sourceScopeID)::\(externalID)",
        identityStatus: .canonicalExternal
      )
    }

    return CanonicalIdentity(
      canonicalID: "local::\(reminder.sourceScopeID)::\(reminder.nativeCalendarItemIdentifier)",
      identityStatus: .localOnlyUnstable
    )
  }
}
