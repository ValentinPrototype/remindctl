@preconcurrency import EventKit
import Foundation

public struct ManagedNoteFooterNormalizationSummary: Sendable, Equatable {
  public let scannedReminderCount: Int
  public let updatedReminderCount: Int

  public init(scannedReminderCount: Int, updatedReminderCount: Int) {
    self.scannedReminderCount = scannedReminderCount
    self.updatedReminderCount = updatedReminderCount
  }
}

public actor RemindersStore {
  private let eventStore = EKEventStore()
  private let calendar: Calendar

  public init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  public func requestAccess() async throws {
    let status = Self.authorizationStatus()
    switch status {
    case .notDetermined:
      let updated = try await requestAuthorization()
      if updated != .fullAccess {
        throw RemindCoreError.accessDenied
      }
    case .denied, .restricted:
      throw RemindCoreError.accessDenied
    case .writeOnly:
      throw RemindCoreError.writeOnlyAccess
    case .fullAccess:
      break
    }
  }

  public static func authorizationStatus() -> RemindersAuthorizationStatus {
    RemindersAuthorizationStatus(eventKitStatus: EKEventStore.authorizationStatus(for: .reminder))
  }

  public func requestAuthorization() async throws -> RemindersAuthorizationStatus {
    let status = Self.authorizationStatus()
    switch status {
    case .notDetermined:
      let granted = try await requestFullAccess()
      return granted ? .fullAccess : .denied
    default:
      return status
    }
  }

  public func lists() async -> [ReminderList] {
    eventStore.calendars(for: .reminder).map { calendar in
      ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
    }
  }

  public func defaultListName() -> String? {
    eventStore.defaultCalendarForNewReminders()?.title
  }

  public func reminders(in listName: String? = nil) async throws -> [ReminderItem] {
    let calendars = try calendars(for: listName)
    return await fetchReminders(in: calendars)
  }

  public func nativeReminders(in listName: String? = nil) async throws -> [NativeReminderRecord] {
    let calendars = try calendars(for: listName)
    return await fetchNativeReminders(in: calendars)
  }

  public func normalizeManagedNoteFooters(
    in listName: String? = nil
  ) async throws -> ManagedNoteFooterNormalizationSummary {
    let calendars = try calendars(for: listName)
    return try await normalizeManagedNoteFooters(in: calendars)
  }

  public func createList(name: String) async throws -> ReminderList {
    let list = EKCalendar(for: .reminder, eventStore: eventStore)
    list.title = name
    guard let source = eventStore.defaultCalendarForNewReminders()?.source else {
      throw RemindCoreError.operationFailed("Unable to determine default reminder source")
    }
    list.source = source
    try eventStore.saveCalendar(list, commit: true)
    return ReminderList(id: list.calendarIdentifier, title: list.title)
  }

  public func renameList(oldName: String, newName: String) async throws {
    let calendar = try calendar(named: oldName)
    guard calendar.allowsContentModifications else {
      throw RemindCoreError.operationFailed("Cannot modify system list")
    }
    calendar.title = newName
    try eventStore.saveCalendar(calendar, commit: true)
  }

  public func deleteList(name: String) async throws {
    let calendar = try calendar(named: name)
    guard calendar.allowsContentModifications else {
      throw RemindCoreError.operationFailed("Cannot delete system list")
    }
    try eventStore.removeCalendar(calendar, commit: true)
  }

  public func createReminder(_ draft: ReminderDraft, listName: String) async throws -> ReminderItem {
    let calendar = try calendar(named: listName)
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = draft.title
    reminder.notes = CanonicalNoteFooter.normalize(rawNotes: draft.notes).rawNotes
    reminder.calendar = calendar
    reminder.priority = draft.priority.eventKitValue
    if let dueDate = draft.dueDate {
      reminder.dueDateComponents = calendarComponents(from: dueDate)
    }
    try eventStore.save(reminder, commit: true)
    return item(from: reminder)
  }

  public func updateReminder(id: String, update: ReminderUpdate) async throws -> ReminderItem {
    let reminder = try reminder(withID: id)
    let existingNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)

    if let title = update.title {
      reminder.title = title
    }
    if let notes = update.notes {
      reminder.notes = CanonicalNoteFooter.normalize(
        rawNotes: notes,
        canonicalManagedID: existingNotes.canonicalManagedID
      ).rawNotes
    } else {
      reminder.notes = CanonicalNoteFooter.normalize(
        rawNotes: reminder.notes,
        canonicalManagedID: existingNotes.canonicalManagedID
      ).rawNotes
    }
    if let dueDateUpdate = update.dueDate {
      if let dueDate = dueDateUpdate {
        reminder.dueDateComponents = calendarComponents(from: dueDate)
      } else {
        reminder.dueDateComponents = nil
      }
    }
    if let priority = update.priority {
      reminder.priority = priority.eventKitValue
    }
    if let listName = update.listName {
      reminder.calendar = try calendar(named: listName)
    }
    if let isCompleted = update.isCompleted {
      reminder.isCompleted = isCompleted
    }

    try eventStore.save(reminder, commit: true)

    return item(from: reminder)
  }

  public func completeReminders(ids: [String]) async throws -> [ReminderItem] {
    var updated: [ReminderItem] = []
    for id in ids {
      let reminder = try reminder(withID: id)
      let existingNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)
      reminder.notes = CanonicalNoteFooter.normalize(
        rawNotes: reminder.notes,
        canonicalManagedID: existingNotes.canonicalManagedID
      ).rawNotes
      reminder.isCompleted = true
      try eventStore.save(reminder, commit: true)
      updated.append(item(from: reminder))
    }
    return updated
  }

  public func deleteReminders(ids: [String]) async throws -> Int {
    var deleted = 0
    for id in ids {
      let reminder = try reminder(withID: id)
      try eventStore.remove(reminder, commit: true)
      deleted += 1
    }
    return deleted
  }

  private func requestFullAccess() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.requestFullAccessToReminders { granted, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: granted)
      }
    }
  }

  private func fetchReminders(in calendars: [EKCalendar]) async -> [ReminderItem] {
    struct ReminderData: Sendable {
      let id: String
      let title: String
      let notes: String?
      let isCompleted: Bool
      let completionDate: Date?
      let priority: Int
      let dueDateComponents: DateComponents?
      let listID: String
      let listName: String
    }

    let reminderData = await withCheckedContinuation { (continuation: CheckedContinuation<[ReminderData], Never>) in
      let predicate = eventStore.predicateForReminders(in: calendars)
      eventStore.fetchReminders(matching: predicate) { reminders in
        let data = (reminders ?? []).map { reminder in
          let parsedNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)
          return ReminderData(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: parsedNotes.notesBody,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: Int(reminder.priority),
            dueDateComponents: reminder.dueDateComponents,
            listID: reminder.calendar.calendarIdentifier,
            listName: reminder.calendar.title
          )
        }
        continuation.resume(returning: data)
      }
    }

    return reminderData.map { data in
      ReminderItem(
        id: data.id,
        title: data.title,
        notes: data.notes,
        isCompleted: data.isCompleted,
        completionDate: data.completionDate,
        priority: ReminderPriority(eventKitValue: data.priority),
        dueDate: date(from: data.dueDateComponents),
        listID: data.listID,
        listName: data.listName
      )
    }
  }

  private func fetchNativeReminders(in calendars: [EKCalendar]) async -> [NativeReminderRecord] {
    struct ReminderData: Sendable {
      let sourceScopeID: String
      let calendarID: String
      let listTitle: String
      let title: String
      let noteFields: ManagedNoteFields
      let isCompleted: Bool
      let completionDate: Date?
      let priority: Int
      let dueDateComponents: DateComponents?
      let createdAt: Date?
      let updatedAt: Date?
      let url: String?
      let nativeCalendarItemIdentifier: String
      let nativeExternalIdentifier: String?
    }

    let reminderData = await withCheckedContinuation { (continuation: CheckedContinuation<[ReminderData], Never>) in
      let predicate = eventStore.predicateForReminders(in: calendars)
      eventStore.fetchReminders(matching: predicate) { reminders in
        let data = (reminders ?? []).compactMap { reminder -> ReminderData? in
          let sourceIdentifier = reminder.calendar.source.sourceIdentifier
          guard sourceIdentifier.isEmpty == false else {
            return nil
          }

          let parsedNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)
          return ReminderData(
            sourceScopeID: sourceIdentifier,
            calendarID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
            title: reminder.title ?? "",
            noteFields: ManagedNoteFields(parsedNotes: parsedNotes),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: Int(reminder.priority),
            dueDateComponents: reminder.dueDateComponents,
            createdAt: reminder.creationDate,
            updatedAt: reminder.lastModifiedDate,
            url: reminder.url?.absoluteString,
            nativeCalendarItemIdentifier: reminder.calendarItemIdentifier,
            nativeExternalIdentifier: reminder.calendarItemExternalIdentifier
          )
        }
        continuation.resume(returning: data)
      }
    }

    return reminderData.map { data in
      NativeReminderRecord(
        id: data.nativeCalendarItemIdentifier,
        sourceScopeID: data.sourceScopeID,
        calendarID: data.calendarID,
        listTitle: data.listTitle,
        title: data.title,
        noteFields: data.noteFields,
        isCompleted: data.isCompleted,
        completionDate: data.completionDate,
        priority: ReminderPriority(eventKitValue: data.priority),
        dueDate: date(from: data.dueDateComponents),
        createdAt: data.createdAt,
        updatedAt: data.updatedAt,
        url: data.url,
        nativeCalendarItemIdentifier: data.nativeCalendarItemIdentifier,
        nativeExternalIdentifier: data.nativeExternalIdentifier
      )
    }
  }

  private func normalizeManagedNoteFooters(
    in calendars: [EKCalendar]
  ) async throws -> ManagedNoteFooterNormalizationSummary {
    let reminderIDs = await fetchReminderIdentifiers(in: calendars)
    var updatedReminderCount = 0

    for reminderID in reminderIDs {
      let reminder = try reminder(withID: reminderID)
      let existingNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)
      let normalizedNotes = CanonicalNoteFooter.normalize(
        rawNotes: reminder.notes,
        canonicalManagedID: existingNotes.canonicalManagedID
      )
      if normalizedNotes.rawNotes != reminder.notes {
        reminder.notes = normalizedNotes.rawNotes
        try eventStore.save(reminder, commit: true)
        updatedReminderCount += 1
      }
    }

    return ManagedNoteFooterNormalizationSummary(
      scannedReminderCount: reminderIDs.count,
      updatedReminderCount: updatedReminderCount
    )
  }

  private func fetchReminderIdentifiers(in calendars: [EKCalendar]) async -> [String] {
    await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
      let predicate = eventStore.predicateForReminders(in: calendars)
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: (reminders ?? []).map(\.calendarItemIdentifier))
      }
    }
  }

  private func reminder(withID id: String) throws -> EKReminder {
    guard let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindCoreError.reminderNotFound(id)
    }
    return item
  }

  private func calendar(named name: String) throws -> EKCalendar {
    let calendars = eventStore.calendars(for: .reminder).filter { $0.title == name }
    guard let calendar = calendars.first else {
      throw RemindCoreError.listNotFound(name)
    }
    return calendar
  }

  private func calendars(for listName: String?) throws -> [EKCalendar] {
    if let listName {
      let calendars = eventStore.calendars(for: .reminder).filter { $0.title == listName }
      if calendars.isEmpty {
        throw RemindCoreError.listNotFound(listName)
      }
      return calendars
    }
    return eventStore.calendars(for: .reminder)
  }

  private func calendarComponents(from date: Date) -> DateComponents {
    calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
  }

  private func date(from components: DateComponents?) -> Date? {
    guard let components else { return nil }
    return calendar.date(from: components)
  }

  private func item(from reminder: EKReminder) -> ReminderItem {
    let parsedNotes = CanonicalNoteFooter.parse(rawNotes: reminder.notes)
    return ReminderItem(
      id: reminder.calendarItemIdentifier,
      title: reminder.title ?? "",
      notes: parsedNotes.notesBody,
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      priority: ReminderPriority(eventKitValue: Int(reminder.priority)),
      dueDate: date(from: reminder.dueDateComponents),
      listID: reminder.calendar.calendarIdentifier,
      listName: reminder.calendar.title
    )
  }
}
