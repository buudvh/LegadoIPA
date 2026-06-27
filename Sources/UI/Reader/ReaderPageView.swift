import Foundation
import UIKit
import SwiftUI
import CoreText

/// UIView hiển thị trực quan một trang sách sử dụng CoreText
public final class CoreTextPageView: UIView {
    
    public var attributedString: NSAttributedString? {
        didSet {
            setNeedsDisplay()
        }
    }
    
    public var range: NSRange = NSRange(location: 0, length: 0) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    public var margins: UIEdgeInsets = .zero {
        didSet {
            setNeedsDisplay()
        }
    }
    
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let attributedString = attributedString else { return }
        
        // Đảo ngược hệ trục tọa độ của CGContext (CoreText sử dụng Y-up, UIKit sử dụng Y-down)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Tính toán khung vẽ trừ lề
        let textWidth = bounds.size.width - margins.left - margins.right
        let textHeight = bounds.size.height - margins.top - margins.bottom
        
        // Tạo khung vẽ (lưu ý: Y trong hệ trục đã lật ngược thì lề top sẽ ở phía đáy, lề bottom ở phía đỉnh)
        let pageRect = CGRect(
            x: margins.left,
            y: margins.bottom,
            width: textWidth,
            height: textHeight
        )
        
        let path = CGPath(rect: pageRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(range.location, range.length), path, nil)
        
        // Vẽ khung chữ lên màn hình
        CTFrameDraw(frame, context)
    }
}

/// Bọc CoreTextPageView sang môi trường SwiftUI (UIViewRepresentable)
public struct ReaderPageViewRepresentable: UIViewRepresentable {
    
    public let text: String
    public let range: NSRange
    public let config: ReaderConfig
    
    public init(text: String, range: NSRange, config: ReaderConfig) {
        self.text = text
        self.range = range
        self.config = config
    }
    
    public func makeUIView(context: Context) -> CoreTextPageView {
        let view = CoreTextPageView()
        view.backgroundColor = .clear
        updateViewData(view)
        return view
    }
    
    public func updateUIView(_ uiView: CoreTextPageView, context: Context) {
        updateViewData(uiView)
    }
    
    private func updateViewData(_ view: CoreTextPageView) {
        let attrString = CoreTextPager.shared.createAttributedString(text: text, config: config)
        view.attributedString = attrString
        view.range = range
        view.margins = config.margins
    }
}
