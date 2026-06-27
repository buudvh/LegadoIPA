import Foundation

/// Thực thể lưu trữ quy tắc thay thế văn bản (ReplaceRule) để lọc quảng cáo, sửa lỗi chính tả
public struct ReplaceRule: Codable, Identifiable, Equatable {
    public var id: String?          // Mã định danh quy tắc (UUID String)
    public var name: String          // Tên quy tắc lọc
    
    public var pattern: String       // Chuỗi tìm kiếm (chuỗi thường hoặc biểu thức chính quy)
    public var replacement: String   // Chuỗi thay thế
    public var enabled: Bool         // Có kích hoạt hay không
    public var isRegex: Bool         // Có sử dụng Regular Expression
    
    public var scope: String?        // Phạm vi áp dụng (các bookSourceUrl cách nhau bằng dấu phẩy)
    public var customOrder: Int      // Thứ tự ưu tiên chạy bộ lọc

    public init(
        id: String? = nil,
        name: String = "",
        pattern: String = "",
        replacement: String = "",
        enabled: Bool = true,
        isRegex: Bool = true,
        scope: String? = nil,
        customOrder: Int = 0
    ) {
        self.id = id ?? UUID().uuidString
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.enabled = enabled
        self.isRegex = isRegex
        self.scope = scope
        self.customOrder = customOrder
    }
}
