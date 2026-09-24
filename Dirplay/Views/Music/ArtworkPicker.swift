import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared "add a cover" flow: source dialog → Photos or Files → embed the
/// image into the audio file's own metadata → refresh the UI.
struct ArtworkPickerModifier: ViewModifier {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerViewModel.self) private var player
    let item: MediaItem?
    @Binding var isPresented: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isPickingFile = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Set Cover", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Choose from Photos") { isPhotoPickerPresented = true }
                Button("Choose from Files") { isPickingFile = true }
            } message: {
                Text("The image is saved inside the music file itself, so the cover travels with it.")
            }
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await embed(data)
                    }
                    photoItem = nil
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                guard let data else {
                    errorMessage = ArtworkEmbedError.invalidImage.localizedDescription
                    return
                }
                Task { await embed(data) }
            }
            .overlay {
                if isWorking {
                    ProgressView("Saving cover…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(
                "Couldn't Set Cover",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func embed(_ data: Data) async {
        guard let item else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await ArtworkEmbedder.embed(imageData: data, into: item.url)
            library.noteMetadataChanged(for: item.url)
            player.reloadMetadataForCurrentTrack()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

extension View {
    func artworkPicker(for item: MediaItem?, isPresented: Binding<Bool>) -> some View {
        modifier(ArtworkPickerModifier(item: item, isPresented: isPresented))
    }
}
