import Foundation
import JavaScriptCore
import CryptoKit
import SwiftSoup

// MARK: - Jsoup JSExport Protocols
@objc protocol JsoupElementExport: JSExport {
    func select(_ selector: String) -> JSJsoupElementList
    func text() -> String
    func html() -> String
    func attr(_ key: String) -> String
    func toString() -> String
}

@objc protocol JsoupElementListExport: JSExport {
    func toArray() -> [JSJsoupElement]
    func select(_ selector: String) -> JSJsoupElementList
    func text() -> String
    func html() -> String
    func attr(_ key: String) -> String
    func size() -> Int
    func get(_ index: Int) -> JSJsoupElement?
}

// MARK: - Jsoup Wrappers for JS
@objc class JSJsoupElement: NSObject, JsoupElementExport {
    var element: Element?
    
    init(element: Element) {
        self.element = element
    }
    
    init(html: String) {
        self.element = try? SwiftSoup.parse(html)
    }
    
    func select(_ selector: String) -> JSJsoupElementList {
        guard let element = element,
              let elements = try? element.select(selector) else {
            return JSJsoupElementList(elements: [])
        }
        return JSJsoupElementList(elements: elements.array())
    }
    
    func text() -> String {
        return (try? element?.text()) ?? ""
    }
    
    func html() -> String {
        return (try? element?.html()) ?? ""
    }
    
    func attr(_ key: String) -> String {
        return (try? element?.attr(key)) ?? ""
    }
    
    func toString() -> String {
        return (try? element?.outerHtml()) ?? ""
    }
}

@objc class JSJsoupElementList: NSObject, JsoupElementListExport {
    var elements: [Element]
    
    init(elements: [Element]) {
        self.elements = elements
    }
    
    func toArray() -> [JSJsoupElement] {
        return elements.map { JSJsoupElement(element: $0) }
    }
    
    func select(_ selector: String) -> JSJsoupElementList {
        var subElements: [Element] = []
        for el in elements {
            if let sub = try? el.select(selector) {
                subElements.append(contentsOf: sub.array())
            }
        }
        return JSJsoupElementList(elements: subElements)
    }
    
    func text() -> String {
        return elements.map { (try? $0.text()) ?? "" }.joined(separator: " ")
    }
    
    func html() -> String {
        return elements.map { (try? $0.html()) ?? "" }.joined(separator: "\n")
    }
    
    func attr(_ key: String) -> String {
        return elements.compactMap { try? $0.attr(key) }.first ?? ""
    }
    
    func size() -> Int {
        return elements.count
    }
    
    func get(_ index: Int) -> JSJsoupElement? {
        guard index >= 0 && index < elements.count else { return nil }
        return JSJsoupElement(element: elements[index])
    }
}

// MARK: - Cookie JSExport Protocol
@objc protocol CookieExport: JSExport {
    func getCookie(_ url: String) -> String
    func setCookie(_ url: String, _ value: String)
    func removeCookie(_ url: String)
}

// MARK: - Cookie Bridge for JS
@objc class JSCookieBridge: NSObject, CookieExport {
    func getCookie(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr) else { return "" }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    
    func setCookie(_ urlStr: String, _ value: String) {
        guard let url = URL(string: urlStr), let host = url.host else { return }
        let parts = value.components(separatedBy: ";")
        for part in parts {
            let keyValue = part.components(separatedBy: "=")
            if keyValue.count == 2 {
                let name = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let val = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: val,
                    .domain: host,
                    .path: "/"
                ]) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
    }
    
    func removeCookie(_ urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies(for: url) {
            for cookie in cookies {
                storage.deleteCookie(cookie)
            }
        }
    }
    }
}

// MARK: - Response Wrapper cho JS (startBrowserAwait / ajax)
@objc protocol JSResponseExport: JSExport {
    func body() -> String
    func toString() -> String
}

@objc class JSResponseObj: NSObject, JSResponseExport {
    private var html: String
    
    init(html: String) {
        self.html = html
    }
    
    func body() -> String {
        return html
    }
    
    func toString() -> String {
        return html
    }
}

// MARK: - Main JSBridge
/// Cầu nối tiêm các đối tượng và phương thức hữu ích từ Swift vào môi trường JavaScriptCore
public final class JSBridge {
    
    /// Đăng ký các hàm mở rộng vào JSContext
    public static func setupContext(_ context: JSContext, withBaseUrl baseUrl: String?, source: BookSource?) {
        let bridge = JSBridge()
        
        // Tiêm đối tượng "java" vào context để tương thích các nguồn sách cũ của Android
        let javaObject = JSValue(newObjectIn: context)
        context.setObject(javaObject, forKeyedSubscript: "java" as NSString)
        
        // Đăng ký các phương thức của Bridge lên đối tượng "java" và phạm vi toàn cục (global)
        
        // 1. AJAX request (Đồng bộ qua Semaphore)
        let ajaxBlock: @convention(block) (String) -> JSResponseObj? = { urlStr in
            if let resStr = bridge.syncAjax(url: urlStr, baseUrl: baseUrl, source: source) {
                return JSResponseObj(html: resStr)
            }
            return nil
        }
        javaObject?.setObject(ajaxBlock, forKeyedSubscript: "ajax" as NSString)
        context.setObject(ajaxBlock, forKeyedSubscript: "ajax" as NSString)
        
        // 2. MD5 Encode
        let md5Block: @convention(block) (String) -> String = { str in
            return bridge.md5Encode(str)
        }
        javaObject?.setObject(md5Block, forKeyedSubscript: "md5Encode" as NSString)
        javaObject?.setObject(md5Block, forKeyedSubscript: "md5Encode16" as NSString) // Fallback
        context.setObject(md5Block, forKeyedSubscript: "md5Encode" as NSString)
        
        // 3. Base64 Encode/Decode
        let base64EncodeBlock: @convention(block) (String) -> String = { str in
            return Data(str.utf8).base64EncodedString()
        }
        let base64DecodeBlock: @convention(block) (String) -> String = { base64Str in
            guard let data = Data(base64Encoded: base64Str),
                  let decoded = String(data: data, encoding: .utf8) else {
                return ""
            }
            return decoded
        }
        javaObject?.setObject(base64EncodeBlock, forKeyedSubscript: "base64Encode" as NSString)
        javaObject?.setObject(base64DecodeBlock, forKeyedSubscript: "base64Decode" as NSString)
        context.setObject(base64EncodeBlock, forKeyedSubscript: "base64Encode" as NSString)
        context.setObject(base64DecodeBlock, forKeyedSubscript: "base64Decode" as NSString)
        
        // 4. URL Encode/Decode
        let urlEncodeBlock: @convention(block) (String) -> String = { str in
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=?/") // Bắt buộc mã hóa các kí tự này trong parameter value
            return str.addingPercentEncoding(withAllowedCharacters: allowed) ?? str
        }
        let urlDecodeBlock: @convention(block) (String) -> String = { str in
            return str.removingPercentEncoding ?? str
        }
        javaObject?.setObject(urlEncodeBlock, forKeyedSubscript: "utf8Encode" as NSString)
        javaObject?.setObject(urlDecodeBlock, forKeyedSubscript: "utf8Decode" as NSString)
        context.setObject(urlEncodeBlock, forKeyedSubscript: "utf8Encode" as NSString)
        context.setObject(urlDecodeBlock, forKeyedSubscript: "utf8Decode" as NSString)
        
        // 5. Console Log
        let logBlock: @convention(block) (String) -> Void = { msg in
            print("[JS Logger] \(msg)")
        }
        javaObject?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        context.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        
        // 6. Giản thể <=> Phồn thể
        let t2sBlock: @convention(block) (String) -> String = { text in
            return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        }
        let s2tBlock: @convention(block) (String) -> String = { text in
            return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
        }
        javaObject?.setObject(t2sBlock, forKeyedSubscript: "t2s" as NSString)
        javaObject?.setObject(s2tBlock, forKeyedSubscript: "s2t" as NSString)
        context.setObject(t2sBlock, forKeyedSubscript: "t2s" as NSString)
        context.setObject(s2tBlock, forKeyedSubscript: "s2t" as NSString)
        
        // 7. Toast Notification (gửi qua NotificationCenter)
        let toastBlock: @convention(block) (String) -> Void = { msg in
            print("[JS Toast] \(msg)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowToastNotification"),
                    object: nil,
                    userInfo: ["message": msg]
                )
            }
        }
        javaObject?.setObject(toastBlock, forKeyedSubscript: "toast" as NSString)
        context.setObject(toastBlock, forKeyedSubscript: "toast" as NSString)
        
        // 8. Giả lập Jsoup (org.jsoup.Jsoup)
        let orgObject = JSValue(newObjectIn: context)
        let jsoupObject = JSValue(newObjectIn: context)
        let jsoupClass = JSValue(newObjectIn: context)
        let parseBlock: @convention(block) (String) -> JSJsoupElement = { html in
            return JSJsoupElement(html: html)
        }
        jsoupClass?.setObject(parseBlock, forKeyedSubscript: "parse" as NSString)
        jsoupObject?.setObject(jsoupClass, forKeyedSubscript: "Jsoup" as NSString)
        orgObject?.setObject(jsoupObject, forKeyedSubscript: "jsoup" as NSString)
        context.setObject(orgObject, forKeyedSubscript: "org" as NSString)
        
        // 9. Giả lập đối tượng cookie
        let cookieBridge = JSCookieBridge()
        context.setObject(cookieBridge, forKeyedSubscript: "cookie" as NSString)
        
        // 9.1 startBrowserAwait để hiển thị popup WebView giải khiên Cloudflare
        let startBrowserBlock: @convention(block) (String, String) -> JSResponseObj? = { urlStr, titleStr in
            if let resStr = bridge.startBrowserAwait(url: urlStr, title: titleStr) {
                return JSResponseObj(html: resStr)
            }
            return nil
        }
        javaObject?.setObject(startBrowserBlock, forKeyedSubscript: "startBrowserAwait" as NSString)
        context.setObject(startBrowserBlock, forKeyedSubscript: "startBrowserAwait" as NSString)
        
        // 9.2 Đăng ký bổ sung các hàm java.put/get/md5/base64/cookie cho đối tượng java
        let putBlock: @convention(block) (String, String) -> Void = { key, val in
            AnalyzeRule.putGlobalVariable(key: key, value: val)
        }
        let getBlock: @convention(block) (String) -> String = { key in
            return AnalyzeRule.getGlobalVariable(key)
        }
        javaObject?.setObject(putBlock, forKeyedSubscript: "put" as NSString)
        javaObject?.setObject(getBlock, forKeyedSubscript: "get" as NSString)
        context.setObject(putBlock, forKeyedSubscript: "put" as NSString)
        context.setObject(getBlock, forKeyedSubscript: "get" as NSString)
        
        javaObject?.setObject(md5Block, forKeyedSubscript: "md5" as NSString)
        javaObject?.setObject(base64EncodeBlock, forKeyedSubscript: "base64" as NSString)
        context.setObject(md5Block, forKeyedSubscript: "md5" as NSString)
        context.setObject(base64EncodeBlock, forKeyedSubscript: "base64" as NSString)
        
        let getCookieBlock: @convention(block) (String) -> String = { url in
            return cookieBridge.getCookie(url)
        }
        let setCookieBlock: @convention(block) (String, String) -> Void = { url, val in
            cookieBridge.setCookie(url, val)
        }
        javaObject?.setObject(getCookieBlock, forKeyedSubscript: "getCookie" as NSString)
        javaObject?.setObject(setCookieBlock, forKeyedSubscript: "setCookie" as NSString)
        context.setObject(getCookieBlock, forKeyedSubscript: "getCookie" as NSString)
        context.setObject(setCookieBlock, forKeyedSubscript: "setCookie" as NSString)
        
        // 10. Nạp hàm helper customJsonPath để hỗ trợ JSONPath của Android
        let jsonPathScript = """
        function customJsonPath(obj, path) {
            if (path === '$' || path === '') return obj;
            
            // 1. Loại bỏ $. ở đầu
            var cleanPath = path.replace(/^\\$\\.?/, '');
            
            // 2. Chia tách bằng dấu chấm nhưng bỏ qua dấu chấm trong ngoặc vuông [...]
            var parts = [];
            var temp = "";
            var inBracket = 0;
            for (var i = 0; i < cleanPath.length; i++) {
                var c = cleanPath[i];
                if (c === '[') inBracket++;
                else if (c === ']') inBracket--;
                
                if (c === '.' && inBracket === 0) {
                    if (temp !== "") {
                        parts.push(temp);
                        temp = "";
                    }
                } else {
                    temp += c;
                }
            }
            if (temp !== "") {
                parts.push(temp);
            }
            
            var current = obj;
            for (var i = 0; i < parts.length; i++) {
                var part = parts[i].trim();
                if (!part) continue;
                
                // Phân tích nếu part chứa ngoặc vuông (VD: books[0] hoặc books[*])
                var bracketStart = part.indexOf('[');
                if (bracketStart > -1) {
                    var key = part.slice(0, bracketStart).trim();
                    var bracketExpr = part.slice(bracketStart).trim(); // "[0]", "[*]", "[?(@.author == 'abc')]"
                    
                    if (key !== "") {
                        if (Array.isArray(current)) {
                            current = current.map(function(item) { return item[key]; }).filter(function(x) { return x !== undefined && x !== null; });
                        } else {
                            current = current[key];
                        }
                    }
                    if (current === undefined || current === null) return null;
                    
                    // Giải quyết các biểu thức ngoặc vuông liên tiếp (VD: [0][1] hoặc [*][?(@.id)])
                    var match;
                    var bracketRegex = /\\[([^\\]]+?)\\]/g;
                    while ((match = bracketRegex.exec(bracketExpr)) !== null) {
                        var expr = match[1].trim();
                        if (expr === '*') {
                            if (Array.isArray(current)) {
                                // Gom toàn bộ phần tử mảng và tiếp tục các part sau
                                var nextParts = parts.slice(i + 1);
                                var remainingBrackets = bracketExpr.slice(bracketRegex.lastIndex).trim();
                                var nextPath = (remainingBrackets ? remainingBrackets : "") + (nextParts.length > 0 ? (remainingBrackets ? "." : "") + nextParts.join('.') : "");
                                var res = [];
                                current.forEach(function(item) {
                                    var val = customJsonPath(item, '$' + (nextPath ? '.' + nextPath : ''));
                                    if (val !== undefined && val !== null) {
                                        if (Array.isArray(val)) res = res.concat(val);
                                        else res.push(val);
                                    }
                                });
                                return res;
                            }
                        } else if (expr.startsWith('?(') && expr.endsWith(')')) {
                            var filterExpr = expr.slice(2, -1);
                            if (Array.isArray(current)) {
                                current = current.filter(function(item) {
                                    try {
                                        var jsExpr = filterExpr.replace(/@/g, 'item');
                                        return eval('(function(item){ return ' + jsExpr + '; })(item)');
                                    } catch(e) { return false; }
                                });
                            }
                        } else {
                            var idx = parseInt(expr);
                            if (!isNaN(idx)) {
                                if (Array.isArray(current)) {
                                    current = current[idx];
                                } else {
                                    current = current[expr];
                                }
                            } else {
                                // Lấy key dạng ['key'] hoặc "key"
                                var cleanKey = expr.replace(/^['\"]|['\"]$/g, '');
                                if (Array.isArray(current)) {
                                    current = current.map(function(item) { return item[cleanKey]; }).filter(function(x) { return x !== undefined && x !== null; });
                                } else {
                                    current = current[cleanKey];
                                }
                            }
                        }
                        if (current === undefined || current === null) return null;
                    }
                } else {
                    // Không chứa ngoặc vuông (VD: name)
                    if (Array.isArray(current)) {
                        current = current.map(function(item) { return item[part]; }).filter(function(x) { return x !== undefined && x !== null; });
                    } else {
                        current = current[part];
                    }
                }
                if (current === undefined || current === null) return null;
            }
            return current;
        }
        """
        context.evaluateScript(jsonPathScript)
        
        // Tiêm các biến môi trường
        if let baseUrl = baseUrl {
            context.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
            javaObject?.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        }
    }
    
    // MARK: - Internal Operations
    
    private func syncAjax(url: String, baseUrl: String?, source: BookSource?) -> String? {
        if Thread.isMainThread {
            print("[JSBridge Error] syncAjax được gọi trên Main Thread! Hủy bỏ để tránh deadlock giao diện.")
            return nil
        }
        
        var absoluteURLStr = url
        
        // Xử lý URL tương đối
        if let baseUrl = baseUrl, !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            if let base = URL(string: baseUrl), let absURL = URL(string: url, relativeTo: base) {
                absoluteURLStr = absURL.absoluteString
            }
        }
        
        guard let urlObj = URL(string: absoluteURLStr) else { return nil }
        var request = URLRequest(url: urlObj, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        request.httpMethod = "GET"
        
        // Tiêm cấu hình User-Agent hoặc Headers mặc định từ nguồn sách
        if let source = source, let headerJson = source.header {
            if let headerData = headerJson.data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
                for (key, val) in headers {
                    request.setValue(val, forHTTPHeaderField: key)
                }
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: String? = nil
        
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                result = self.decodeResponseData(data)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10.0) // Chờ tối đa 10 giây
        
        return result
    }
    
    fileprivate func startBrowserAwait(url: String, title: String) -> String? {
        if Thread.isMainThread {
            print("[JSBridge Error] startBrowserAwait được gọi trên Main Thread! Hủy bỏ để tránh deadlock.")
            return nil
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var htmlResult: String? = nil
        
        DispatchQueue.main.async {
            // Phát notification để UI hiển thị BottomWebViewDialog
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowWebViewVerificationNotification"),
                object: nil,
                userInfo: [
                    "url": url,
                    "title": title,
                    "completion": { (html: String?) in
                        htmlResult = html
                        semaphore.signal()
                    } as (String?) -> Void
                ]
            )
        }
        
        // Chờ người dùng giải khiên (tối đa 180 giây - 3 phút)
        _ = semaphore.wait(timeout: .now() + 180.0)
        return htmlResult
    }
    
    private func md5Encode(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    fileprivate func decodeResponseData(_ data: Data) -> String {
        if let utf8Str = String(data: data, encoding: .utf8) {
            return utf8Str
        }
        let gbkEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let gbkStr = String(data: data, encoding: String.Encoding(rawValue: gbkEncoding)) {
            return gbkStr
        }
        if let winStr = String(data: data, encoding: .windowsCP1252) {
            return winStr
        }
        return String(data: data, encoding: .ascii) ?? ""
    }
}
