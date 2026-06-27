import Foundation

/// Struct lưu trữ dữ liệu các từ điển phục vụ dịch Hán-Việt
public struct TranslationData {
    public let names: DoubleArrayTrie
    public let vietPhrase: DoubleArrayTrie
    public let chinesePhienAm: [String: String]
    
    public init(names: DoubleArrayTrie, vietPhrase: DoubleArrayTrie, chinesePhienAm: [String: String]) {
        self.names = names
        self.vietPhrase = vietPhrase
        self.chinesePhienAm = chinesePhienAm
    }
}

/// Quản lý nạp từ điển Hán-Việt, hỗ trợ biên dịch file text thô thành binary DAT
public actor TranslationLoader {
    
    public static let shared = TranslationLoader()
    
    public enum DictType: String {
        case names = "Names"
        case vietPhrase = "VietPhrase"
        case phienAm = "ChinesePhienAmWords"
    }
    
    private var translationData: TranslationData?
    private var activeTask: Task<TranslationData, Error>?
    
    private init() {}
    
    /// Thư mục lưu trữ cache từ điển nhị phân
    private var cacheDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("translate/binary", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }
    
    /// Thư mục lưu trữ từ điển tùy chỉnh do người dùng import
    private var customDictDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let customDir = paths[0].appendingPathComponent("translate/custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        return customDir
    }
    
    /// Báo trạng thái từ điển đã được load lên RAM chưa
    public func isLoaded() -> Bool {
        return translationData != nil
    }
    
    /// Tải tất cả từ điển (phiên bản bất đồng bộ)
    public func loadTranslationData() async throws -> TranslationData {
        if let cached = translationData {
            return cached
        }
        
        if let task = activeTask {
            return try await task.value
        }
        
        let task = Task<TranslationData, Error> {
            print("TranslationLoader: Khởi tạo tiến trình tải dữ liệu dịch thuật...")
            let namesTrie = try await loadTrieDictionary(type: .names)
            let vietPhraseTrie = try await loadTrieDictionary(type: .vietPhrase)
            let phienAmMap = try await loadPhoneticDictionary()
            
            return TranslationData(
                names: namesTrie,
                vietPhrase: vietPhraseTrie,
                chinesePhienAm: phienAmMap
            )
        }
        
        self.activeTask = task
        defer { self.activeTask = nil }
        
        do {
            let data = try await task.value
            self.translationData = data
            return data
        } catch {
            throw error
        }
    }
    
    /// Xóa cache trong bộ nhớ (để reload từ điển)
    public func clearCache() {
        self.translationData = nil
    }
    
    /// Xóa tất cả các file cache nhị phân (.dat / .bin)
    public func clearAllBinaryCache() {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files {
                if file.pathExtension == "dat" || file.pathExtension == "bin" {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        self.translationData = nil
    }
    
    // MARK: - Helper Methods
    
    /// Tải từ điển kiểu Trie (Names hoặc VietPhrase)
    private func loadTrieDictionary(type: DictType) async throws -> DoubleArrayTrie {
        let trie = DoubleArrayTrie()
        
        // 1. Kiểm tra từ điển tùy chỉnh của người dùng trong Documents
        let customTextURL = customDictDirectoryURL.appendingPathComponent("\(type.rawValue).txt")
        let customBinaryURL = customDictDirectoryURL.appendingPathComponent("\(type.rawValue).dat")
        
        if FileManager.default.fileExists(atPath: customTextURL.path) {
            if FileManager.default.fileExists(atPath: customBinaryURL.path) {
                do {
                    try trie.load(from: customBinaryURL)
                    print("TranslationLoader: Đã nạp từ điển tùy chỉnh (binary): \(type.rawValue)")
                    return trie
                } catch {
                    try? FileManager.default.removeItem(at: customBinaryURL)
                }
            }
            
            // Xây dựng binary từ file text tùy chỉnh
            do {
                print("TranslationLoader: Đang build từ điển tùy chỉnh (text -> binary): \(type.rawValue)")
                let entries = try parseTextDictionary(fileURL: customTextURL)
                let tmpURL = customBinaryURL.appendingPathExtension("tmp")
                if let stream = OutputStream(url: tmpURL, append: false) {
                    try trie.save(to: stream, entries: entries)
                    try? FileManager.default.removeItem(at: customBinaryURL)
                    try FileManager.default.moveItem(at: tmpURL, to: customBinaryURL)
                }
                try trie.load(from: customBinaryURL)
                return trie
            } catch {
                print("TranslationLoader: Lỗi khi build từ điển tùy chỉnh \(type.rawValue): \(error)")
            }
        }
        
        // 2. Kiểm tra cache mặc định ở Caches directory
        let defaultBinaryURL = cacheDirectoryURL.appendingPathComponent("\(type.rawValue).dat")
        if FileManager.default.fileExists(atPath: defaultBinaryURL.path) {
            do {
                try trie.load(from: defaultBinaryURL)
                return trie
            } catch {
                try? FileManager.default.removeItem(at: defaultBinaryURL)
            }
        }
        
        // 3. Nạp từ tệp raw text của app bundle và biên dịch lưu vào Cache
        if let bundleTextURL = Bundle.main.url(forResource: type.rawValue, withExtension: "txt") {
            do {
                print("TranslationLoader: Build cache nhị phân từ Bundle: \(type.rawValue)")
                let entries = try parseTextDictionary(fileURL: bundleTextURL)
                let tmpURL = defaultBinaryURL.appendingPathExtension("tmp")
                if let stream = OutputStream(url: tmpURL, append: false) {
                    try trie.save(to: stream, entries: entries)
                    try? FileManager.default.removeItem(at: defaultBinaryURL)
                    try FileManager.default.moveItem(at: tmpURL, to: defaultBinaryURL)
                }
                try trie.load(from: defaultBinaryURL)
                return trie
            } catch {
                print("TranslationLoader: Không thể build cache nhị phân cho \(type.rawValue) từ bundle, cố gắng đọc thô")
                throw error
            }
        }
        
        // 4. Nếu có sẵn tệp .dat đóng gói sẵn trong App Bundle thì load trực tiếp
        if let bundleDatURL = Bundle.main.url(forResource: type.rawValue, withExtension: "dat") {
            try trie.load(from: bundleDatURL)
            print("TranslationLoader: Tải trực tiếp file .dat từ App Bundle: \(type.rawValue)")
            return trie
        }
        
        throw NSError(domain: "TranslationLoader", code: 201, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy nguồn tài nguyên từ điển \(type.rawValue)"])
    }
    
    /// Tải từ điển phiên âm (ChinesePhienAmWords) dạng HashMap
    private func loadPhoneticDictionary() async throws -> [String: String] {
        let type = DictType.phienAm
        let customTextURL = customDictDirectoryURL.appendingPathComponent("\(type.rawValue).txt")
        let customCacheURL = customDictDirectoryURL.appendingPathComponent("\(type.rawValue).json")
        
        // 1. Từ điển tùy chỉnh của người dùng
        if FileManager.default.fileExists(atPath: customTextURL.path) {
            if FileManager.default.fileExists(atPath: customCacheURL.path),
               let data = try? Data(contentsOf: customCacheURL),
               let map = try? JSONDecoder().decode([String: String].self, from: data) {
                return map
            }
            
            if let map = try? parsePhoneticText(fileURL: customTextURL) {
                if let data = try? JSONEncoder().encode(map) {
                    try? data.write(to: customCacheURL)
                }
                return map
            }
        }
        
        // 2. Cache trong Cache directory
        let defaultCacheURL = cacheDirectoryURL.appendingPathComponent("\(type.rawValue).json")
        if FileManager.default.fileExists(atPath: defaultCacheURL.path),
           let data = try? Data(contentsOf: defaultCacheURL),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            return map
        }
        
        // 3. Từ bundle chính của ứng dụng
        if let bundleTextURL = Bundle.main.url(forResource: type.rawValue, withExtension: "txt") {
            let map = try parsePhoneticText(fileURL: bundleTextURL)
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: defaultCacheURL)
            }
            return map
        }
        
        print("TranslationLoader: Không tìm thấy từ điển phiên âm. Sử dụng map trống.")
        return [:]
    }
    
    /// Parse tệp tin từ điển văn bản thô (UTF-8, định dạng key=value)
    private func parseTextDictionary(fileURL: URL) throws -> [(String, String)] {
        let contentStr = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [(String, String)] = []
        
        contentStr.enumerateLines { line, _ in
            let trimmed = line.replacingOccurrences(of: "\u{0000}", with: "")
                              .replacingOccurrences(of: "\u{0001}", with: "")
                              .replacingOccurrences(of: "\u{0004}", with: "")
                              .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmed.isEmpty else { return }
            
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !val.isEmpty {
                    entries.append((key, val))
                }
            }
        }
        
        return entries
    }
    
    /// Parse tệp tin phiên âm văn bản thô (UTF-8, định dạng key=value)
    private func parsePhoneticText(fileURL: URL) throws -> [String: String] {
        let contentStr = try String(contentsOf: fileURL, encoding: .utf8)
        var map: [String: String] = [:]
        
        contentStr.enumerateLines { line, _ in
            let trimmed = line.replacingOccurrences(of: "\u{0000}", with: "")
                              .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmed.isEmpty else { return }
            
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !val.isEmpty {
                    map[key] = val
                }
            }
        }
        
        return map
    }
}
