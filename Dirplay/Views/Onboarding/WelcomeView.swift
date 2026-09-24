import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(LibraryViewModel.self) private var library
    @State private var isPickingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 20)
            Text("Welcome to Dirplay")
                .font(.largeTitle.bold())
            Text("Your files. Your music. No ads.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 20) {
                StepRow(
                    number: 1,
                    title: "Create a folder",
                    detail: "In the Files app, make a folder anywhere and name it whatever you like."
                )
                StepRow(
                    number: 2,
                    title: "Add Music and Video inside",
                    detail: "Inside it, create two folders named “Music” and “Video”. Organize them with as many subfolders as you want — Dirplay mirrors your structure exactly."
                )
                StepRow(
                    number: 3,
                    title: "Choose that folder",
                    detail: "Pick the folder below and your library appears instantly."
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isPickingFolder = true
            } label: {
                Text("Choose Folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(duration: 0.4)) {
                    library.setRoot(url)
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
