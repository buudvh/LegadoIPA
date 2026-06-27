import Foundation

/// Đại diện cho một Chương của Sách (BookChapter)
public struct BookChapter: Codable, Identifiable, Equatable {
    public var id: String { "\(bookUrl)_\(index)" }
    
    public var bookUrl: String     // URL sách sở hữu chương này
    public var index: Int          // Vị trí thứ tự chương (0-indexed)
    public var title: String       // Tiêu đề chương
    public var url: String         // URL nội dung chương
    
    public var isVolume: Bool      // Là mục phân quyển/cuốn (không chứa nội dung)
    public var isVip: Bool         // Chương VIP
    public var isPay: Bool         // Chương cần thanh toán
    
    public var start: Int64?       // Điểm bắt đầu đọc từ file local
    public var end: Int64?         // Điểm kết thúc đọc từ file local

    public init(
        bookUrl: String = "",
        index: Int = 0,
        title: String = "",
        url: String = "",
        isVolume: Bool = false,
        isVip: Bool = false,
        isPay: Bool = false,
        start: Int64? = nil,
        end: Int64? = nil
    ) {
        self.bookUrl = bookUrl
        self.index = index
        self.title = title
        self.url = url
        self.isVolume = isVolume
        self.isVip = isVip
        self.isPay = isPay
        self.start = start
        self.end = end
    }
}
