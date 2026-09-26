import SwiftUI

/// Non-dismissible gate shown when a newer version exists on the App Store.
/// The only way forward is the update button.
struct UpdateRequiredView: View {
    let storeURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("Update Required")
                .font(.title2.bold())
            Text("A new version of Dirplay is available. Please update to continue.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let storeURL {
                    UIApplication.shared.open(storeURL)
                }
            } label: {
                Text("Update Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    UpdateRequiredView(storeURL: nil)
}
