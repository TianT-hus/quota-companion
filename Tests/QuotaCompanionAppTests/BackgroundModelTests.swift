import AppKit
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized)
@MainActor
struct BackgroundModelTests {
    private func finishImport(_ model: CompanionModel) async throws {
        for _ in 0..<250 {
            if !model.isImportingBackground { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Background import did not finish in 5 seconds")
    }

    @Test func failedImportPreservesSelectionAndRestorePreservesFilesAndOtherSettings() async throws {
        let suite = "quota-import-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        defaults.set("original-pet-path", forKey: "customMascotPath")
        defaults.set("en", forKey: "language")
        defaults.set(["display": ["x": 10, "y": 20]], forKey: "panelPositions")
        let original = defaults.dictionaryRepresentation()
        let store = SnapshotStore(directory: directory)
        let model = CompanionModel(defaults: defaults, store: store)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/QuotaCompanionApp/Resources/water-mascot.png")
        let originalData = try Data(contentsOf: source)
        model.importBackground(from: source)
        try await finishImport(model)
        let first = try #require(model.customBackgroundName)
        #expect(model.background != nil)
        #expect(defaults.string(forKey: "customMascotPath") == "original-pet-path")

        let corrupt = directory.appendingPathComponent("broken.png")
        try Data("broken".utf8).write(to: corrupt)
        model.importBackground(from: corrupt)
        try await finishImport(model)
        #expect(model.customBackgroundName == first)
        #expect(model.background != nil)
        #expect(!model.backgroundMessage.isEmpty)

        model.importBackground(from: source)
        try await finishImport(model)
        let second = try #require(model.customBackgroundName)
        #expect(first != second)
        let reloaded = CompanionModel(defaults: defaults, store: store)
        for _ in 0..<250 {
            if reloaded.background != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(reloaded.customBackgroundName == second && reloaded.background != nil)

        model.importBackground(from: source)
        model.restoreDefaultBackground()
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.customBackgroundName == nil && model.background == nil)
        #expect(defaults.string(forKey: "customBackgroundName") == nil)
        #expect(try Data(contentsOf: source) == originalData)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backgrounds/\(first)").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backgrounds/\(second)").path))
        for key in ["customMascotPath", "language", "panelPositions"] {
            #expect(NSDictionary(dictionary: [key: defaults.object(forKey: key)!]) == NSDictionary(dictionary: [key: original[key]!]))
        }
    }
}
