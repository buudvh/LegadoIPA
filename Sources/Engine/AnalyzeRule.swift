import Foundation
import JavaScriptCore
import SwiftSoup
import Kanna

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
        var context = _jsContext
        if context == nil {
            context = JSContext()
            if let context = context {
                JSBridge.setupContext(context, withBaseUrl: baseUrl, source: source)
                for (key, val) in ruleData {
                    context.setObject(val, forKeyedSubscript: key as NSString)
                }
                _jsContext = context
            }
        }
        lock.unlock()
        return context!
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
    
    // MARK: - Variables Storage (@put / @get)
    
    public func putVariable(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        ruleData[key] = value
        _jsContext?.setObject(value, forKeyedSubscript: key as NSString)
    }
    
    public func getVariable(key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(describing: ruleData[key] ?? "")
    }
    
    // MARK: - GET STRING
    
    /// Trích xuất một chuỗi đơn lẻ từ quy tắc
    public func getString(_ rule: String?, from mContent: Any? = nil) -> String {
        guard let rule = rule, !rule.isEmpty else { return "" }
        
        // 1. Xử lý @get trước khi phân tích quy tắc
        var processedRule = evaluateGetRules(rule)
        
        // 2. Xử lý @put nếu quy tắc chứa @put
        if processedRule.contains("@put:") {
            processPutRules(processedRule, on: mContent ?? self.content)
            processedRule = removePutRules(processedRule)
        }
        
        if processedRule.isEmpty { return "" }
        
        let list = getStringList(processedRule, from: mContent)
        return list.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Trích xuất danh sách các chuỗi từ quy tắc (Hỗ trợ ghép nối &&, ||, @js)
    public func getStringList(_ rule: String?, from mContent: Any? = nil, isListRule: Bool = false) -> [String] {
        guard let rule = rule, !rule.isEmpty else { return [] }
        
        // Xử lý @get trước khi phân tích danh sách
        var processedRule = evaluateGetRules(rule)
        if processedRule.contains("@put:") {
            processPutRules(processedRule, on: mContent ?? self.content)
            processedRule = removePutRules(processedRule)
        }
        
        if processedRule.isEmpty { return [] }
        
        let evalContent = mContent ?? self.content
        guard let evalContent = evalContent else { return [] }
        
        let trimmedRule = processedRule.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
            let subResult = evaluateSingleRule(subRule, on: evalContent, isListRule: isListRule)
            results.append(contentsOf: subResult)
        }
        
        return results
    }
    
    // MARK: - EVALUATE SINGLE RULE
    
    private func evaluateSingleRule(_ rule: String, on content: Any, isListRule: Bool) -> [String] {
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
        
        // Phân loại định dạng nội dung (HTML vs JSON) và bộ lọc (XPath vs Jsoup vs JSONPath)
        let contentStr = String(describing: content)
        let isJson = contentStr.hasPrefix("{") || contentStr.hasPrefix("[")
        let isXPathRule = currentRule.hasPrefix("/") || currentRule.lowercased().hasPrefix("@xpath:")
        
        if isJson {
            results = evaluateJsonRule(currentRule, jsonStr: contentStr)
        } else if isXPathRule {
            results = evaluateXPathRule(currentRule, htmlStr: contentStr)
        } else {
            results = evaluateHtmlRule(currentRule, htmlStr: contentStr, isListRule: isListRule)
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
    
    private func evaluateHtmlRule(_ rule: String, htmlStr: String, isListRule: Bool) -> [String] {
        var cleanRule = rule
        if cleanRule.lowercased().hasPrefix("@css:") {
            cleanRule = String(cleanRule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanRule.hasPrefix("@@") {
            cleanRule = String(cleanRule.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let doc = try? SwiftSoup.parse(htmlStr, baseUrl ?? "") else { return [htmlStr] }
        
        // Chia tách bằng @ để tìm thuộc tính cần lấy (VD: selector@text hoặc selector@href)
        let parts = cleanRule.components(separatedBy: "@")
        let selector = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        
        let defaultAttr = isListRule ? "outerHtml" : "text"
        let attr = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : defaultAttr
        
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
            } else if attr == "outerHtml" {
                if let html = try? element.outerHtml() {
                    results.append(html)
                }
            } else {
                let attrValue = (try? element.attr(attr)) ?? ""
                results.append(attrValue)
            }
        }
        
        return results
    }
    
    // MARK: - XPATH RULE PARSER (Kanna)
    
    private func evaluateXPathRule(_ rule: String, htmlStr: String) -> [String] {
        var xpath = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if xpath.lowercased().hasPrefix("@xpath:") {
            xpath = String(xpath.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let doc = try? Kanna.HTML(html: htmlStr, encoding: .utf8) else { return [htmlStr] }
        
        var results: [String] = []
        let isHtml = xpath.hasSuffix("/@html") || xpath.hasSuffix("/html()")
        if isHtml {
            if xpath.hasSuffix("/@html") {
                xpath = String(xpath.dropLast(6))
            } else {
                xpath = String(xpath.dropLast(7))
            }
        }
        
        let nodes = doc.xpath(xpath)
        for node in nodes {
            if isHtml {
                if let html = node.toHTML {
                    results.append(html)
                }
            } else {
                if let text = node.text {
                    results.append(text)
                } else if let content = node.content {
                    results.append(content)
                }
            }
        }
        
        return results
    }
    
    // MARK: - JSON RULE PARSER (JSContext + customJsonPath)
    
    private func evaluateJsonRule(_ rule: String, jsonStr: String) -> [String] {
        var jsonPath = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonPath.lowercased().hasPrefix("@json:") {
            jsonPath = String(jsonPath.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let escapedJson = jsonStr.jsonEscaped()
        let jsExpression = """
        (function() {
            var _jsonObj = JSON.parse(\(escapedJson));
            var res = customJsonPath(_jsonObj, "\(jsonPath)");
            return res;
        })()
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        let jsVal = jsContext.evaluateScript(jsExpression)
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
        lock.lock()
        defer { lock.unlock() }
        
        jsContext.setObject(result, forKeyedSubscript: "result" as NSString)
        let jsVal = jsContext.evaluateScript(jsCode)
        jsContext.setObject(nil, forKeyedSubscript: "result" as NSString) // Giải phóng tham chiếu
        
        guard let val = jsVal else { return [] }
        
        if val.isArray {
            if let array = val.toArray() {
                return array.map { String(describing: $0) }
            }
        }
        
        let valStr = val.isUndefined || val.isNull ? "" : val.toString() ?? ""
        return valStr.isEmpty ? [] : [valStr]
    }
    
    // MARK: - Get/Put Rules Helpers
    
    private func evaluateGetRules(_ rule: String) -> String {
        var result = rule
        let pattern = "@get:\\{([^}]+?)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return rule }
        
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        
        for match in matches.reversed() {
            guard let totalRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let key = String(result[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let val = getVariable(key)
            result.replaceSubrange(totalRange, with: val)
        }
        return result
    }
    
    private func extractPutJson(from text: String) -> (json: String, range: Range<String.Index>)? {
        guard let startRange = text.range(of: "@put:", options: .caseInsensitive) else { return nil }
        let afterPutIndex = startRange.upperBound
        let remainingText = String(text[afterPutIndex...])
        
        guard let firstBraceIndex = remainingText.firstIndex(of: "{") else { return nil }
        
        var braceDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevChar: Character? = nil
        let chars = Array(remainingText)
        let startOffset = remainingText.distance(from: remainingText.startIndex, to: firstBraceIndex)
        
        for i in startOffset..<chars.count {
            let char = chars[i]
            
            if char == "'" && prevChar != "\\" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && prevChar != "\\" && !inSingleQuote {
                inDoubleQuote.toggle()
            }
            
            let inQuote = inSingleQuote || inDoubleQuote
            if !inQuote {
                if char == "{" { braceDepth += 1 }
                else if char == "}" {
                    braceDepth -= 1
                    if braceDepth == 0 {
                        let endOffset = i
                        let startIndex = remainingText.index(remainingText.startIndex, offsetBy: startOffset)
                        let endIndex = remainingText.index(remainingText.startIndex, offsetBy: endOffset + 1)
                        let jsonContent = String(remainingText[startIndex..<endIndex])
                        
                        // Tính toán range trong text gốc
                        let textEndIndex = text.index(afterPutIndex, offsetBy: endOffset + 1)
                        // Bao gồm cả phần @put:
                        return (jsonContent, startRange.lowerBound..<textEndIndex)
                    }
                }
            }
            prevChar = char
        }
        return nil
    }
    
    private func processPutRules(_ rule: String, on evalContent: Any?) {
        guard let evalContent = evalContent else { return }
        var tempRule = rule
        while let putData = extractPutJson(from: tempRule) {
            let jsonStr = putData.json
            if let jsonData = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                for (key, selector) in dict {
                    let val = getString(selector, from: evalContent)
                    putVariable(key: key, value: val)
                }
            }
            tempRule.replaceSubrange(putData.range, with: "")
        }
    }
    
    private func removePutRules(_ rule: String) -> String {
        var cleanRule = rule
        while let putData = extractPutJson(from: cleanRule) {
            cleanRule.replaceSubrange(putData.range, with: "")
        }
        return cleanRule.trimmingCharacters(in: .whitespacesAndNewlines)
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
