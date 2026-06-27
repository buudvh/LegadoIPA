import Foundation
import JavaScriptCore
import SwiftSoup

/// Nhân chạy mã nguồn JavaScript của Extension trên nền JavaScriptCore nguyên bản của iOS
public final class VBookExtensionEngine {
    
    public let extensionId: String
    
    public init(extensionId: String) {
        self.extensionId = extensionId
    }
    
    /// Thiết lập các đối tượng và hàm toàn cục cho JSContext
    private func setupGlobals(context: JSContext) {
        // 1. Đối tượng Html (parse, clean)
        let htmlObj = JSValue(newObjectIn: context)
        
        let parseBlock: @convention(block) (String) -> JSValue = { html in
            return JS_Document.parse(html, context: context)
        }
        
        let cleanBlock: @convention(block) (String, [String]) -> String = { html, tags in
            let whitelist = Whitelist.none()
            for tag in tags {
                _ = try? whitelist.addTags(tag)
            }
            return (try? SwiftSoup.clean(html, whitelist)) ?? ""
        }
        
        htmlObj?.setObject(parseBlock, forKeyedSubscript: "parse" as NSString)
        htmlObj?.setObject(cleanBlock, forKeyedSubscript: "clean" as NSString)
        context.setObject(htmlObj, forKeyedSubscript: "Html" as NSString)
        
        // 2. Đối tượng Response (success, error)
        let responseObj = JSValue(newObjectIn: context)
        
        let successBlock: @convention(block) (JSValue, JSValue?) -> JSValue = { data, next in
            let res = JSValue(newObjectIn: context)
            res?.setObject(data, forKeyedSubscript: "data" as NSString)
            if let next = next, !next.isUndefined, !next.isNull {
                res?.setObject(next, forKeyedSubscript: "next" as NSString)
            }
            return res!
        }
        
        let errorBlock: @convention(block) (String) -> JSValue = { message in
            let res = JSValue(newObjectIn: context)
            res?.setObject(message, forKeyedSubscript: "error" as NSString)
            return res!
        }
        
        responseObj?.setObject(successBlock, forKeyedSubscript: "success" as NSString)
        responseObj?.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
        context.setObject(responseObj, forKeyedSubscript: "Response" as NSString)
        
        // 3. Hàm load(filename) toàn cục
        let loadBlock: @convention(block) (String) -> Void = { [weak self] filename in
            guard let self = self else { return }
            let extensionsDir = VBookExtensionManager.shared.extensionsDirectoryURL
            let fileURL = extensionsDir.appendingPathComponent(self.extensionId).appendingPathComponent("src").appendingPathComponent(filename)
            
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                _ = context.evaluateScript(content)
            } else {
                // Fallback tìm ở thư mục ngoài
                let outerFileURL = extensionsDir.appendingPathComponent(self.extensionId).appendingPathComponent(filename)
                if let outerContent = try? String(contentsOf: outerFileURL, encoding: .utf8) {
                    _ = context.evaluateScript(outerContent)
                }
            }
        }
        context.setObject(loadBlock, forKeyedSubscript: "load" as NSString)
        
        // 4. Hàm fetch(url, options) đồng bộ toàn cục
        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { urlStr, options in
            let trimmed = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
            let encodedStr = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let finalUrl = URL(string: trimmed) ?? URL(string: encodedStr)
            
            guard let url = finalUrl else {
                return JSValue(nullIn: context)
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            // 1. Đồng bộ cookie từ Webview sang Storage trước khi gửi
            let semaphoreCookie = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await NetworkManager.shared.syncCookiesFromWebViewToStorage()
                semaphoreCookie.signal()
            }
            _ = semaphoreCookie.wait(timeout: .now() + 2.0) // Timeout chờ đồng bộ cookie
            
            if let options = options, !options.isUndefined, !options.isNull {
                if let method = options.objectForKeyedSubscript("method")?.toString() {
                    request.httpMethod = method.uppercased()
                }
                
                if let headersVal = options.objectForKeyedSubscript("headers"), !headersVal.isUndefined, !headersVal.isNull {
                    if let headersDict = headersVal.toDictionary() {
                        for (key, val) in headersDict {
                            let keyStr = (key as? String) ?? "\(key)"
                            let valStr = (val as? String) ?? "\(val)"
                            request.setValue(valStr, forHTTPHeaderField: keyStr)
                        }
                    }
                }
                
                if let bodyVal = options.objectForKeyedSubscript("body"), !bodyVal.isUndefined, !bodyVal.isNull {
                    if bodyVal.isString {
                        request.httpBody = bodyVal.toString().data(using: .utf8)
                    } else if let bodyDict = bodyVal.toDictionary() as? [String: Any] {
                        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
                        if contentType.contains("application/json") {
                            request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict, options: [])
                        } else {
                            var components = URLComponents()
                            components.queryItems = bodyDict.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
                            request.httpBody = components.query?.data(using: .utf8)
                        }
                    }
                }
            }
            
            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var responseStatus = 500
            var finalResponseURL: URL?
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    responseStatus = httpResponse.statusCode
                    finalResponseURL = httpResponse.url
                }
                responseData = data
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 30.0) // Chờ tối đa 30s
            
            // 2. Đồng bộ ngược cookie nhận được vào Webview để dùng cho các phiên sau
            if let respURL = finalResponseURL ?? url {
                let semaphoreSyncBack = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    await NetworkManager.shared.syncCookiesToWebView(for: respURL)
                    semaphoreSyncBack.signal()
                }
                _ = semaphoreSyncBack.wait(timeout: .now() + 2.0)
            }
            
            let data = responseData ?? Data()
            let jsResponse = JS_Response(status: responseStatus, data: data, context: context)
            return JSValue(object: jsResponse, in: context)
        }
        context.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)
        
        // 5. Hàm String.format toàn cục
        let formatBlock: @convention(block) (String, JSValue) -> String = { formatStr, argVal in
            // Hỗ trợ thay thế %s hoặc {0}
            let argStr = argVal.toString() ?? ""
            var result = formatStr.replacingOccurrences(of: "%s", with: argStr)
            result = result.replacingOccurrences(of: "{0}", with: argStr)
            return result
        }
        
        let stringObj = JSValue(newObjectIn: context)
        stringObj?.setObject(formatBlock, forKeyedSubscript: "format" as NSString)
        context.setObject(stringObj, forKeyedSubscript: "String" as NSString)
        
        // 6. Hàm log, md5, base64 encode/decode toàn cục
        let logBlock: @convention(block) (JSValue) -> Void = { val in
            print("[Extension JS Log]: \(val.toString() ?? "nil")")
        }
        context.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        
        // 7. Mở rộng Array.prototype để tương thích với Jsoup Elements
        let arrayExtendScript = """
        Array.prototype.first = function() {
            return this.length > 0 ? this[0] : null;
        };
        Array.prototype.size = function() {
            return this.length;
        };
        Array.prototype.select = function(selector) {
            var results = [];
            for (var i = 0; i < this.length; i++) {
                var items = this[i].select(selector);
                results = results.concat(items);
            }
            return results;
        };
        Array.prototype.attr = function(name) {
            return this.length > 0 ? this[0].attr(name) : "";
        };
        Array.prototype.text = function() {
            var txts = [];
            for (var i = 0; i < this.length; i++) {
                txts.push(this[i].text());
            }
            return txts.join(" ").trim();
        };
        Array.prototype.html = function() {
            return this.length > 0 ? this[0].html() : "";
        };
        Array.prototype.outerHtml = function() {
            return this.length > 0 ? this[0].outerHtml() : "";
        };
        Array.prototype.remove = function() {
            for (var i = 0; i < this.length; i++) {
                this[i].remove();
            }
        };
        """
        _ = context.evaluateScript(arrayExtendScript)
    }
    
    /// Nạp cấu hình cô lập từ BookSource vào biến toàn cục của context
    private func setupConfig(context: JSContext, source: BookSource) {
        guard let configJsonStr = source.extensionConfig,
              let configData = configJsonStr.data(using: .utf8),
              let configDict = try? JSONSerialization.jsonObject(with: configData, options: []) as? [String: String] else {
            return
        }
        
        for (key, val) in configDict {
            context.setObject(val, forKeyedSubscript: key as NSString)
        }
    }
    
    /// Tự động nạp tệp src/config.js (nếu có)
    private func loadConfigFile(context: JSContext) {
        let extensionsDir = VBookExtensionManager.shared.extensionsDirectoryURL
        let configURL = extensionsDir.appendingPathComponent(extensionId).appendingPathComponent("src").appendingPathComponent("config.js")
        
        if let configContent = try? String(contentsOf: configURL, encoding: .utf8) {
            _ = context.evaluateScript(configContent)
        }
    }
    
    
    /// Đọc nội dung tệp script nghiệp vụ và gộp đệ quy toàn bộ các file được chỉ định qua load('...')
    private func getFullScriptContent(scriptName: String) -> String? {
        let extensionsDir = VBookExtensionManager.shared.extensionsDirectoryURL
        let fileURL = extensionsDir.appendingPathComponent(self.extensionId).appendingPathComponent("src").appendingPathComponent(scriptName)
        
        var content = ""
        if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            content = fileContent
        } else {
            let outerFileURL = extensionsDir.appendingPathComponent(self.extensionId).appendingPathComponent(scriptName)
            if let fileContent = try? String(contentsOf: outerFileURL, encoding: .utf8) {
                content = fileContent
            } else {
                return nil
            }
        }
        
        // Regex tìm lệnh load('filename') hoặc load("filename") có hỗ trợ khoảng trắng tùy ý
        let pattern = #"load\(\s*['"](.+?)['"]\s*\);?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        
        var resolvedContent = content
        let nsString = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // Duyệt ngược để không làm lệch index range khi thay thế chuỗi
        for match in matches.reversed() {
            let loadRange = match.range(at: 0)
            let fileRange = match.range(at: 1)
            let filename = nsString.substring(with: fileRange)
            
            if let loadedContent = getFullScriptContent(scriptName: filename) {
                resolvedContent = (resolvedContent as NSString).replacingCharacters(in: loadRange, with: loadedContent)
            } else {
                // Xóa lệnh load lỗi để tránh crash JS
                resolvedContent = (resolvedContent as NSString).replacingCharacters(in: loadRange, with: "")
            }
        }
        
        return resolvedContent
    }
    
    /// Thực thi một tệp script nghiệp vụ và gọi hàm entrypoint execute(...)
    public func executeScript(
        scriptName: String,
        source: BookSource,
        arguments: [Any] = []
    ) async throws -> JSValue {
        let context = JSContext()!
        
        // 1. Đăng ký các hàm và mở rộng toàn cục
        setupGlobals(context: context)
        
        // 2. Tiêm các cấu hình động của người dùng
        setupConfig(context: context, source: source)
        
        // 3. Chạy config.js để khởi tạo BASE_URL đúng cách
        loadConfigFile(context: context)
        
        // 4. Phân tích resolve và thực thi file script nghiệp vụ (gộp các file load để tránh lỗi scope let/const ES6)
        guard let scriptContent = getFullScriptContent(scriptName: scriptName) else {
            throw NSError(domain: "VBookExtensionEngine", code: 501, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy file script \(scriptName)"])
        }
        
        _ = context.evaluateScript(scriptContent)
        
        // 5. Gọi hàm execute(...) trong script
        guard let executeFunc = context.objectForKeyedSubscript("execute"), !executeFunc.isUndefined, !executeFunc.isNull else {
            throw NSError(domain: "VBookExtensionEngine", code: 502, userInfo: [NSLocalizedDescriptionKey: "Tệp script \(scriptName) không định nghĩa hàm execute()"])
        }
        
        let jsResult = executeFunc.call(withArguments: arguments)
        
        // 6. Xử lý lỗi trả về từ đối tượng Response.error
        if let resObj = jsResult, !resObj.isUndefined, !resObj.isNull {
            if let errorVal = resObj.objectForKeyedSubscript("error"), !errorVal.isUndefined, !errorVal.isNull {
                throw NSError(domain: "VBookExtensionEngine", code: 503, userInfo: [NSLocalizedDescriptionKey: errorVal.toString() ?? "Lỗi không xác định từ Extension"])
            }
        }
        
        return jsResult ?? JSValue(undefinedIn: context)
    }
}
