import Foundation
import JavaScriptCore
import SwiftSoup

@objc protocol JSResponseExport: JSExport {
    var status: Int { get }
    var ok: Bool { get }
    func text() -> String
    func text(_ charset: String) -> String
    func json() -> JSValue
    func html() -> JSValue
    func html(_ charset: String) -> JSValue
}

/// Lớp giả lập HTTP Response trả về cho JavaScript
public final class JS_Response: NSObject, JSResponseExport {
    public let status: Int
    public let ok: Bool
    private let data: Data
    private let context: JSContext
    
    public init(status: Int, data: Data, context: JSContext) {
        self.status = status
        self.ok = (200...299).contains(status)
        self.data = data
        self.context = context
    }
    
    public func text() -> String {
        // Tự động nhận diện UTF-8 hoặc ASCII
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
    }
    
    public func text(_ charset: String) -> String {
        let cfEnc = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if cfEnc != kCFStringEncodingInvalidId {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
            if let str = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                return str
            }
        }
        return text()
    }
    
    public func json() -> JSValue {
        let textStr = text()
        // Evaluate JSON parse an toàn thông qua JS engine để trả về JSValue hợp lệ
        let jsonExpression = "JSON.parse(\(textStr.jsonEscaped()))"
        return context.evaluateScript(jsonExpression) ?? JSValue(undefinedIn: context)
    }
    
    public func html() -> JSValue {
        return JS_Document.parse(text(), context: context)
    }
    
    public func html(_ charset: String) -> JSValue {
        return JS_Document.parse(text(charset), context: context)
    }
}

@objc protocol JSDocumentExport: JSExport {
    func select(_ selector: String) -> [JS_Element]
    func selectFirst(_ selector: String) -> JS_Element?
    func text() -> String
    func html() -> String
    func outerHtml() -> String
}

/// Lớp giả lập Document (DOM Root) tương thích Jsoup
public final class JS_Document: NSObject, JSDocumentExport {
    public let document: Document
    private let context: JSContext
    
    public init(_ document: Document, context: JSContext) {
        self.document = document
        self.context = context
    }
    
    public static func parse(_ html: String, context: JSContext) -> JSValue {
        if let doc = try? SwiftSoup.parse(html) {
            let jsDoc = JS_Document(doc, context: context)
            return JSValue(object: jsDoc, in: context)
        }
        return JSValue(nullIn: context)
    }
    
    public func select(_ selector: String) -> [JS_Element] {
        guard let elements = try? document.select(selector) else { return [] }
        return elements.array().map { JS_Element($0, context: context) }
    }
    
    public func selectFirst(_ selector: String) -> JS_Element? {
        guard let element = try? document.select(selector).first() else { return nil }
        return JS_Element(element, context: context)
    }
    
    public func text() -> String {
        return (try? document.text()) ?? ""
    }
    
    public func html() -> String {
        return (try? document.html()) ?? ""
    }
    
    public func outerHtml() -> String {
        return (try? document.outerHtml()) ?? ""
    }
}

@objc protocol JSElementExport: JSExport {
    func select(_ selector: String) -> [JS_Element]
    func selectFirst(_ selector: String) -> JS_Element?
    func text() -> String
    func html() -> String
    func outerHtml() -> String
    func attr(_ name: String) -> String
    func remove()
}

/// Lớp giả lập Element (DOM Node) tương thích Jsoup
public final class JS_Element: NSObject, JSElementExport {
    public let element: Element
    private let context: JSContext
    
    public init(_ element: Element, context: JSContext) {
        self.element = element
        self.context = context
    }
    
    public func select(_ selector: String) -> [JS_Element] {
        guard let elements = try? element.select(selector) else { return [] }
        return elements.array().map { JS_Element($0, context: context) }
    }
    
    public func selectFirst(_ selector: String) -> JS_Element? {
        guard let firstEl = try? element.select(selector).first() else { return nil }
        return JS_Element(firstEl, context: context)
    }
    
    public func text() -> String {
        return (try? element.text()) ?? ""
    }
    
    public func html() -> String {
        return (try? element.html()) ?? ""
    }
    
    public func outerHtml() -> String {
        return (try? element.outerHtml()) ?? ""
    }
    
    public func attr(_ name: String) -> String {
        return (try? element.attr(name)) ?? ""
    }
    
    public func remove() {
        try? element.remove()
    }
}

// MARK: - String Extension Helper
extension String {
    fileprivate func jsonEscaped() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [self], options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        let length = str.count
        return String(str[str.index(str.startIndex, offsetBy: 1)..<str.index(str.startIndex, offsetBy: length - 1)])
    }
}
