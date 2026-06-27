import SwiftUI

/// Màn hình Cài đặt (SettingsView)
public struct SettingsView: View {
    
    // Toggle Dịch thuật
    @AppStorage("translateEnable") private var isTranslateEnabled = false
    
    // WebDAV Credentials
    @AppStorage("webdav_url") private var webdavUrl = ""
    @AppStorage("webdav_username") private var webdavUsername = ""
    @AppStorage("webdav_password") private var webdavPassword = ""
    
    @State private var cacheSizeStr = "0.0 MB"
    @State private var dictStatus = "Chưa nạp từ điển"
    @State private var isSyncing = false
    @State private var syncMessage = ""
    @State private var isReloadingDicts = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                // 1. Cấu hình dịch thuật tự động (VietPhrase)
                Section(header: Text("Dịch Thuật (VietPhrase)")) {
                    Toggle("Bật Dịch thuật QT tự động", isOn: $isTranslateEnabled)
                        .onChange(of: isTranslateEnabled) { val in
                            TranslateUtils.isTranslateEnabled = val
                        }
                    
                    HStack {
                        Text("Trạng thái từ điển")
                        Spacer()
                        Text(dictStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        Task { await reloadDictionaries() }
                    }) {
                        if isReloadingDicts {
                            ProgressView()
                        } else {
                            Text("Nạp lại & Biên dịch từ điển (.txt -> .dat)")
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(isReloadingDicts)
                }
                
                // 2. Cấu hình đồng bộ WebDAV
                Section(header: Text("Đồng bộ sao lưu WebDAV")) {
                    TextField("Địa chỉ WebDAV URL", text: $webdavUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Tên đăng nhập (Username)", text: $webdavUsername)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Mật khẩu (Password)", text: $webdavPassword)
                    
                    if !syncMessage.isEmpty {
                        Text(syncMessage)
                            .font(.caption)
                            .foregroundColor(syncMessage.hasPrefix("Lỗi") ? .red : .green)
                    }
                    
                    HStack(spacing: 20) {
                        Button(action: { Task { await performBackup() } }) {
                            Text("Sao lưu cấu hình")
                        }
                        .disabled(isSyncing || webdavUrl.isEmpty)
                        
                        Spacer()
                        
                        Button(action: { Task { await performRestore() } }) {
                            Text("Phục hồi cấu hình")
                        }
                        .disabled(isSyncing || webdavUrl.isEmpty)
                    }
                    .font(.subheadline)
                }
                
                // 3. Quản lý dung lượng & Cache
                Section(header: Text("Quản lý bộ nhớ & Cache")) {
                    HStack {
                        Text("Dung lượng đệm")
                        Spacer()
                        Text(cacheSizeStr)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: clearReaderCache) {
                        Text("Xóa cache chương truyện & ảnh bìa")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Cài Đặt")
            .onAppear {
                checkDictStatus()
                calculateCacheSize()
            }
        }
    }
    
    // MARK: - Logic Operations
    
    private func checkDictStatus() {
        Task {
            let loaded = await TranslationLoader.shared.isLoaded()
            DispatchQueue.main.async {
                self.dictStatus = loaded ? "Đã nạp vào RAM (Sẵn sàng)" : "Chưa nạp hoặc đang chờ"
            }
        }
    }
    
    private func reloadDictionaries() async {
        isReloadingDicts = true
        // Xóa cache nhị phân cũ để ép buộc dịch lại từ text thô
        await TranslationLoader.shared.clearAllBinaryCache()
        
        do {
            _ = try await TranslationLoader.shared.loadTranslationData()
            dictStatus = "Đã biên dịch và nạp thành công!"
        } catch {
            dictStatus = "Biên dịch lỗi: \(error.localizedDescription)"
        }
        isReloadingDicts = false
    }
    
    private func calculateCacheSize() {
        let fileManager = FileManager.default
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        var totalBytes: Int64 = 0
        
        let targetDirs = [
            documentDir.appendingPathComponent("ExportedBooks"),
            documentDir.appendingPathComponent("Database"),
            cacheDir.appendingPathComponent("translate")
        ]
        
        for dir in targetDirs {
            if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in files {
                    if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                        totalBytes += Int64(size)
                    }
                }
            }
        }
        
        let sizeInMB = Double(totalBytes) / (1024.0 * 1024.0)
        cacheSizeStr = String(format: "%.2f MB", sizeInMB)
    }
    
    private func clearReaderCache() {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        // Xóa cache translate, webview caches, v.v.
        let translateBinaryURL = cacheDir.appendingPathComponent("translate")
        try? fileManager.removeItem(at: translateBinaryURL)
        
        // Reset DB Caches
        Task {
            await TranslationLoader.shared.clearCache()
        }
        
        calculateCacheSize()
    }
    
    // MARK: - WebDAV Web Backup / Restore Sync
    
    private func performBackup() async {
        isSyncing = true
        syncMessage = "Đang kết nối sao lưu..."
        
        let fileManager = FileManager.default
        let dbDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Database")
        
        // Đọc danh sách books và book_sources
        let sourcesURL = dbDir.appendingPathComponent("book_sources.json")
        let booksURL = dbDir.appendingPathComponent("books.json")
        
        var backupData = [String: Data]()
        if let data = try? Data(contentsOf: sourcesURL) { backupData["book_sources.json"] = data }
        if let data = try? Data(contentsOf: booksURL) { backupData["books.json"] = data }
        
        guard !backupData.isEmpty else {
            syncMessage = "Không có cấu hình để sao lưu"
            isSyncing = false
            return
        }
        
        do {
            // Đóng gói thành tệp zip hoặc lưu từng tệp lên WebDAV
            for (filename, data) in backupData {
                let uploadUrlStr = webdavUrl.hasSuffix("/") ? "\(webdavUrl)\(filename)" : "\(webdavUrl)/\(filename)"
                guard let url = URL(string: uploadUrlStr) else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.httpBody = data
                
                // Tiêm Authentication Header
                let loginString = String(format: "%@:%@", webdavUsername, webdavPassword)
                if let loginData = loginString.data(using: .utf8) {
                    let base64LoginString = loginData.base64EncodedString()
                    request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
                }
                
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    throw NSError(domain: "WebDAV", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về mã lỗi: \(httpResponse.statusCode)"])
                }
            }
            
            syncMessage = "Sao lưu WebDAV thành công!"
            isSyncing = false
        } catch {
            syncMessage = "Lỗi sao lưu: \(error.localizedDescription)"
            isSyncing = false
        }
    }
    
    private func performRestore() async {
        isSyncing = true
        syncMessage = "Đang tải bản sao lưu..."
        
        let filenames = ["book_sources.json", "books.json"]
        let fileManager = FileManager.default
        let dbDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Database")
        
        do {
            for filename in filenames {
                let downloadUrlStr = webdavUrl.hasSuffix("/") ? "\(webdavUrl)\(filename)" : "\(webdavUrl)/\(filename)"
                guard let url = URL(string: downloadUrlStr) else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                let loginString = String(format: "%@:%@", webdavUsername, webdavPassword)
                if let loginData = loginString.data(using: .utf8) {
                    let base64LoginString = loginData.base64EncodedString()
                    request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        let targetURL = dbDir.appendingPathComponent(filename)
                        try data.write(to: targetURL, options: .atomic)
                    } else if httpResponse.statusCode != 404 {
                        throw NSError(domain: "WebDAV", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Lỗi tải tệp: \(httpResponse.statusCode)"])
                    }
                }
            }
            
            syncMessage = "Phục hồi cấu hình WebDAV thành công! Hãy khởi động lại tab."
            isSyncing = false
        } catch {
            syncMessage = "Lỗi phục hồi: \(error.localizedDescription)"
            isSyncing = false
        }
    }
}
