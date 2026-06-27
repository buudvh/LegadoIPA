import Foundation
import WebKit

/// Trình quản lý mạng xử lý các kết nối URLSession, tự động đồng bộ hóa Cookie giữa URLSession và WKWebView
@MainActor
public final class NetworkManager: NSObject, @preconcurrency URLSessionDelegate, @preconcurrency URLSessionTaskDelegate {
    
    public static let shared = NetworkManager()
    
    private var session: URLSession!
    
    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        // Sử dụng lưu trữ cookie dùng chung hệ thống để đồng bộ dễ dàng hơn
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        
        // Đảm bảo tất cả delegate callbacks chạy trên luồng chính để tránh race condition trên Cookie Storage
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }
    
    /// Thực hiện gửi yêu cầu cào dữ liệu và trả về nội dung text (UTF-8 hoặc tương tự)
    public func request(_ analyzeUrl: AnalyzeUrl) async throws -> String {
        guard let request = analyzeUrl.getRequest() else {
            throw NSError(domain: "NetworkManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo URLRequest từ AnalyzeUrl"])
        }
        
        // Đảm bảo chạy đồng bộ trên MainActor
        await syncCookiesFromWebViewToStorage()
        
        let (data, response) = try await session.data(for: request)
        
        // Đồng bộ ngược cookie từ URL thực tế sau redirect (response.url) thay vì request.url gốc
        if let responseURL = response.url {
            await syncCookiesToWebView(for: responseURL)
        } else if let requestURL = request.url {
            await syncCookiesToWebView(for: requestURL)
        }
        
        // Xác định Encoding từ Response Header (hỗ trợ GBK, GB2312, Windows-1258...)
        var usedEncoding: String.Encoding = .utf8
        if let httpResponse = response as? HTTPURLResponse, let encodingName = httpResponse.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                usedEncoding = String.Encoding(rawValue: nsEncoding)
            }
        }
        
        // Giải mã nội dung bằng bảng mã đã xác định
        if let htmlStr = String(data: data, encoding: usedEncoding) {
            return htmlStr
        }
        
        // Fallback dự phòng sang UTF-8 hoặc ASCII
        if let htmlStr = String(data: data, encoding: .utf8) {
            return htmlStr
        } else if let asciiStr = String(data: data, encoding: .ascii) {
            return asciiStr
        }
        
        throw NSError(domain: "NetworkManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể decode dữ liệu phản hồi"])
    }
    
    // MARK: - Cookie Synchronization (Đồng bộ hóa Cookie)
    
    /// Đồng bộ toàn bộ cookie từ WKWebView sang URLSession Storage
    @MainActor
    public func syncCookiesFromWebViewToStorage() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let webCookies = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        
        for cookie in webCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
    
    /// Đồng bộ một cookie đơn lẻ vào WKWebView
    @MainActor
    public func syncCookieToWebView(_ cookie: HTTPCookie) async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }
    
    /// Đồng bộ toàn bộ cookie liên quan đến URL từ HTTPCookieStorage sang WKWebView tuần tự
    @MainActor
    public func syncCookiesToWebView(for url: URL) async {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        // Ghi tuần tự tránh overhead tạo TaskGroup không cần thiết trên MainActor
        for cookie in cookies {
            await syncCookieToWebView(cookie)
        }
    }
    
    // MARK: - URLSessionTaskDelegate HTTP Redirection Handling
    @MainActor
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Callback này hiện chạy an toàn trên MainThread nhờ delegateQueue: .main
        if let url = response.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:], for: url)
            
            Task {
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                    await self.syncCookieToWebView(cookie)
                }
                completionHandler(request)
            }
        } else {
            completionHandler(request)
        }
    }
}
