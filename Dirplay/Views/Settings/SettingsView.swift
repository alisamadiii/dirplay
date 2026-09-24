import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LibraryViewModel.self) private var library
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode = AppearanceMode.system
    @State private var isPickingFolder = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Folder", value: library.rootURL?.lastPathComponent ?? "None")
                    Button("Change Folder…") {
                        isPickingFolder = true
                    }
                    Button("Rescan Library") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        library.rescan()
                    }
                }
                Section("Appearance") {
                    Picker(selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon)
                                .tag(mode)
                        }
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                    .onChange(of: appearanceMode) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                } header: {
                    Text("About")
                } footer: {
                    Text("Dirplay is free, open source, and has no ads. Your files never leave your device — there is no database and no tracking.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    library.setRoot(url)
                }
            }
        }
        .miniPlayerInset()
    }
}
