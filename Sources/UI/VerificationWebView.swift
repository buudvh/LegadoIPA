import SwiftUI
import WebKit

/// SwiftUI View hiển thị WKWebView để người dùng giải khiên Cloudflare/Turnstile thủ công
public struct VerificationWebView: View {
    let url: String
    let title: String
    let completion: (String?) -> Void
    
    @State private var isLoading = true
    @State private var webViewRef: WKWebView? = nil
    
    public init(url: String, title: String, completion: @escaping (String?) -> Void) {
        self.url = url
        self.title = title
        self.completion = completion
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                VerificationWebViewRepresentable(urlStr: url, webViewRef: $webViewRef, isLoading: $isLoading)
                    .edgesIgnoringSafeArea(.bottom)
                
                if isLoading {
                    ProgressView("Đang tải trang xác minh...")
                        .padding()
                        .background(Color(.systemBackground).opacity(0.8))
                        .cornerRadius(12)
                }
            }
            .navigationTitle(title.isEmpty ? "Xác minh bảo mật" : title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Hủy") {
                    completion(nil)
                },
                trailing: Button("Hoàn tất") {
                    // Lấy nội dung HTML hiện tại khi người dùng bấm hoàn tất
                    if let webView = webViewRef {
                        webView.evaluateJavaScript("document.documentElement.outerHTML") { val, err in
                            let html = val as? String
                            completion(html)
                        }
                    } else {
                        completion(nil)
                    }
                }
            )
        }
    }
}

struct VerificationWebViewRepresentable: UIViewRepresentable {
    let urlStr: String
    @Binding var webViewRef: WKWebView?
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Sử dụng chung Cookie Storage
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
        
        webViewRef = webView
        
        if let url = URL(string: urlStr) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: VerificationWebViewRepresentable
        
        init(_ parent: VerificationWebViewRepresentable) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            
            // Tự động kiểm tra nếu trang web đã vượt khiên thành công (không còn Cloudflare Challenge)
            webView.evaluateJavaScript("document.body.innerText") { val, _ in
                if let text = val as? String {
                    let isBlocked = text.contains("Just a moment") || text.contains("Checking your browser") || text.contains("Turnstile")
                    if !isBlocked && !text.isEmpty {
                        // Tự động đồng bộ cookie vào Cookie Storage của app
                        Task { @MainActor in
                            await NetworkManager.shared.syncCookiesFromWebViewToStorage()
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
