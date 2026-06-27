import Foundation

/// Trình quản lý ghi log hoạt động cào dữ liệu ra tệp tin app_crawl.log trong thư mục Documents
public final class Logger {
    public static let shared = Logger()
    
    private let logFileURL: URL
    
    private init() {
        let fileManager = FileManager.default
        let documentDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.logFileURL = documentDir.appendingPathComponent("app_crawl.log")
        
        // Khởi tạo file log trống nếu chưa tồn tại
        if !fileManager.fileExists(atPath: logFileURL.path) {
            try? "=== BẮT ĐẦU LOG HOẠT ĐỘNG CÀO SÁCH ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// Ghi log kèm theo nhãn thời gian thực ra cả console và tệp tin app_crawl.log
    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        // In ra console mặc định
        print(message)
        
        // Ghi nối tiếp (Append) vào tệp tin trên đĩa
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                // Nếu fileHandle lỗi, thử ghi đè
                try? logLine.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    /// Xóa sạch dữ liệu log cũ
    public func clearLog() {
        try? "=== LOG ĐÃ ĐƯỢC LÀM SẠCH ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
