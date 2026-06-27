import Foundation
import JavaScriptCore
import SwiftSoup

/// Phân tích và trích xuất dữ liệu từ HTML/JSON dựa trên các quy tắc cấu hình (CSS Selector, XPath, JSONPath, JS, Regex)
public final class AnalyzeRule {
    
    private var content: Any?
    private var baseUrl: String?
    private let source: BookSource?
    private var ruleData: [String: Any]
    
    private let lock = NSRecursiveLock()
    private var _jsContext: JSContext?
    
    // JS context dùng chung để chạy các quy tắc JS
    private var jsContext: JSContext {
        lock.lock()
        defer { lock.unlock() }
        if let context = _jsContext { return context }
        guard let context = JSContext() else {
            fatalError("Failed to create JSContext")
        }
        JSBridge.setupContext(context, withBaseUrl: baseUrl, source: source)
        for (key, val) in ruleData {
            context.setObject(val, forKeyedSubscript: key as NSString)
        }
        _jsContext = context
        return context
    }
    
    public init(content: Any? = nil, baseUrl: String? = nil, source: BookSource? = nil, ruleData: [String: Any] = [:]) {
        self.content = content
        self.baseUrl = baseUrl
        self.source = source
        self.ruleData = ruleData
    }
    
    public func setContent(_ content: Any?, baseUrl: String? = nil) {
        self.content = content
        if let baseUrl = baseUrl {
            self.baseUrl = baseUrl
        }
    }
    
    // MARK: - GET STRING
    
    /// Trích xuất một chuỗi đơn lẻ từ quy tắc
    public func getString(_ rule: String?, from mContent: Any? = nil) -> String {
        let list = getStringList(rule, from: mContent)
        return list.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Trích xuất danh sách các chuỗi từ quy tắc (Hỗ trợ ghép nối &&, ||, @js)
    public func getStringList(_ rule: String?, from mContent: Any? = nil) -> [String] {
        guard let rule = rule, !rule.isEmpty else { return [] }
        let evalContent = mContent ?? self.content
        guard let evalContent = evalContent else { return [] }
        
        let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Nếu quy tắc là khối JavaScript thuần (@js: hoặc <js>)
        if trimmedRule.hasPrefix("@js:") {
            let jsCode = String(trimmedRule.dropFirst(4))
            return executeJS(jsCode, withResult: evalContent)
        } else if trimmedRule.hasPrefix("<js>") && trimmedRule.hasSuffix("</js>") {
            let startIdx = trimmedRule.index(trimmedRule.startIndex, offsetBy: 4)
            let endIdx = trimmedRule.index(trimmedRule.endIndex, offsetBy: -5)
            let jsCode = String(trimmedRule[startIdx..<endIdx])
            return executeJS(jsCode, withResult: evalContent)
        }
        
        // 2. Chia tách các quy tắc nối bằng && hoặc ||
        let analyzer = RuleAnalyzer(data: trimmedRule)
        let subRules = analyzer.splitRule("&&")
        
        var results: [String] = []
        
        for subRule in subRules {
            let subResult = evaluateSingleRule(subRule, on: evalContent)
            results.append(contentsOf: subResult)
        }
        
        return results
    }
    
    // MARK: - EVALUATE SINGLE RULE
    
    private func evaluateSingleRule(_ rule: String, on content: Any) -> [String] {
        var currentRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Xử lý regex thay thế dạng "##regex##replace" ở cuối quy tắc
        var regexReplace: (pattern: String, template: String)? = nil
        if let lastHashRange = currentRule.range(of: "##", options: .backwards) {
            let ruleBody = String(currentRule[..<lastHashRange.lowerBound])
            let suffix = String(currentRule[lastHashRange.upperBound...])
            
            if let firstHashInSuffix = suffix.range(of: "##") {
                let pattern = String(suffix[..<firstHashInSuffix.lowerBound])
                let template = String(suffix[firstHashInSuffix.upperBound...])
                regexReplace = (pattern, template)
                currentRule = ruleBody
            }
        }
        
        var results: [String] = []
        
        // Phân loại định dạng nội dung (HTML vs JSON)
        let contentStr = String(describing: content)
        let isJson = contentStr.hasPrefix("{") || contentStr.hasPrefix("[")
        
        if isJson {
            results = evaluateJsonRule(currentRule, jsonStr: contentStr)
        } else {
            results = evaluateHtmlRule(currentRule, htmlStr: contentStr)
        }
        
        // Áp dụng biểu thức chính quy thay thế nếu có
        if let replacement = regexReplace {
            results = results.map { text in
                if let regex = try? NSRegularExpression(pattern: replacement.pattern, options: []) {
                    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                    return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: replacement.template)
                }
                return text
            }
        }
        
        return results
    }
    
    // MARK: - HTML RULE PARSER (SwiftSoup)
    
    private func evaluateHtmlRule(_ rule: String, htmlStr: String) -> [String] {
        guard let doc = try? SwiftSoup.parse(htmlStr, baseUrl ?? "") else { return [htmlStr] }
        
        // Chia tách bằng @ để tìm thuộc tính cần lấy (VD: selector@text hoặc selector@href)
        let parts = rule.components(separatedBy: "@")
        let selector = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let attr = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : "text"
        
        // Nếu không có selector, lấy trực tiếp trên document root
        let elements: Elements
        if selector.isEmpty {
            elements = Elements([doc])
        } else {
            elements = (try? doc.select(selector)) ?? Elements()
        }
        
        var results: [String] = []
        for element in elements.array() {
            if attr == "text" {
                if let txt = try? element.text() {
                    results.append(txt)
                }
            } else if attr == "html" {
                if let html = try? element.html() {
                    results.append(html)
                }
            } else {
                let attrValue = (try? element.attr(attr)) ?? ""
                results.append(attrValue)
            }
        }
        
        return results
    }
    
    // MARK: - JSON RULE PARSER (JSContext)
    
    private func evaluateJsonRule(_ rule: String, jsonStr: String) -> [String] {
        var jsPath = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsPath.hasPrefix("$.") {
            jsPath = "_jsonObj." + jsPath.dropFirst(2)
        } else if jsPath.hasPrefix("$[") {
            jsPath = "_jsonObj" + jsPath.dropFirst(1)
        } else if jsPath == "$" {
            jsPath = "_jsonObj"
        }
        
        // Xử lý [*] -> map lấy thuộc tính
        jsPath = jsPath.replacingOccurrences(of: "[*]", with: "")
        
        // Sửa lỗi phình RAM: Chạy trong IIFE để tránh lưu trữ _jsonObj ở scope global của JSContext
        let escapedJson = jsonStr.jsonEscaped()
        let jsExpression = """
        (function() {
            var _jsonObj = JSON.parse(\(escapedJson));
            return \(jsPath);
        })()
        """
        
        let jsVal: JSValue?
        lock.lock()
        jsVal = jsContext.evaluateScript(jsExpression)
        lock.unlock()
        
        guard let val = jsVal else { return [] }
        
        if val.isArray {
            if let array = val.toArray() {
                return array.map { String(describing: $0) }
            }
        }
        
        let valStr = val.isUndefined || val.isNull ? "" : val.toString() ?? ""
        return valStr.isEmpty ? [] : [valStr]
    }
    
    // MARK: - JS EXECUTION
    
    private func executeJS(_ jsCode: String, withResult result: Any) -> [String] {
        let jsVal: JSValue?
        lock.lock()
        jsContext.setObject(result, forKeyedSubscript: "result" as NSString)
        jsVal = jsContext.evaluateScript(jsCode)
        jsContext.setObject(nil, forKeyedSubscript: "result" as NSString) // Giải phóng tham chiếu
        lock.unlock()
        
        guard let val = jsVal else { return [] }
        
        if val.isArray {
            if let array = val.toArray() {
                return array.map { String(describing: $0) }
            }
        }
        
        let valStr = val.isUndefined || val.isNull ? "" : val.toString() ?? ""
        return valStr.isEmpty ? [] : [valStr]
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
