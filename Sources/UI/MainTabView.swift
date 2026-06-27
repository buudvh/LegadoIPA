import SwiftUI

/// Container chính (MainTabView) kết hợp 4 Tab chức năng của LegadoIPA
public struct MainTabView: View {
    @State private var selectedTab = 0
    
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
    }
}
