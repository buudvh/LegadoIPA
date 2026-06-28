import Foundation
import JavaScriptCore

/// Phân tích và sinh URLRequest từ biểu mẫu URL cấu hình của Legado (Hỗ trợ nhúng JS {{...}}, JSON options sau dấu phẩy)
public final class AnalyzeUrl {
    
    public var urlStr: String
    private let source: BookSource?
    private var ruleData: [String: Any]
    private var sharedJSContext: JSContext?
    private let lock = NSRecursiveLock()
    
    public var key: String?
    public var page: Int?
    
    public init(urlStr: String, source: BookSource?, ruleData: [String: Any] = [:], key: String? = nil, page: Int? = nil) {
        self.urlStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.key = key
        self.page = page
        
        var mutableRuleData = ruleData
        if let key = key {
            mutableRuleData["key"] = key
        }
        if let page = page {
            mutableRuleData["page"] = page
        }
        self.ruleData = mutableRuleData
    }
    
    /// Sinh URLRequest cuối cùng sau khi phân tích
    public func getRequest() -> URLRequest? {
        var processedUrl = urlStr
        
        // 1. Phân tích các khối JS nội suy {{ java.ajax(...) }} hoặc {{ key }}
        processedUrl = evaluateJSTemplates(in: processedUrl)
        
        // 2. Chia tách URL gốc và phần tùy chọn JSON bổ sung (phân tách bởi dấu phẩy thứ nhất ngoài dấu ngoặc JSON)
        var finalUrlStr = processedUrl
        var jsonOptions: [String: Any]? = nil
        
        if let commaIndex = findOptionComma(in: processedUrl) {
            let urlPart = String(processedUrl[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonPart = String(processedUrl[processedUrl.index(after: commaIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            finalUrlStr = urlPart
            if jsonPart.hasPrefix("{") && jsonPart.hasSuffix("}") {
                if let jsonData = jsonPart.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    jsonOptions = dict
                }
            }
        }
        
        // Thay thế thực thể ký tự nếu có
        finalUrlStr = finalUrlStr.replacingOccurrences(of: "&amp;", with: "&")
        
        guard let url = URL(string: finalUrlStr) else {
            print("AnalyzeUrl Error: URL không hợp lệ: \(finalUrlStr)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        
        // Cài đặt Headers mặc định từ nguồn sách
        if let source = source, let headerJson = source.header {
            if let headerData = headerJson.data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
                for (key, val) in headers {
                    request.setValue(val, forHTTPHeaderField: key)
                }
            }
        }
        
        // 3. Cấu hình các tùy chọn nâng cao từ JSON options (Method, Headers, Body)
        if let options = jsonOptions {
            if let method = options["method"] as? String {
                request.httpMethod = method.uppercased()
            }
            
            if let headers = options["headers"] as? [String: String] {
                for (key, val) in headers {
                    request.setValue(val, forHTTPHeaderField: key)
                }
            }
            
            if let body = options["body"] as? String {
                let evaluatedBody = evaluateJSTemplates(in: body)
                request.httpBody = evaluatedBody.data(using: .utf8)
            } else if let bodyDict = options["body"] as? [String: Any] {
                // Hỗ trợ body dạng form-data / x-www-form-urlencoded
                var parts: [String] = []
                for (key, val) in bodyDict {
                    let valStr = evaluateJSTemplates(in: String(describing: val))
                    if let encKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let encVal = valStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        parts.append("\(encKey)=\(encVal)")
                    }
                }
                request.httpBody = parts.joined(separator: "&").data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        
        return request
    }
    
    // MARK: - JS Template Evaluator
    
    private func evaluateJSTemplates(in text: String) -> String {
        let pattern = "\\{\\{([\\s\\S]*?)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        
        if matches.isEmpty { return text }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Tái sử dụng JSContext trong cùng một request của URL để tránh overhead
        if sharedJSContext == nil {
            guard let context = JSContext() else { return text }
            JSBridge.setupContext(context, withBaseUrl: nil, source: source)
            for (key, val) in ruleData {
                context.setObject(val, forKeyedSubscript: key as NSString)
            }
            sharedJSContext = context
        }
        let jsContext = sharedJSContext!
        
        var result = text
        for match in matches.reversed() {
            guard let totalRange = Range(match.range(at: 0), in: result),
                  let codeRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            
            let jsCode = String(result[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let jsVal = jsContext.evaluateScript(jsCode) {
                let replacement = jsVal.isUndefined || jsVal.isNull ? "" : jsVal.toString() ?? ""
                result.replaceSubrange(totalRange, with: replacement)
            } else {
                result.replaceSubrange(totalRange, with: "")
            }
        }
        
        return result
    }
    
    // MARK: - Option Comma Parser
    
    /// Tìm vị trí dấu phẩy phân tách các tùy chọn JSON của Legado
    private func findOptionComma(in text: String) -> String.Index? {
        let chars = Array(text)
        var bracketDepth = 0
        var braceDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevChar: Character? = nil
        
        for i in 0..<chars.count {
            let char = chars[i]
            
            if char == "'" && prevChar != "\\" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && prevChar != "\\" && !inSingleQuote {
                inDoubleQuote.toggle()
            }
            
            let inQuote = inSingleQuote || inDoubleQuote
            if !inQuote {
                if char == "[" { bracketDepth += 1 }
                else if char == "]" { bracketDepth -= 1 }
                else if char == "{" { braceDepth += 1 }
                else if char == "}" { braceDepth -= 1 }
                else if char == "," {
                    if bracketDepth == 0 && braceDepth == 0 {
                        return text.index(text.startIndex, offsetBy: i)
                    }
                }
            }
            prevChar = char
        }
        return nil
    }
}
