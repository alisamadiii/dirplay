import Foundation

extension TimeInterval {
    /// "3:42" or "1:07:15" for durations over an hour.
    var formattedTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
