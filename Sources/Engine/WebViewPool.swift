import Foundation
import WebKit

/// Trình chạy WebView chạy ngầm xử lý việc nạp trang web và thực thi mã JavaScript (Bypass Cloudflare, AJAX ngầm)
@MainActor
public final class PooledWebView: NSObject, WKNavigationDelegate {
    
    public let webView: WKWebView
    private var completion: ((Result<String, Error>) -> Void)?
    private var jsToEvaluate: String?
    private var isPageLoaded = false
    private var timeoutTask: Task<Void, Never>?
    
    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        // Cấu hình vô hiệu hóa media autoplay để tiết kiệm data
        config.mediaTypesRequiringUserActionForPlayback = .all
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        
        // Tiêm User-Agent tương thích di động phổ biến
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
    }
    
    /// Nạp URL và thực thi mã JS sau khi tải xong trang
    public func loadAndEvaluate(urlStr: String, jsCode: String, timeout: TimeInterval = 15.0) async throws -> String {
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "PooledWebView", code: 401, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        
        cancelTimeoutTask()
        
        self.jsToEvaluate = jsCode
        self.isPageLoaded = false
        
        return try await withCheckedThrowingContinuation { continuation in
            self.completion = { [weak self] result in
                self?.cleanUpAndFinish(with: result)
                continuation.resume(with: result)
            }
            
            // Bắt đầu tải trang
            self.webView.load(URLRequest(url: url))
            
            // Xử lý timeout an toàn trên @MainActor để tránh Data Race
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self = self else { return }
                if Task.isCancelled { return }
                
                if !self.isPageLoaded && self.completion != nil {
                    self.webView.stopLoading()
                    let err = NSError(domain: "PooledWebView", code: 408, userInfo: [NSLocalizedDescriptionKey: "WebView nạp trang quá thời gian chờ (Timeout)"])
                    let comp = self.completion
                    self.completion = nil
                    self.cleanUpAndFinish(with: .failure(err))
                    comp?(.failure(err))
                }
            }
        }
    }
    
    private func cancelTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
    
    private func cleanUpAndFinish(with result: Result<String, Error>) {
        cancelTimeoutTask()
        jsToEvaluate = nil
    }
    
    /// Chuẩn bị tái sử dụng: Reset trạng thái và tải trang trống an toàn
    public func prepareForReuse() {
        cancelTimeoutTask()
        self.completion = nil
        self.jsToEvaluate = nil
        self.isPageLoaded = false
        
        // Hủy delegate tạm thời khi tải trang blank để tránh kích hoạt didFinish ngoài ý muốn
        self.webView.navigationDelegate = nil
        self.webView.stopLoading()
        self.webView.load(URLRequest(url: URL(string: "about:blank")!))
        self.webView.navigationDelegate = self
    }
    
    /// Hủy hoàn toàn các kết nối và dừng tải
    public func destroy() {
        cancelTimeoutTask()
        self.completion = nil
        self.jsToEvaluate = nil
        self.webView.navigationDelegate = nil
        self.webView.stopLoading()
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Bỏ qua sự kiện tải trang blank dọn dẹp
        if webView.url?.absoluteString == "about:blank" { return }
        
        self.isPageLoaded = true
        cancelTimeoutTask()
        
        guard let js = jsToEvaluate, let comp = completion else { return }
        self.jsToEvaluate = nil
        self.completion = nil
        
        webView.evaluateJavaScript(js) { val, err in
            if let err = err {
                comp(.failure(err))
            } else {
                comp(.success(String(describing: val ?? "")))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView.url?.absoluteString == "about:blank" { return }
        if let comp = completion {
            self.completion = nil
            cleanUpAndFinish(with: .failure(error))
            comp(.failure(error))
        }
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView.url?.absoluteString == "about:blank" { return }
        if let comp = completion {
            self.completion = nil
            cleanUpAndFinish(with: .failure(error))
            comp(.failure(error))
        }
    }
}

/// Bể chứa (Pool) các đối tượng PooledWebView để tái sử dụng
@MainActor
public final class WebViewPool {
    
    public static let shared = WebViewPool()
    
    private var idlePool: [PooledWebView] = []
    private let maxPoolSize = 3 // Giới hạn kích thước pool để tránh phình bộ nhớ
    private var memoryWarningObserver: NSObjectProtocol?
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { @MainActor [weak self] _ in
            guard let self = self else { return }
            
            // Hủy triệt để các WebView rảnh rỗi
            for webView in self.idlePool {
                webView.destroy()
            }
            self.idlePool.removeAll()
            
            // Dọn dẹp cache WebKit trên disk và memory để giải phóng RAM tối đa
            WKWebsiteDataStore.default().removeData(
                ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
                modifiedSince: Date.distantPast
            ) {}
        }
    }
    
    /// Lấy một WebView rảnh rỗi hoặc khởi tạo mới
    public func acquire() -> PooledWebView {
        if !idlePool.isEmpty {
            return idlePool.removeLast()
        }
        return PooledWebView()
    }
    
    /// Trả lại WebView về bể chứa sau khi sử dụng
    public func release(_ pooledWebView: PooledWebView) {
        pooledWebView.prepareForReuse()
        
        // Chỉ lưu giữ lại WebView trong pool nếu chưa vượt quá số lượng tối đa
        if idlePool.count < maxPoolSize {
            idlePool.append(pooledWebView)
        } else {
            // Giải phóng triệt để nếu pool đã đầy
            pooledWebView.destroy()
        }
    }
    
    /// Thực thi tác vụ chạy ngầm của WebView
    public func execute(urlStr: String, jsCode: String, timeout: TimeInterval = 15.0) async throws -> String {
        let webView = acquire()
        defer {
            release(webView)
        }
        return try await webView.loadAndEvaluate(urlStr: urlStr, jsCode: jsCode, timeout: timeout)
    }
}
