import Foundation
import JavaScriptCore
import CryptoKit

/// Cầu nối tiêm các đối tượng và phương thức hữu ích từ Swift vào môi trường JavaScriptCore
public final class JSBridge {
    
    /// Đăng ký các hàm mở rộng vào JSContext
    public static func setupContext(_ context: JSContext, withBaseUrl baseUrl: String?, source: BookSource?) {
        let bridge = JSBridge()
        
        // Tiêm đối tượng "java" vào context để tương thích các nguồn sách cũ của Android
        let javaObject = JSValue(newObjectIn: context)
        context?.setObject(javaObject, forKeyedSubscript: "java" as NSString)
        
        // Đăng ký các phương thức của Bridge lên đối tượng "java" và phạm vi toàn cục (global)
        
        // 1. AJAX request (Đồng bộ qua Semaphore)
        let ajaxBlock: @convention(block) (String) -> String? = { urlStr in
            return bridge.syncAjax(url: urlStr, baseUrl: baseUrl, source: source)
        }
        javaObject?.setObject(ajaxBlock, forKeyedSubscript: "ajax" as NSString)
        context?.setObject(ajaxBlock, forKeyedSubscript: "ajax" as NSString)
        
        // 2. MD5 Encode
        let md5Block: @convention(block) (String) -> String = { str in
            return bridge.md5Encode(str)
        }
        javaObject?.setObject(md5Block, forKeyedSubscript: "md5Encode" as NSString)
        javaObject?.setObject(md5Block, forKeyedSubscript: "md5Encode16" as NSString) // Fallback
        context?.setObject(md5Block, forKeyedSubscript: "md5Encode" as NSString)
        
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
        context?.setObject(base64EncodeBlock, forKeyedSubscript: "base64Encode" as NSString)
        context?.setObject(base64DecodeBlock, forKeyedSubscript: "base64Decode" as NSString)
        
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
        context?.setObject(urlEncodeBlock, forKeyedSubscript: "utf8Encode" as NSString)
        context?.setObject(urlDecodeBlock, forKeyedSubscript: "utf8Decode" as NSString)
        
        // 5. Console Log
        let logBlock: @convention(block) (String) -> Void = { msg in
            print("[JS Logger] \(msg)")
        }
        javaObject?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        context?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        
        // Tiêm các biến môi trường
        if let baseUrl = baseUrl {
            context?.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
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
                // Tự động nhận diện encoding và chuyển về UTF-8
                result = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10.0) // Chờ tối đa 10 giây
        
        return result
    }
    
    private func md5Encode(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
