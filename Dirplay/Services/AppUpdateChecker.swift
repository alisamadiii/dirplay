import Foundation
import Observation

/// Checks Apple's public iTunes Lookup API for a newer App Store version.
/// Fails open: no network, app not yet published, or store ≤ local all mean
/// the app keeps working normally.
@Observable @MainActor
final class AppUpdateChecker {
    private(set) var isUpdateRequired = false
    private(set) var storeVersion: String?
    private(set) var storeURL: URL?

    func check() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forceupdatetest") {
            storeVersion = "99.0"
            storeURL = URL(string: "https://apps.apple.com")
            isUpdateRequired = true
            return
        }
        #endif
        guard let bundleID = Bundle.main.bundleIdentifier,
              let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=us")
        else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let latest = results.first,
              let version = latest["version"] as? String
        else { return }
        if Self.isVersion(version, newerThan: localVersion) {
            storeVersion = version
            storeURL = (latest["trackViewUrl"] as? String).flatMap(URL.init(string:))
            isUpdateRequired = true
        }
    }

    /// Numeric segment compare: "1.10" > "1.9", "2.0" > "1.9.9".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
