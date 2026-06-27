import Foundation
import ZIPFoundation

/// Cấu trúc dữ liệu Extension tải về từ Registry URL nguồn lớn
public struct RegistryExtension: Codable, Identifiable, Equatable {
    public var id: String { path }
    public let name: String
    public let author: String
    public let path: String
    public let version: Int
    public let source: String
    public let icon: String?
    public let description: String?
    public let type: String?
    public let locale: String?
    
    public init(
        name: String,
        author: String,
        path: String,
        version: Int,
        source: String,
        icon: String? = nil,
        description: String? = nil,
        type: String? = nil,
        locale: String? = nil
    ) {
        self.name = name
        self.author = author
        self.path = path
        self.version = version
        self.source = source
        self.icon = icon
        self.description = description
        self.type = type
        self.locale = locale
    }
}

/// Cấu trúc phản hồi từ Registry JSON
public struct RegistryResponse: Codable {
    public let data: [RegistryExtension]
}

/// Định nghĩa cấu trúc file plugin.json bên trong extension
public struct ExtensionPluginJson: Codable {
    public struct Metadata: Codable {
        public let name: String
        public let author: String?
        public let version: Int?
        public let source: String?
        public let regexp: String?
        public let description: String?
        public let locale: String?
        public let type: String?
    }
    
    public struct ScriptMapping: Codable {
        public let home: String?
        public let genre: String?
        public let detail: String?
        public let search: String?
        public let page: String?
        public let toc: String?
        public let chap: String?
    }
    
    public let metadata: Metadata
    public let script: ScriptMapping?
    public let config: [String: ExtensionConfigField]?
}

/// Định nghĩa trường cấu hình động
public struct ExtensionConfigField: Codable, Equatable {
    public let title: String?
    public let mode: String?
    public let format: String?
    public let `default`: String?
    
    public init(title: String?, mode: String?, format: String?, `default`: String?) {
        self.title = title
        self.mode = mode
        self.format = format
        self.default = `default`
    }
}

/// Lớp quản lý vòng đời của các Tiện ích mở rộng VBook
public final class VBookExtensionManager {
    
    public static let shared = VBookExtensionManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    /// Thư mục lưu trữ các extensions cục bộ
    public var extensionsDirectoryURL: URL {
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let extDir = documentDir.appendingPathComponent("Extensions", isDirectory: true)
        try? fileManager.createDirectory(at: extDir, withIntermediateDirectories: true)
        return extDir
    }
    
    /// Tải danh sách tiện ích mở rộng từ Registry URL nguồn lớn
    public func fetchRegistry(from urlStr: String) async throws -> [RegistryExtension] {
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "VBookExtensionManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Registry URL không hợp lệ"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(RegistryResponse.self, from: data)
        return response.data
    }
    
    /// Tải tệp ZIP từ URL và cài đặt vào thiết bị
    public func downloadAndInstallExtension(from urlStr: String, extensionId: String) async throws {
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "VBookExtensionManager", code: 402, userInfo: [NSLocalizedDescriptionKey: "Download URL không hợp lệ"])
        }
        
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try await installExtension(zipFileURL: tempURL, extensionId: extensionId)
    }
    
    /// Cài đặt tiện ích từ file ZIP cục bộ
    public func installExtension(zipFileURL: URL, extensionId: String) async throws {
        let extFolderURL = extensionsDirectoryURL.appendingPathComponent(extensionId, isDirectory: true)
        
        // 1. Dọn dẹp thư mục cũ nếu có
        if fileManager.fileExists(atPath: extFolderURL.path) {
            try? fileManager.removeItem(at: extFolderURL)
        }
        try fileManager.createDirectory(at: extFolderURL, withIntermediateDirectories: true)
        
        // 2. Giải nén ZIP sử dụng ZIPFoundation
        try fileManager.unzipItem(at: zipFileURL, to: extFolderURL)
        
        // 3. Kiểm tra tệp plugin.json
        // Hỗ trợ trường hợp giải nén ra có một thư mục con cùng tên bên trong
        var targetJsonURL = extFolderURL.appendingPathComponent("plugin.json")
        
        if !fileManager.fileExists(atPath: targetJsonURL.path) {
            // Thử tìm trong thư mục con đầu tiên
            if let subDirs = try? fileManager.contentsOfDirectory(at: extFolderURL, includingPropertiesForKeys: nil),
               let firstSubDir = subDirs.first(where: { $0.hasDirectoryPath }) {
                let subJsonURL = firstSubDir.appendingPathComponent("plugin.json")
                if fileManager.fileExists(atPath: subJsonURL.path) {
                    // Di chuyển toàn bộ nội dung từ thư mục con ra ngoài thư mục gốc extension
                    let contents = try fileManager.contentsOfDirectory(at: firstSubDir, includingPropertiesForKeys: nil)
                    for item in contents {
                        let dest = extFolderURL.appendingPathComponent(item.lastPathComponent)
                        if fileManager.fileExists(atPath: dest.path) {
                            try? fileManager.removeItem(at: dest)
                        }
                        try fileManager.moveItem(at: item, to: dest)
                    }
                    try? fileManager.removeItem(at: firstSubDir)
                }
            }
        }
        
        targetJsonURL = extFolderURL.appendingPathComponent("plugin.json")
        
        guard fileManager.fileExists(atPath: targetJsonURL.path) else {
            throw NSError(domain: "VBookExtensionManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp plugin.json hợp lệ bên trong extension"])
        }
        
        // 4. Phân tích plugin.json để đăng ký BookSource
        let jsonData = try Data(contentsOf: targetJsonURL)
        let pluginJson = try JSONDecoder().decode(ExtensionPluginJson.self, from: jsonData)
        
        // 5. Khởi tạo giá trị config mặc định (Key-Value)
        var defaultConfigValues: [String: String] = [:]
        if let config = pluginJson.config {
            for (key, field) in config {
                defaultConfigValues[key] = field.default ?? ""
            }
        }
        
        // Tự động gán CONFIG_URL tương đương với BASE_URL ban đầu để tương thích với config.js mẫu
        if defaultConfigValues["CONFIG_URL"] == nil, let defaultBase = defaultConfigValues["BASE_URL"] {
            defaultConfigValues["CONFIG_URL"] = defaultBase
        }
        
        let configData = try? JSONSerialization.data(withJSONObject: defaultConfigValues, options: [])
        let configJsonStr = configData != nil ? String(data: configData!, encoding: .utf8) : "{}"
        
        let configDefData = try? JSONEncoder().encode(pluginJson.config)
        let configDefJsonStr = configDefData != nil ? String(data: configDefData!, encoding: .utf8) : "{}"
        
        // 6. Lưu đăng ký vào Database
        let bookSource = BookSource(
            bookSourceUrl: pluginJson.metadata.source ?? "extension://\(extensionId)",
            bookSourceName: pluginJson.metadata.name,
            bookSourceGroup: "Extensions",
            bookSourceType: .text,
            bookUrlPattern: pluginJson.metadata.regexp,
            customOrder: 0,
            enabled: true,
            enabledExplore: true,
            isExtension: true,
            extensionId: extensionId,
            extensionConfig: configJsonStr,
            extensionConfigDefinition: configDefJsonStr
        )
        
        await DatabaseManager.shared.saveBookSource(bookSource)
    }
    
    /// Gỡ cài đặt extension
    public func uninstallExtension(source: BookSource) async {
        guard let extId = source.extensionId else { return }
        let extFolderURL = extensionsDirectoryURL.appendingPathComponent(extId, isDirectory: true)
        if fileManager.fileExists(atPath: extFolderURL.path) {
            try? fileManager.removeItem(at: extFolderURL)
        }
        await DatabaseManager.shared.deleteBookSource(url: source.bookSourceUrl)
    }
}
