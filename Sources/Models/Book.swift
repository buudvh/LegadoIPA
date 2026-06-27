import Foundation

/// Thực thể lưu trữ thông tin Sách (Book) trong tủ sách
public struct Book: Codable, Identifiable, Equatable {
    public var id: String { bookUrl } // Sử dụng bookUrl làm ID duy nhất
    
    public var bookUrl: String         // URL nhận diện sách
    public var tocUrl: String          // URL mục lục chương
    public var name: String            // Tên sách
    public var author: String?         // Tác giả
    public var coverUrl: String?       // Link ảnh bìa
    public var intro: String?          // Giới thiệu tóm tắt
    public var customOrder: Int        // Thứ tự sắp xếp thủ công
    public var origin: String          // Nguồn sách URL gốc
    public var originName: String      // Tên nguồn sách gốc
    public var type: Int               // Thể loại (0: chữ, 1: audio, 2: tranh)
    public var group: String?          // Phân nhóm trên tủ sách
    
    public var lastChapterTitle: String? // Tên chương cuối cùng đã cập nhật
    public var lastChapterTime: Int64    // Thời gian cập nhật chương cuối cùng
    
    public var durChapterIndex: Int     // Chỉ số chương hiện tại đang đọc (0-indexed)
    public var durChapterPos: Int       // Vị trí dòng hoặc ký tự đang đọc trong chương
    public var durChapterTime: Int64     // Thời gian đọc gần nhất (timestamp)
    
    public var canUpdate: Bool          // Có thể tự động cập nhật chương mới
    public var isLocal: Bool            // Sách local (TXT, EPUB) được nhập vào
    public var isEpub: Bool             // Sách dạng EPUB
    public var originNameNoCache: String {
        return isLocal ? "Local" : originName
    }
    
    public var wordCount: String?       // Số lượng chữ

    public init(
        bookUrl: String = "",
        tocUrl: String = "",
        name: String = "",
        author: String? = nil,
        coverUrl: String? = nil,
        intro: String? = nil,
        customOrder: Int = 0,
        origin: String = "",
        originName: String = "",
        type: Int = 0,
        group: String? = nil,
        lastChapterTitle: String? = nil,
        lastChapterTime: Int64 = 0,
        durChapterIndex: Int = 0,
        durChapterPos: Int = 0,
        durChapterTime: Int64 = 0,
        canUpdate: Bool = true,
        isLocal: Bool = false,
        isEpub: Bool = false,
        wordCount: String? = nil
    ) {
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.intro = intro
        self.customOrder = customOrder
        self.origin = origin
        self.originName = originName
        self.type = type
        self.group = group
        self.lastChapterTitle = lastChapterTitle
        self.lastChapterTime = lastChapterTime
        self.durChapterIndex = durChapterIndex
        self.durChapterPos = durChapterPos
        self.durChapterTime = durChapterTime
        self.canUpdate = canUpdate
        self.isLocal = isLocal
        self.isEpub = isEpub
        self.wordCount = wordCount
    }
    
    /// Sinh tên thư mục lưu cache của sách
    public func getFolderName() -> String {
        let cleanName = name.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
        let cleanAuthor = (author ?? "").replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
        let key = "\(cleanName)_\(cleanAuthor)"
        return key.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "") ?? key
    }
}
