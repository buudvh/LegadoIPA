import Foundation
import WebKit

/// Trình quản lý mạng xử lý các kết nối URLSession, tự động đồng bộ hóa Cookie giữa URLSession và WKWebView
public final class NetworkManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    
    public static let shared = NetworkManager()
    
    private var session: URLSession!
    
    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        // Sử dụng lưu trữ cookie dùng chung hệ thống để đồng bộ dễ dàng hơn
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    /// Thực hiện gửi yêu cầu cào dữ liệu và trả về nội dung text (UTF-8 hoặc tương tự)
    public func request(_ analyzeUrl: AnalyzeUrl) async throws -> String {
        guard let request = analyzeUrl.getRequest() else {
            throw NSError(domain: "NetworkManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo URLRequest từ AnalyzeUrl"])
        }
        
        // Đảm bảo chạy đồng bộ trên MainActor
        await MainActor.run {
            await syncCookiesFromWebViewToStorage()
        }
        
        let (data, response) = try await session.data(for: request)
        
        // Đồng bộ ngược toàn bộ cookie (kể cả cookie từ redirect tự động) vào WKWebView
        if let url = request.url {
            await MainActor.run {
                await syncCookiesToWebView(for: url)
            }
        }
        
        // Giải mã nội dung
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
    
    /// Đồng bộ toàn bộ cookie liên quan đến URL từ HTTPCookieStorage sang WKWebView song song
    @MainActor
    public func syncCookiesToWebView(for url: URL) async {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return }
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        
        await withTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        cookieStore.setCookie(cookie) {
                            continuation.resume()
                        }
                    }
                }
            }
            await group.waitForAll()
        }
    }
    
    // MARK: - URLSessionTaskDelegate HTTP Redirection Handling
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = response.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:], for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
                Task { @MainActor in
                    await self.syncCookieToWebView(cookie)
                }
            }
        }
        completionHandler(request)
    }
}
