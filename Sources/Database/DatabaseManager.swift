import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Trình quản lý cơ sở dữ liệu nội bộ bằng giải pháp lưu trữ JSON File Persistence bảo mật, an toàn, nhanh chóng và không phụ thuộc thư viện ngoài (Zero Dependency)
public actor DatabaseManager {
    
    public static let shared = DatabaseManager()
    
    private var bookSources: [String: BookSource] = [:]
    private var books: [String: Book] = [:]
    private var replaceRules: [String: ReplaceRule] = [:]
    private var isCorrupted = false
    
    private init() {
        let fileManager = FileManager.default
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documentDir.appendingPathComponent("Database", isDirectory: true)
        try? fileManager.createDirectory(at: dbURL, withIntermediateDirectories: true)
        
        // 1. Load BookSources
        let sourcesURL = dbURL.appendingPathComponent("book_sources.json")
        if fileManager.fileExists(atPath: sourcesURL.path) {
            do {
                let data = try Data(contentsOf: sourcesURL)
                let list = try JSONDecoder().decode([BookSource].self, from: data)
                for src in list {
                    bookSources[src.bookSourceUrl] = src
                }
            } catch {
                isCorrupted = true
                print("[DatabaseManager] Lỗi giải mã book_sources.json: \(error). Khóa ghi để bảo toàn dữ liệu đĩa.")
            }
        }
        
        // 2. Load Books
        let booksURL = dbURL.appendingPathComponent("books.json")
        if fileManager.fileExists(atPath: booksURL.path) {
            do {
                let data = try Data(contentsOf: booksURL)
                let list = try JSONDecoder().decode([Book].self, from: data)
                for book in list {
                    books[book.bookUrl] = book
                }
            } catch {
                isCorrupted = true
                print("[DatabaseManager] Lỗi giải mã books.json: \(error). Khóa ghi để bảo toàn dữ liệu đĩa.")
            }
        }
        
        // 3. Load ReplaceRules
        let rulesURL = dbURL.appendingPathComponent("replace_rules.json")
        if fileManager.fileExists(atPath: rulesURL.path) {
            do {
                let data = try Data(contentsOf: rulesURL)
                let list = try JSONDecoder().decode([ReplaceRule].self, from: data)
                for rule in list {
                    if let id = rule.id {
                        replaceRules[id] = rule
                    }
                }
            } catch {
                isCorrupted = true
                print("[DatabaseManager] Lỗi giải mã replace_rules.json: \(error).")
            }
        }
    }
    
    private var databaseDirectoryURL: URL {
        let fileManager = FileManager.default
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbDir = documentDir.appendingPathComponent("Database", isDirectory: true)
        try? fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir
    }
    
    // MARK: - Core Load / Save Operations
    
    private func saveBookSourcesToDisk() {
        guard !isCorrupted else { return }
        let sourcesURL = databaseDirectoryURL.appendingPathComponent("book_sources.json")
        let list = Array(bookSources.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: sourcesURL, options: .atomic)
        }
    }
    
    private func saveBooksToDisk() {
        guard !isCorrupted else { return }
        let booksURL = databaseDirectoryURL.appendingPathComponent("books.json")
        let list = Array(books.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: booksURL, options: .atomic)
        }
    }
    
    private func saveReplaceRulesToDisk() {
        guard !isCorrupted else { return }
        let rulesURL = databaseDirectoryURL.appendingPathComponent("replace_rules.json")
        let list = Array(replaceRules.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: rulesURL, options: .atomic)
        }
    }
    
    // MARK: - BookSource APIs
    
    public func saveBookSource(_ source: BookSource) {
        bookSources[source.bookSourceUrl] = source
        saveBookSourcesToDisk()
    }
    
    public func deleteBookSource(url: String) {
        bookSources.removeValue(forKey: url)
        saveBookSourcesToDisk()
    }
    
    public func getAllBookSources() -> [BookSource] {
        return Array(bookSources.values).sorted(by: { $0.customOrder < $1.customOrder })
    }
    
    public func getBookSource(url: String) -> BookSource? {
        return bookSources[url]
    }
    
    // MARK: - Book (Bookshelf) APIs
    
    public func saveBook(_ book: Book) {
        books[book.bookUrl] = book
        saveBooksToDisk()
    }
    
    public func deleteBook(url: String) {
        books.removeValue(forKey: url)
        saveBooksToDisk()
        
        // Xóa cả file cache chương đi kèm để giải phóng bộ nhớ
        let fileManager = FileManager.default
        let chaptersURL = databaseDirectoryURL.appendingPathComponent("chapters_\(url.md5_16()).json")
        try? fileManager.removeItem(at: chaptersURL)
    }
    
    public func getAllBooks() -> [Book] {
        return Array(books.values).sorted(by: { $0.customOrder < $1.customOrder })
    }
    
    public func getBook(url: String) -> Book? {
        return books[url]
    }
    
    // MARK: - BookChapter APIs (Lưu theo từng tệp riêng cho mỗi quyển sách)
    
    public func saveChapters(_ chapters: [BookChapter], forBookUrl bookUrl: String) {
        let fileURL = databaseDirectoryURL.appendingPathComponent("chapters_\(bookUrl.md5_16()).json")
        if let data = try? JSONEncoder().encode(chapters) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    public func getChapters(forBookUrl bookUrl: String) -> [BookChapter] {
        let fileURL = databaseDirectoryURL.appendingPathComponent("chapters_\(bookUrl.md5_16()).json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([BookChapter].self, from: data) {
            return list
        }
        return []
    }
    
    // MARK: - ReplaceRule APIs
    
    public func saveReplaceRule(_ rule: ReplaceRule) {
        if let id = rule.id {
            replaceRules[id] = rule
            saveReplaceRulesToDisk()
        }
    }
    
    public func deleteReplaceRule(id: String) {
        replaceRules.removeValue(forKey: id)
        saveReplaceRulesToDisk()
    }
    
    public func getAllReplaceRules() -> [ReplaceRule] {
        return Array(replaceRules.values).sorted(by: { $0.customOrder < $1.customOrder })
    }
}

// MARK: - Helper MD5 extension
extension String {
    fileprivate func md5_16() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        #if canImport(CryptoKit)
        let digest = Insecure.MD5.hash(data: data)
        let hexString = digest.map { String(format: "%02hhx", $0) }.joined()
        let start = hexString.index(hexString.startIndex, offsetBy: 8)
        let end = hexString.index(start, offsetBy: 16)
        return String(hexString[start..<end])
        #else
        // Fallback thuật toán băm Djb2 nhất quán thay thế cho hashValue ngẫu nhiên của Swift
        var hash: UInt32 = 5381
        for scalar in self.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ scalar.value
        }
        return String(format: "%08x", hash)
        #endif
    }
}
