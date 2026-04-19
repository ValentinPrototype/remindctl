import Foundation

public struct ReminderMutationTarget: Sendable, Equatable {
  public let reminderID: String
  public let canonicalManagedID: String

  public init(reminderID: String, canonicalManagedID: String) {
    self.reminderID = reminderID
    self.canonicalManagedID = canonicalManagedID
  }
}
