import SwiftUI
import UniformTypeIdentifiers

/// Màn hình quản lý Kho tiện ích mở rộng (Extension Store)
public struct ExtensionStoreView: View {
    
    @State private var registryUrl: String = "https://raw.githubusercontent.com/Darkrai9x/vbook-extensions/refs/heads/master/plugin.json"
    @State private var registryExtensions: [RegistryExtension] = []
    @State private var installedExtensions: [BookSource] = []
    
    @State private var isLoadingRegistry = false
    @State private var registryErrorMessage = ""
    
    // Quá trình cài đặt
    @State private var installingPaths: Set<String> = []
    @State private var installStatusMessage = ""
    
    // File Importer
    @State private var showFileImporter = false
    
    // Config Sheet
    @State private var selectedExtensionForConfig: BookSource? = nil
    
    public init() {}
    
    public var body: some View {
        List {
            // 1. Nhập Registry nguồn extension lớn
            Section(header: Text("Nguồn kho tiện ích (Registry URL)")) {
                HStack {
                    TextField("Registry URL", text: $registryUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.footnote)
                    
                    Button(action: {
                        Task { await loadRegistry() }
                    }) {
                        if isLoadingRegistry {
                            ProgressView()
                        } else {
                            Text("Tải")
                                .bold()
                        }
                    }
                    .disabled(isLoadingRegistry || registryUrl.isEmpty)
                }
                
                if !registryErrorMessage.isEmpty {
                    Text(registryErrorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            // 2. Import file ZIP cục bộ
            Section(header: Text("Cài đặt thủ công")) {
                Button(action: { showFileImporter = true }) {
                    HStack {
                        Image(systemName: "doc.zipper")
                        Text("Nhập từ tệp tin .zip cục bộ")
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // 3. Hiển thị thông báo trạng thái cài đặt chung
            if !installStatusMessage.isEmpty {
                Section {
                    Text(installStatusMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // 4. Danh sách đã cài đặt
            Section(header: Text("Tiện ích đã cài đặt (\(installedExtensions.count))")) {
                if installedExtensions.isEmpty {
                    Text("Chưa cài đặt tiện ích nào.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(installedExtensions) { source in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.bookSourceName)
                                    .font(.headline)
                                Text(source.bookSourceUrl)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                // Nút Cấu hình
                                if source.extensionConfigDefinition != nil && source.extensionConfigDefinition != "{}" {
                                    Button(action: {
                                        selectedExtensionForConfig = source
                                    }) {
                                        Image(systemName: "slider.horizontal.3")
                                            .foregroundColor(.blue)
                                            .padding(8)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                // Nút Xóa
                                Button(action: {
                                    Task { await uninstallExtension(source) }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .padding(8)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            
            // 5. Danh sách tiện ích có sẵn trong kho
            Section(header: Text("Tiện ích có sẵn trong kho (\(registryExtensions.count))")) {
                if registryExtensions.isEmpty {
                    Text("Nhấn nút 'Tải' ở trên để nạp danh sách tiện ích từ Registry.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(registryExtensions) { ext in
                        HStack(alignment: .center, spacing: 12) {
                            // Icon đại diện
                            AsyncImage(url: URL(string: ext.icon ?? "")) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                         .aspectRatio(contentMode: .fit)
                                         .frame(width: 40, height: 40)
                                         .cornerRadius(8)
                                default:
                                    Image(systemName: "puzzlepiece.extension")
                                         .resizable()
                                         .aspectRatio(contentMode: .fit)
                                         .frame(width: 40, height: 40)
                                         .foregroundColor(.gray)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ext.name)
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Text("v\(ext.version)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                
                                if let desc = ext.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Text("Tác giả: \(ext.author) | Loại: \(ext.type ?? "novel")")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Nút cài đặt/cập nhật
                            Button(action: {
                                Task { await installFromRegistry(ext) }
                            }) {
                                if installingPaths.contains(ext.path) {
                                    ProgressView()
                                } else {
                                    Text(isInstalled(ext) ? "Cập nhật" : "Cài đặt")
                                        .font(.caption)
                                        .bold()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isInstalled(ext) ? Color.green : Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .disabled(installingPaths.contains(ext.path))
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Kho Tiện Ích VBook")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importZipFile(url) }
            case .failure(let error):
                installStatusMessage = "Lỗi chọn tệp tin: \(error.localizedDescription)"
            }
        }
        .sheet(item: $selectedExtensionForConfig) { source in
            ExtensionConfigView(source: source) {
                Task { await refreshLocalExtensions() }
            }
        }
        .onAppear {
            Task {
                await refreshLocalExtensions()
            }
        }
    }
    
    // MARK: - Logic Operations
    
    private func isInstalled(_ ext: RegistryExtension) -> Bool {
        return installedExtensions.contains(where: { $0.bookSourceName == ext.name })
    }
    
    private func refreshLocalExtensions() async {
        let allSources = await DatabaseManager.shared.getAllBookSources()
        let filtered = allSources.filter { $0.isExtension == true }
        DispatchQueue.main.async {
            self.installedExtensions = filtered
        }
    }
    
    private func loadRegistry() async {
        isLoadingRegistry = true
        registryErrorMessage = ""
        do {
            let list = try await VBookExtensionManager.shared.fetchRegistry(from: registryUrl)
            DispatchQueue.main.async {
                self.registryExtensions = list
                self.isLoadingRegistry = false
            }
        } catch {
            DispatchQueue.main.async {
                self.registryErrorMessage = "Lỗi nạp kho: \(error.localizedDescription)"
                self.isLoadingRegistry = false
            }
        }
    }
    
    private func installFromRegistry(_ ext: RegistryExtension) async {
        DispatchQueue.main.async {
            installingPaths.insert(ext.path)
            installStatusMessage = "Đang cài đặt \(ext.name)..."
        }
        
        let extId = ext.name.lowercased().replacingOccurrences(of: " ", with: "_")
        
        do {
            try await VBookExtensionManager.shared.downloadAndInstallExtension(from: ext.path, extensionId: extId)
            await refreshLocalExtensions()
            DispatchQueue.main.async {
                installingPaths.remove(ext.path)
                installStatusMessage = "Cài đặt thành công: \(ext.name)!"
            }
        } catch {
            DispatchQueue.main.async {
                installingPaths.remove(ext.path)
                installStatusMessage = "Lỗi cài đặt \(ext.name): \(error.localizedDescription)"
            }
        }
    }
    
    private func importZipFile(_ url: URL) async {
        let extId = url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "_")
        installStatusMessage = "Đang cài đặt tệp ZIP..."
        
        // Cần truy cập URL file an toàn (scoped resource)
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured { url.stopAccessingSecurityScopedResource() }
        }
        
        do {
            try await VBookExtensionManager.shared.installExtension(zipFileURL: url, extensionId: extId)
            await refreshLocalExtensions()
            DispatchQueue.main.async {
                installStatusMessage = "Cài đặt tệp ZIP thành công!"
            }
        } catch {
            DispatchQueue.main.async {
                installStatusMessage = "Lỗi cài đặt tệp ZIP: \(error.localizedDescription)"
            }
        }
    }
    
    private func uninstallExtension(_ source: BookSource) async {
        installStatusMessage = "Đang gỡ cài đặt \(source.bookSourceName)..."
        await VBookExtensionManager.shared.uninstallExtension(source: source)
        await refreshLocalExtensions()
        DispatchQueue.main.async {
            installStatusMessage = "Đã gỡ cài đặt tiện ích mở rộng!"
        }
    }
}

