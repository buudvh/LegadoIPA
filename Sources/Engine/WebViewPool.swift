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
        
        timeoutTask?.cancel()
        timeoutTask = nil
        
        self.jsToEvaluate = jsCode
        self.isPageLoaded = false
        
        return try await withCheckedThrowingContinuation { continuation in
            self.completion = { [weak self] result in
                self?.cleanUpAndFinish(with: result)
                continuation.resume(with: result)
            }
            
            // Bắt đầu tải trang
            self.webView.load(URLRequest(url: url))
            
            // Xử lý timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self = self else { return }
                if Task.isCancelled { return }
                
                if !self.isPageLoaded && self.completion != nil {
                    self.webView.stopLoading()
                    let err = NSError(domain: "PooledWebView", code: 408, userInfo: [NSLocalizedDescriptionKey: "WebView nạp trang quá thời gian chờ (Timeout)"])
                    self.completion?(.failure(err))
                    self.completion = nil
                }
            }
        }
    }
    
    private func cleanUpAndFinish(with result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        jsToEvaluate = nil
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isPageLoaded = true
        timeoutTask?.cancel()
        timeoutTask = nil
        
        guard let js = jsToEvaluate, let comp = completion else { return }
        self.jsToEvaluate = nil
        self.completion = nil
        
        // Thực thi mã JS sau khi nạp trang hoàn tất
        webView.evaluateJavaScript(js) { val, err in
            if let err = err {
                comp(.failure(err))
            } else {
                comp(.success(String(describing: val ?? "")))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let comp = completion {
            cleanUpAndFinish(with: .failure(error))
            self.completion = nil
            comp(.failure(error))
        }
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let comp = completion {
            cleanUpAndFinish(with: .failure(error))
            self.completion = nil
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
        ) { [weak self] _ in
            guard let self = self else { return }
            // Xóa sạch pool khi nhận cảnh báo bộ nhớ để giải phóng tiến trình WebKit con
            self.idlePool.removeAll()
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
        // Clear trạng thái bằng cách load trang trống
        pooledWebView.webView.load(URLRequest(url: URL(string: "about:blank")!))
        
        // Chỉ lưu giữ lại WebView trong pool nếu chưa vượt quá số lượng tối đa
        if idlePool.count < maxPoolSize {
            idlePool.append(pooledWebView)
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
