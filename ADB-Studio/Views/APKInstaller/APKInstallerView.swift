import SwiftUI
import UniformTypeIdentifiers

struct APKInstallerView: View {
    @ObservedObject var viewModel: DeviceDetailViewModel
    @State private var isDragOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Install APK", systemImage: "app.badge.fill")
                .font(.headline)

            dropZone
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $viewModel.isInstallingAPK) {
            APKInstallSheet(viewModel: viewModel)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isDragOver ? .accentColor : .secondary)

                Text("Drop APK here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("or click to select")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .frame(height: 100)
        .contentShape(Rectangle())
        .onTapGesture {
            selectAPKFile()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    private func selectAPKFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.message = "Select an APK file to install"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.installAPK(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "apk" else { return }

            DispatchQueue.main.async {
                viewModel.installAPK(url: url)
            }
        }
        return true
    }
}

struct APKInstallSheet: View {
    @ObservedObject var viewModel: DeviceDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResult = false

    var body: some View {
        VStack(spacing: 20) {
            if let result = viewModel.apkInstallResult {
                resultView(result)
            } else {
                progressView
            }
        }
        .padding(30)
        .frame(minWidth: 300)
        .onChange(of: viewModel.apkInstallResult) { _, result in
            guard let result = result else { return }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showResult = true
            }

            if case .success = result {
                NSSound(named: "Glass")?.play()
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    viewModel.dismissAPKInstall()
                    dismiss()
                }
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("Installing APK...")
                .font(.headline)

            Text(viewModel.apkInstallProgress)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            Button("Cancel") {
                viewModel.cancelAPKInstall()
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
    }

    @ViewBuilder
    private func resultView(_ result: DeviceDetailViewModel.APKInstallResult) -> some View {
        switch result {
        case .success:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)
                    .scaleEffect(showResult ? 1 : 0.5)
                    .opacity(showResult ? 1 : 0)

                Text("Installation Complete")
                    .font(.headline)
                    .opacity(showResult ? 1 : 0)
            }

        case .failure(let message):
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.red)
                    .scaleEffect(showResult ? 1 : 0.5)
                    .opacity(showResult ? 1 : 0)

                Text("Installation Failed")
                    .font(.headline)
                    .opacity(showResult ? 1 : 0)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                    .opacity(showResult ? 1 : 0)

                Button("Close") {
                    viewModel.dismissAPKInstall()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .opacity(showResult ? 1 : 0)
            }
        }
    }
}
