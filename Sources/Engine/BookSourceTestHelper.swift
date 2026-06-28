import Foundation

public final class BookSourceTestHelper {
    
    public static func runTest(completion: @escaping (String) -> Void) {
        Task {
            var log = ""
            let logBlock: (String) -> Void = { msg in
                print("[TestSource] \(msg)")
                log += msg + "\n"
            }
            
            logBlock("=== BẮT ĐẦU KIỂM THỬ NGUỒN SÁCH 69SHU ===")
            
            // 1. Khởi tạo đối tượng BookSource từ chuỗi JSON
            let jsonUrl = "https://www.yckceo.com/yuedu/shuyuan/json/id/7395.json"
            logBlock("Tải JSON nguồn sách từ: \(jsonUrl)...")
            
            guard let url = URL(string: jsonUrl),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let sources = try? JSONDecoder().decode([BookSource].self, from: data),
                  let source = sources.first else {
                logBlock("LỖI: Không thể tải hoặc parse JSON nguồn sách.")
                completion(log)
                return
            }
            logBlock("Nạp nguồn sách thành công: \(source.bookSourceName) [\(source.bookSourceUrl)]")
            
            // 2. Chạy thử Tìm kiếm (Search)
            let searchKey = "Thần Đạo"
            logBlock("Đang tìm kiếm thử từ khóa: \"\(searchKey)\"...")
            
            // Encode từ khóa (GBK cho nguồn Trung Quốc nếu cần)
            var query = ""
            if source.bookSourceUrl.contains("sudugu.org") || (source.bookSourceGroup ?? "").contains("Trung Quốc") {
                // Legado có hàm helper. Để đơn giản, ta fallback sang URL encode
                query = searchKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchKey
            } else {
                query = searchKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchKey
            }
            
            var searchUrlStr = source.searchUrl ?? ""
            searchUrlStr = searchUrlStr.replacingOccurrences(of: "{key}", with: query)
            
            let searchAnalyzeUrl = AnalyzeUrl(urlStr: searchUrlStr, source: source, key: searchKey)
            
            do {
                let html = try await NetworkManager.shared.request(searchAnalyzeUrl)
                logBlock("Đã nhận phản hồi HTML mạng (độ dài: \(html.count) ký tự).")
                
                let analyzer = AnalyzeRule(content: html, baseUrl: searchUrlStr, source: source)
                guard let ruleSearch = source.ruleSearch else {
                    logBlock("LỖI: Quy tắc tìm kiếm ruleSearch trống.")
                    completion(log)
                    return
                }
                
                let listRule = ruleSearch.bookList ?? ""
                let nameRule = ruleSearch.name ?? ""
                let authorRule = ruleSearch.author ?? ""
                let urlRule = ruleSearch.bookUrl ?? ""
                
                let bookNodes = analyzer.getStringList(listRule, isListRule: true)
                logBlock("Kết quả bóc tách danh sách: tìm thấy \(bookNodes.count) cuốn sách.")
                
                if bookNodes.isEmpty {
                    logBlock("Cảnh báo: Không trích xuất được cuốn sách nào.")
                } else {
                    for (idx, node) in bookNodes.prefix(3).enumerated() {
                        let name = analyzer.getString(nameRule, from: node)
                        let author = analyzer.getString(authorRule, from: node)
                        let relUrl = analyzer.getString(urlRule, from: node)
                        logBlock(" [\(idx+1)] Sách: \(name) - Tác giả: \(author) -> URL: \(relUrl)")
                    }
                }
                
                // 3. Chạy thử Khám phá (Explore)
                if let exploreUrl = source.exploreUrl, !exploreUrl.isEmpty {
                    logBlock("Đang kiểm tra khám phá danh mục...")
                    // exploreUrl trong 69shu chứa code JS phức tạp tự tạo json
                    let exploreRuleAnalyzer = AnalyzeRule(content: "", baseUrl: source.bookSourceUrl, source: source)
                    let exploreResult = exploreRuleAnalyzer.getString(exploreUrl)
                    logBlock("Mã JS exploreUrl thực thi thành công. Trả về: \(exploreResult.prefix(200))...")
                }
                
                // 4. Lấy chi tiết sách & TOC (chọn sách test tĩnh nếu danh sách trống)
                let testBookUrl = "https://www.69shuba.com/book/48365.htm" // Một URL sách tĩnh để test TOC
                logBlock("Kiểm tra bóc tách chi tiết sách và mục lục từ URL: \(testBookUrl)...")
                let detailAnalyzeUrl = AnalyzeUrl(urlStr: testBookUrl, source: source)
                let detailHtml = try await NetworkManager.shared.request(detailAnalyzeUrl)
                let detailAnalyzer = AnalyzeRule(content: detailHtml, baseUrl: testBookUrl, source: source)
                
                if let ruleBookInfo = source.ruleBookInfo {
                    let bookName = detailAnalyzer.getString(ruleBookInfo.name ?? "")
                    let bookAuthor = detailAnalyzer.getString(ruleBookInfo.author ?? "")
                    logBlock(" -> Tên sách trích xuất được: \(bookName) (Tác giả: \(bookAuthor))")
                    
                    var tocUrl = testBookUrl
                    if let tocRuleStr = ruleBookInfo.tocUrl, !tocRuleStr.isEmpty {
                        let relToc = detailAnalyzer.getString(tocRuleStr)
                        if !relToc.isEmpty, let base = URL(string: testBookUrl), let absToc = URL(string: relToc, relativeTo: base) {
                            tocUrl = absToc.absoluteString
                        }
                    }
                    logBlock(" -> URL mục lục trích xuất: \(tocUrl)")
                    
                    // 5. Tải mục lục
                    logBlock("Tải và bóc tách mục lục...")
                    let tocAnalyzeUrl = AnalyzeUrl(urlStr: tocUrl, source: source)
                    let tocHtml = try await NetworkManager.shared.request(tocAnalyzeUrl)
                    let tocAnalyzer = AnalyzeRule(content: tocHtml, baseUrl: tocUrl, source: source)
                    
                    if let ruleToc = source.ruleToc {
                        let chapterNodes = tocAnalyzer.getStringList(ruleToc.chapterList ?? "")
                        logBlock(" -> Tìm thấy \(chapterNodes.count) chương truyện.")
                        
                        if let firstNode = chapterNodes.first {
                            let chName = tocAnalyzer.getString(ruleToc.chapterName ?? "", from: firstNode)
                            let chUrl = tocAnalyzer.getString(ruleToc.chapterUrl ?? "", from: firstNode)
                            logBlock(" -> Chương đầu tiên: \"\(chName)\" -> Link: \(chUrl)")
                            
                            // 6. Tải nội dung chương đầu tiên
                            if !chUrl.isEmpty {
                                logBlock("Đang tải thử nội dung chương đầu...")
                                var absoluteChUrl = chUrl
                                if let base = URL(string: tocUrl), let absCh = URL(string: chUrl, relativeTo: base) {
                                    absoluteChUrl = absCh.absoluteString
                                }
                                
                                let chAnalyzeUrl = AnalyzeUrl(urlStr: absoluteChUrl, source: source)
                                // Gọi request có kèm webJs
                                let chHtml = try await NetworkManager.shared.request(chAnalyzeUrl, webJs: source.ruleContent?.webJs)
                                let chAnalyzer = AnalyzeRule(content: chHtml, baseUrl: absoluteChUrl, source: source)
                                
                                if let ruleContent = source.ruleContent {
                                    let contentText = chAnalyzer.getString(ruleContent.content ?? "")
                                    logBlock(" -> Trích xuất nội dung thành công (độ dài: \(contentText.count) ký tự).")
                                    logBlock(" -> Bản xem trước nội dung: \n\(contentText.prefix(200))...")
                                }
                            }
                        }
                    }
                }
                
                logBlock("=== KIỂM THỬ HOÀN TẤT THÀNH CÔNG ===")
            } catch {
                logBlock("LỖI trong quá trình kiểm thử: \(error.localizedDescription)")
            }
            
            completion(log)
        }
    }
}
