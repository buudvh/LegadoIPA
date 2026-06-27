import Foundation

/// Chứa nội dung văn bản của một chương sách đã tải về và xử lý
public struct BookContent: Codable, Equatable {
    public var sameTitleRemoved: Bool              // Đã loại bỏ tiêu đề trùng lặp trong nội dung chương
    public var textList: [String]                  // Danh sách các dòng văn bản (đoạn văn)
    public var effectiveReplaceRules: [ReplaceRule]? // Các quy tắc thay thế hiệu dụng đã áp dụng

    public var text: String {
        return textList.joined(separator: "\n")
    }

    public init(
        sameTitleRemoved: Bool = false,
        textList: [String] = [],
        effectiveReplaceRules: [ReplaceRule]? = nil
    ) {
        self.sameTitleRemoved = sameTitleRemoved
        self.textList = textList
        self.effectiveReplaceRules = effectiveReplaceRules
    }
}
