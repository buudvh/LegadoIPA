import Foundation
import CoreText
import UIKit

/// Cấu hình hiển thị trang sách (font, cỡ chữ, lề, khoảng cách dòng)
public struct ReaderConfig: Equatable {
    public var fontSize: CGFloat
    public var fontName: String
    public var textColor: UIColor
    public var lineSpacing: CGFloat
    public var paragraphSpacing: CGFloat
    public var margins: UIEdgeInsets
    
    public init(
        fontSize: CGFloat = 18.0,
        fontName: String = "HelveticaNeue",
        textColor: UIColor = .black,
        lineSpacing: CGFloat = 6.0,
        paragraphSpacing: CGFloat = 12.0,
        margins: UIEdgeInsets = UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20)
    ) {
        self.fontSize = fontSize
        self.fontName = fontName
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.margins = margins
    }
}

/// Bộ phân trang văn bản sử dụng CoreText để tính toán chính xác số trang dựa trên kích thước màn hình
public final class CoreTextPager {
    
    public static let shared = CoreTextPager()
    
    private init() {}
    
    /// Tính toán danh sách các phạm vi (NSRange) cho mỗi trang
    public func paginate(text: String, config: ReaderConfig, boundsSize: CGSize) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        
        let attributedString = createAttributedString(text: text, config: config)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        // Tính toán vùng hiển thị thực tế (trừ đi lề đọc truyện)
        let textWidth = boundsSize.width - config.margins.left - config.margins.right
        let textHeight = boundsSize.height - config.margins.top - config.margins.bottom
        let pageRect = CGRect(x: 0, y: 0, width: textWidth, height: textHeight)
        let path = CGPath(rect: pageRect, transform: nil)
        
        var pages: [NSRange] = []
        var textPos = 0
        let textLength = attributedString.length
        
        while textPos < textLength {
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(textPos, 0), path, nil)
            let stringRange = CTFrameGetVisibleStringRange(frame)
            
            if stringRange.length == 0 {
                // Đề phòng vòng lặp vô hạn nếu kích thước hiển thị quá bé không đủ vẽ 1 ký tự
                break
            }
            
            pages.append(NSRange(location: stringRange.location, length: stringRange.length))
            textPos += stringRange.length
        }
        
        return pages
    }
    
    /// Tạo NSAttributedString từ cấu hình
    public func createAttributedString(text: String, config: ReaderConfig) -> NSAttributedString {
        let font = UIFont(name: config.fontName, size: config.fontSize) ?? UIFont.systemFont(ofSize: config.fontSize)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing
        paragraphStyle.paragraphSpacing = config.paragraphSpacing
        paragraphStyle.alignment = .justified
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: config.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        return NSAttributedString(string: text, attributes: attributes)
    }
}
