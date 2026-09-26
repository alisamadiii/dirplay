import Foundation
import StoreKit
import SwiftUI

/// Asks for an App Store rating with the native prompt once the user is
/// clearly engaged (15 tracks played), at most once per app version.
/// The system further limits actual display to 3 times per year.
enum ReviewPrompter {
    private static let playCountKey = "reviewPlayCount"
    private static let requestedVersionKey = "reviewRequestedVersion"
    private static let playThreshold = 15

    @MainActor
    static func noteTrackPlayed(_ requestReview: RequestReviewAction) {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: playCountKey) + 1
        defaults.set(count, forKey: playCountKey)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard count >= playThreshold,
              defaults.string(forKey: requestedVersionKey) != version
        else { return }
        defaults.set(version, forKey: requestedVersionKey)
        requestReview()
    }
}
