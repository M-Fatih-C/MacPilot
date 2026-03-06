// FileBrowserView.swift
// MacPilot — MacPilot-iOS / Views
//
// File browser for navigating and transferring files on the Mac.

import SwiftUI
import Combine
import UniformTypeIdentifiers
import SharedCore

// MARK: - FileBrowserView

struct FileBrowserView: View {
    @ObservedObject var connection: AnyMacConnectionService
    @StateObject private var viewModel = FileViewModel()
    @StateObject private var transferService: FileTransferService
    @StateObject private var biometricAuth = BiometricAuth.shared
    @State private var showUploadPicker = false
    @State private var authFailed = false
    @State private var authErrorMessage = "File upload requires biometric authentication."
    @State private var uploadMessage: String?
    @State private var showUploadMessage = false

    init(connection: AnyMacConnectionService) {
        self.connection = connection
        _transferService = StateObject(
            wrappedValue: FileTransferService(connection: connection)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Path breadcrumb
                pathBar

                // File list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading...")
                        .tint(.blue)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else if viewModel.files.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    fileList
                }
            }
            .background(
                Color(red: 0.06, green: 0.06, blue: 0.14)
                    .ignoresSafeArea()
            )
            .navigationTitle("Files")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            Task { await authenticateAndUpload() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Image(systemName: biometricAuth.biometricType.icon)
                                    .font(.caption)
                            }
                        }

                        Button {
                            viewModel.refresh(connection: connection)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear {
                biometricAuth.checkAvailability()
                viewModel.browse(path: "~", connection: connection)
            }
            .fileImporter(
                isPresented: $showUploadPicker,
                allowedContentTypes: [UTType.data]
            ) { result in
                handleUploadSelection(result)
            }
            .alert("Authentication Failed", isPresented: $authFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authErrorMessage)
            }
            .alert("Upload", isPresented: $showUploadMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadMessage ?? "Upload status unavailable.")
            }
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.pathComponents, id: \.self) { component in
                    Button {
                        viewModel.navigateToComponent(component, connection: connection)
                    } label: {
                        HStack(spacing: 2) {
                            if component != viewModel.pathComponents.first {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(component)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.white.opacity(0.04))
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            // Back button (if not root)
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack(connection: connection)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.left")
                            .foregroundStyle(.blue)
                        Text("..")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.files) { file in
                FileRow(file: file) {
                    if file.isDirectory {
                        viewModel.browse(path: file.path, connection: connection)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Empty Directory")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
    // MARK: - FaceID Upload

    private func authenticateAndUpload() async {
        guard connection.isConnected else {
            authErrorMessage = "Connect to your Mac first."
            authFailed = true
            return
        }

        let authenticated = await biometricAuth.authenticateForFileUpload()
        if authenticated {
            showUploadPicker = true
        } else {
            authErrorMessage = "Biometric or passcode authentication failed. Upload was cancelled."
            authFailed = true
        }
    }

    private func handleUploadSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let fileURL):
            Task {
                await uploadSelectedFile(fileURL)
            }
        case .failure(let error):
            uploadMessage = "File selection failed: \(error.localizedDescription)"
            showUploadMessage = true
        }
    }

    private func uploadSelectedFile(_ fileURL: URL) async {
        let secured = fileURL.startAccessingSecurityScopedResource()
        defer {
            if secured {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        await transferService.uploadFile(
            fileURL: fileURL,
            destinationPath: viewModel.currentPath
        )

        uploadMessage = "Upload started: \(fileURL.lastPathComponent)"
        showUploadMessage = true
    }
}

// MARK: - FileRow

struct FileRow: View {
    let file: FileItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: file.isDirectory ? "folder.fill" : fileIcon)
                    .font(.title3)
                    .foregroundStyle(file.isDirectory ? .blue : .gray)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if !file.isDirectory {
                            Text(formatSize(file.size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(file.permissions)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var fileIcon: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go": return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        case "mp4", "mov", "avi": return "film.fill"
        case "mp3", "wav", "aac": return "music.note"
        case "pdf": return "doc.richtext.fill"
        case "zip", "tar", "gz": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }
}

// MARK: - FileViewModel

@MainActor
class FileViewModel: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var currentPath: String = "~"
    @Published var isLoading: Bool = false
    private var messageCancellable: AnyCancellable?

    init() {
        self.messageCancellable = NotificationCenter.default
            .publisher(for: .macPilotMessageReceived)
            .compactMap { $0.object as? Data }
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let type = try? MessageProtocol.peekType(data), type == .fileBrowseResponse else {
                    return
                }
                self?.handleBrowseResponse(data)
            }
    }

    var pathComponents: [String] {
        currentPath.split(separator: "/").map(String.init)
    }

    var canGoBack: Bool {
        currentPath != "/" && currentPath != "~"
    }

    func browse(path: String, connection: AnyMacConnectionService) {
        currentPath = path
        isLoading = true

        // Send browse request
        let request = FileBrowseRequest(path: path)
        do {
            let data = try MessageProtocol.encodePlaintext(request, type: .fileBrowseRequest)
            connection.send(data)
        } catch {
            print("[MacPilot][Files] Browse request failed: \(error)")
        }

        // Simulate loading (will be replaced by actual response handler)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isLoading = false
        }
    }

    func goBack(connection: AnyMacConnectionService) {
        let parent = (currentPath as NSString).deletingLastPathComponent
        browse(path: parent, connection: connection)
    }

    func refresh(connection: AnyMacConnectionService) {
        browse(path: currentPath, connection: connection)
    }

    func navigateToComponent(_ component: String, connection: AnyMacConnectionService) {
        guard let index = pathComponents.firstIndex(of: component) else { return }
        let path = "/" + pathComponents.prefix(through: index).joined(separator: "/")
        browse(path: path, connection: connection)
    }

    func handleBrowseResponse(_ data: Data) {
        do {
            let result = try MessageProtocol.decodePlaintext(data, as: FileBrowseResponse.self)
            self.files = result.payload.files
            self.isLoading = false
        } catch {
            print("[MacPilot][Files] Decode failed: \(error)")
        }
    }
}

/// Request to browse a directory.
public struct FileBrowseRequest: Codable, Sendable {
    public let path: String
    public init(path: String) { self.path = path }
}

/// Response with directory contents.
public struct FileBrowseResponse: Codable, Sendable {
    public let path: String
    public let files: [FileItem]
    public init(path: String, files: [FileItem]) {
        self.path = path
        self.files = files
    }
}
