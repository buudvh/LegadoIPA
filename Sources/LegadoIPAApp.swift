import SwiftUI

@main
struct LegadoIPAApp: App {
    
    init() {
        // Tải trước từ điển Hán-Việt ngầm khi ứng dụng khởi chạy
        Task {
            _ = try? await TranslationLoader.shared.loadTranslationData()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
