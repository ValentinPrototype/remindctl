import Foundation
import Testing

@testable import remindctl

struct ShortcutAssetTests {
  @Test("Shortcut integration names remain stable")
  func shortcutNamesRemainStable() {
    #expect(ShortcutTagSearch.shortcutName == "remindctl - Search By Tag")
    #expect(ShortcutTagMutation.shortcutName == "remindctl - Mutate Tags")
  }

  @Test("Canonical search shortcut asset exists in Support/Shortcuts")
  func canonicalSearchShortcutAssetExists() throws {
    let data = try Data(contentsOf: supportShortcutURL)
    #expect(data.isEmpty == false)
  }

  @Test("Compatibility copy matches canonical search shortcut asset bytes")
  func compatibilityCopyMatchesCanonicalAsset() throws {
    let canonicalData = try Data(contentsOf: supportShortcutURL)
    let compatibilityData = try Data(contentsOf: compatibilityShortcutURL)

    #expect(canonicalData == compatibilityData)
  }

  private var supportShortcutURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Support/Shortcuts/remindctl - Search By Tag.shortcut")
  }

  private var compatibilityShortcutURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("remindctl - Search By Tag.shortcut")
  }
}
