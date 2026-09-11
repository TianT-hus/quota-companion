import Foundation

/// Explicit QA opt-in; normal launches retain the existing data and defaults domains.
public enum IsolatedRuntime {
    public static let directory: URL? = {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_COMPANION_TEST_ROOT"] else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard path.hasPrefix("/"), path.utf8.count < 85,
              FileManager.default.fileExists(atPath: url.appendingPathComponent(".quota-isolated").path) else {
            fatalError("QA root must be an absolute, short directory containing .quota-isolated")
        }
        return url
    }()
    public static var enabled: Bool { directory != nil }
}

/// QA preferences stay in the selected directory, never in the user's app domain.
public final class IsolatedDefaults: UserDefaults, @unchecked Sendable {
    private let file: URL
    private var values: [String: Any]
    public init(directory: URL) throws {
        file = directory.appendingPathComponent("preferences.plist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file) {
            values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        } else { values = [:] }
        super.init(suiteName: "quota-companion-isolated-readonly")!
    }
    public override func object(forKey key: String) -> Any? { values[key] }
    public override func string(forKey key: String) -> String? { values[key] as? String }
    public override func data(forKey key: String) -> Data? { values[key] as? Data }
    public override func bool(forKey key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    public override func integer(forKey key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
    public override func double(forKey key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    public override func set(_ value: Any?, forKey key: String) {
        values[key] = value
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try data.write(to: file, options: .atomic)
        } catch { fatalError("Could not save isolated QA preferences") }
    }
    public override func set(_ value: Bool, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    public override func set(_ value: Int, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    public override func set(_ value: Double, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    public override func removeObject(forKey key: String) { set(nil, forKey: key) }
}
