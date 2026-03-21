import Foundation

public struct CanonicalizationPolicy: Sendable, Equatable {
  public init() {}

  public func canonicalIdentity(for reminder: NativeReminderRecord) -> CanonicalIdentity {
    if let canonicalManagedID = reminder.canonicalManagedID {
      return CanonicalIdentity(
        canonicalID: "managed::\(canonicalManagedID)",
        identityStatus: .canonicalManaged
      )
    }

    if reminder.footerState == .invalid {
      return CanonicalIdentity(
        canonicalID: "footer-invalid::\(reminder.sourceScopeID)::\(reminder.nativeCalendarItemIdentifier)",
        identityStatus: .footerInvalid
      )
    }

    return CanonicalIdentity(
      canonicalID: "footer-missing::\(reminder.sourceScopeID)::\(reminder.nativeCalendarItemIdentifier)",
      identityStatus: .footerInvalid
    )
  }
}
