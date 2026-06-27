---
name: Multi-Agent Logic Verifier
description: Kích hoạt hệ thống nhiều sub-agent song song để kiểm tra từng mô-đun logic nhỏ trong dự án iOS LegadoIPA, sau đó tổng hợp qua một agent điều phối chung.
---

# Quy trình Xác minh Đa Agent (Multi-Agent Logic Verifier)

Quy trình này hướng dẫn tác nhân AI (Agent) tự động phân rã tác vụ kiểm tra chất lượng code thành các cuộc hội thoại con (sub-agents) chuyên biệt, chạy song song để tối ưu hóa context window và độ sâu phân tích, trước khi tổng hợp kết quả qua một điều phối viên trung tâm.

---

## Bước 1: Khai báo các Sub-Agent Chuyên biệt

Sử dụng công cụ `define_subagent` để định nghĩa 4 tác nhân chuyên trách cho 4 phân vùng logic lõi của LegadoIPA:

1. **TrieVerifier (Kiểm tra Bộ dịch VietPhrase)**:
   - **Mục tiêu**: Đánh giá tính chính xác của thuật toán phân tách từ trong [TranslateUtils.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Translation/TranslateUtils.swift), thuật toán mảng đôi trong [DoubleArrayTrie.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Translation/DoubleArrayTrie.swift), và việc nạp nhị phân Big Endian trong [TranslationLoader.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Translation/TranslationLoader.swift).
   - **Tập trung**: Tránh tràn bộ nhớ (memory leaks), kiểm tra lỗi ranh giới (off-by-one) khi duyệt chuỗi Unicode, hiệu năng tra cứu.

2. **SelectorVerifier (Kiểm tra Bộ phân tích Rule)**:
   - **Mục tiêu**: Đánh giá tính chính xác của bộ trích xuất dữ liệu trong [AnalyzeRule.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/AnalyzeRule.swift), [RuleAnalyzer.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/RuleAnalyzer.swift), và [AnalyzeUrl.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/AnalyzeUrl.swift).
   - **Tập trung**: Phân tích cú pháp ngoặc cân bằng, escape ký tự đặc biệt, an toàn luồng khi gọi JavaScriptCore và cách tiêm các hàm native JS trong [JSBridge.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/JSBridge.swift).

3. **NetworkVerifier (Kiểm tra Kết nối & WebView)**:
   - **Mục tiêu**: Đánh giá luồng truyền tải dữ liệu trong [NetworkManager.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/NetworkManager.swift) và [WebViewPool.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Engine/WebViewPool.swift).
   - **Tập trung**: Rò rỉ cookie, đồng bộ hóa cookie bất đồng bộ giữa URLSession và WKWebView, việc giữ và giải phóng webview chạy ngầm trên luồng chính (`@MainActor`).

4. **ExporterVerifier (Kiểm tra Đọc ghi & Exporter)**:
   - **Mục tiêu**: Đánh giá logic cào truyện song song và lưu trữ dữ liệu trong [MarkdownExporter.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Exporter/MarkdownExporter.swift) và [DatabaseManager.swift](file:///D:/1.SOURCE_CODE/LegadoIPA/Sources/Database/DatabaseManager.swift).
   - **Tập trung**: Tránh block IP khi gửi request song song quá nhanh, xử lý lỗi mạng từng chương (retry/backoff), cấu trúc định dạng file Markdown xuất ra, tính toàn vẹn của tệp JSON DB.

---

## Bước 2: Kích hoạt chạy song song (Parallel Invocation)

Sử dụng công cụ `invoke_subagent` để kích hoạt đồng thời 4 sub-agents đã khai báo ở trên.

### Cú pháp mẫu gọi song song:
```json
{
  "Subagents": [
    {
      "TypeName": "TrieVerifier",
      "Role": "Trie & Translation Reviewer",
      "Prompt": "Hãy đọc và đánh giá logic các tệp DoubleArrayTrie.swift, TranslationLoader.swift, TranslateUtils.swift. Chỉ ra các lỗi bảo mật tiềm ẩn, rò rỉ bộ nhớ, hoặc sai lệch thuật toán phân tách từ Hán-Việt."
    },
    {
      "TypeName": "SelectorVerifier",
      "Role": "Rule Scraping Parser Reviewer",
      "Prompt": "Hãy đọc và đánh giá logic các tệp RuleAnalyzer.swift, AnalyzeRule.swift, JSBridge.swift, AnalyzeUrl.swift. Tập trung vào tính chính xác của thuật toán cắt chuỗi cân bằng, an toàn luồng khi chạy JSContext và việc tiêm hàm native."
    },
    {
      "TypeName": "NetworkVerifier",
      "Role": "Network & WKWebView Manager Reviewer",
      "Prompt": "Hãy đọc và đánh giá logic các tệp NetworkManager.swift, WebViewPool.swift. Đánh giá tính an toàn luồng, rò rỉ cookie, và cơ chế giải phóng bộ nhớ của WKWebView Pool chạy nền."
    },
    {
      "TypeName": "ExporterVerifier",
      "Role": "Exporter & Database Manager Reviewer",
      "Prompt": "Hãy đọc và đánh giá logic các tệp MarkdownExporter.swift, DatabaseManager.swift. Kiểm tra thuật toán cào song song TaskGroup, cơ chế giãn cách delay request, và tính toàn vẹn khi ghi tệp tin JSON DB."
    }
  ]
}
```

---

## Bước 3: Điều phối và Tổng hợp (Coordinator Agent)

Khi toàn bộ các sub-agent báo cáo kết quả hoàn tất về inbox của bạn, hãy khai báo và gọi một Agent điều phối tổng thể (`IntegrationCoordinator`):

### Định nghĩa Coordinator Agent:
- **Tên**: `IntegrationCoordinator`
- **Vai trò**: Trưởng nhóm Kiến trúc iOS (iOS Lead Architect Coordinator)
- **Nhiệm vụ**: Đọc toàn bộ báo cáo từ 4 sub-agent trước đó, đối chiếu tính liên kết và giao diện tương tác giữa các thành phần (giao tiếp giữa Exporter và Database, giao tiếp giữa AnalyzeRule và JSBridge, v.v.). Tìm kiếm các lỗi xung đột kiểu dữ liệu, các cảnh báo biên dịch Xcode và đưa ra kết luận đánh giá tổng thể.

### Đầu ra mong đợi:
Sinh ra một báo cáo phân tích tổng hợp dưới dạng tệp tin Markdown Artifact đặt tên là `verification_report.md` tại thư mục lưu trữ Artifact của hội thoại hiện tại.
