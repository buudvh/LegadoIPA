import SwiftUI

/// Container chính (MainTabView) kết hợp 4 Tab chức năng của LegadoIPA
public struct MainTabView: View {
    @State private var selectedTab = 0
    
    // Trạng thái cho WebView xác minh Cloudflare toàn cục
    @State private var showVerificationSheet = false
    @State private var verificationUrl = ""
    @State private var verificationTitle = ""
    @State private var verificationCompletion: ((String?) -> Void)? = nil
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            
            // Tab 1: Bookshelf
            BookshelfView()
                .tabItem {
                    Label("Tủ sách", systemImage: "books.vertical.fill")
                }
                .tag(0)
            
            // Tab 2: Explore
            ExploreView()
                .tabItem {
                    Label("Khám phá", systemImage: "safari.fill")
                }
                .tag(1)
            
            // Tab 3: BookSource Manager
            SourceManagerView()
                .tabItem {
                    Label("Nguồn sách", systemImage: "square.stack.3d.up.fill")
                }
                .tag(2)
            
            // Tab 4: Settings
            SettingsView()
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .accentColor(.blue) // Màu sắc hiển thị icon tab đang active
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWebViewVerificationNotification"))) { notification in
            if let userInfo = notification.userInfo,
               let url = userInfo["url"] as? String,
               let title = userInfo["title"] as? String,
               let completion = userInfo["completion"] as? (String?) -> Void {
                self.verificationUrl = url
                self.verificationTitle = title
                self.verificationCompletion = completion
                self.showVerificationSheet = true
            }
        }
        .sheet(isPresented: $showVerificationSheet) {
            VerificationWebView(url: verificationUrl, title: verificationTitle) { html in
                self.showVerificationSheet = false
                // Trả kết quả HTML về cho luồng JS đang block
                self.verificationCompletion?(html)
            }
        }
    }
}
