import Foundation

/// Lớp xuất truyện thành file Markdown (.md) dựa trên cấu hình quy tắc JSON
public final class MarkdownExporter {
    
    public static let shared = MarkdownExporter()
    
    private init() {}
    
    /// Delegate nhận thông tin tiến độ crawl truyện
    public typealias ProgressHandler = (Double, String) -> Void
    
    /// Bắt đầu cào toàn bộ truyện và xuất ra file .md
    public func exportBook(
        _ book: Book,
        source: BookSource,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        // Lấy cấu hình export (nếu nguồn sách không có sẵn, dùng cấu hình mặc định)
        let exportRule = source.markdownExportRule ?? MarkdownExportRule()
        let settings = exportRule.crawlerSettings
        let template = exportRule.outputTemplate
        
        progress(0.01, "Đang tải danh sách chương truyện...")
        
        // 1. Tải danh sách chương truyện
        let chapters = try await fetchChapterList(book: book, source: source)
        guard !chapters.isEmpty else {
            throw NSError(domain: "MarkdownExporter", code: 601, userInfo: [NSLocalizedDescriptionKey: "Không lấy được danh sách chương từ nguồn"])
        }
        
        progress(0.05, "Đã tải xong \(chapters.count) chương. Bắt đầu tải nội dung chương...")
        
        // 2. Tải nội dung từng chương song song (giới hạn số luồng concurrentRequests)
        var chapterContents = [Int: String]()
        let totalChapters = chapters.count
        
        // Chia nhóm để tải song song hạn chế số luồng tránh bị block IP
        let batchSize = settings.concurrentRequests
        var index = 0
        
        while index < totalChapters {
            let endIndex = min(index + batchSize, totalChapters)
            let batch = Array(chapters[index..<endIndex])
            
            // Chạy batch tải song song
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (offset, chapter) in batch.enumerated() {
                    group.addTask {
                        // Trễ so le (Staggered delay) trước khi gửi request trong cùng lô để chống ban IP
                        let staggerDelay = UInt64(offset) * UInt64(settings.delayBetweenRequestsMs) * 1_000_000
                        try? await Task.sleep(nanoseconds: staggerDelay)
                        
                        do {
                            let content = try await self.fetchChapterContentWithRetry(
                                chapter: chapter,
                                source: source,
                                useTranslation: template.useVietPhrase,
                                retryCount: settings.retryCount
                            )
                            return (chapter.index, content)
                        } catch {
                            // Bắt lỗi cục bộ để tránh làm sập tiến trình xuất toàn bộ các chương khác
                            print("[MarkdownExporter Error] Lỗi tải chương \(chapter.title): \(error.localizedDescription)")
                            return (chapter.index, "\n\n[Lỗi: Không thể tải nội dung chương này từ nguồn truyện]\n\n")
                        }
                    }
                }
                
                for try await (chapIndex, text) in group {
                    chapterContents[chapIndex] = text
                    
                    let loadedCount = chapterContents.count
                    let percent = 0.05 + 0.90 * (Double(loadedCount) / Double(totalChapters))
                    let msg = "Đã tải: \(loadedCount)/\(totalChapters) chương..."
                    progress(percent, msg)
                }
            }
            
            index += batchSize
        }
        
        progress(0.96, "Đang ghép nối và định dạng tệp tin Markdown...")
        
        // 3. Ghép nối và định dạng Markdown theo Template
        var mdString = ""
        
        // 3.1 Ghi YAML Frontmatter
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        var frontmatter = template.frontmatter ?? ""
        
        var translatedBookName = book.name
        var translatedBookAuthor = book.author ?? "Unknown"
        var translatedBookIntro = book.intro ?? ""
        
        if template.useVietPhrase {
            translatedBookName = await TranslateUtils.translateMeta(book.name)
            translatedBookAuthor = await TranslateUtils.translateMeta(book.author ?? "")
            translatedBookIntro = await TranslateUtils.translateMeta(book.intro ?? "")
        }
        
        frontmatter = frontmatter.replacingOccurrences(of: "{title}", with: translatedBookName)
                                 .replacingOccurrences(of: "{author}", with: translatedBookAuthor)
                                 .replacingOccurrences(of: "{sourceUrl}", with: book.bookUrl)
                                 .replacingOccurrences(of: "{intro}", with: translatedBookIntro)
                                 .replacingOccurrences(of: "{currentDate}", with: dateStr)
        mdString += frontmatter
        
        // 3.2 Ghi nội dung từng chương
        for i in 0..<totalChapters {
            guard let rawContent = chapterContents[i] else { continue }
            let chapter = chapters[i]
            
            var chapterTitle = chapter.title
            if template.useVietPhrase {
                chapterTitle = await TranslateUtils.translateChapterTitle(chapter.title)
            }
            
            // Tiêu đề chương
            var header = template.chapterHeader ?? "\n\n# {chapterTitle}\n\n"
            header = header.replacingOccurrences(of: "{chapterTitle}", with: chapterTitle)
            mdString += header
            
            // Nội dung chương (Đoạn văn cách nhau bởi dấu xuống dòng chuẩn)
            let paragraphs = rawContent.components(separatedBy: .newlines)
            let paragraphTemplate = template.chapterContentFormat ?? "{paragraph}\n"
            
            for p in paragraphs {
                let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let pText = paragraphTemplate.replacingOccurrences(of: "{paragraph}", with: trimmed)
                mdString += pText
            }
        }
        
        progress(0.99, "Ghi tệp tin vào bộ nhớ thiết bị...")
        
        // 4. Lưu tệp Markdown vào thư mục Documents của ứng dụng
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportDir = documentDirectory.appendingPathComponent("ExportedBooks", isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        let safeName = book.name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        let fileURL = exportDir.appendingPathComponent("\(safeName).md")
        
        try mdString.write(to: fileURL, atomically: true, encoding: .utf8)
        
        progress(1.0, "Xuất file Markdown thành công!")
        return fileURL
    }
    
    // MARK: - Crawler Engine Helpers
    
    /// Cào danh sách chương truyện
    private func fetchChapterList(book: Book, source: BookSource) async throws -> [BookChapter] {
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let requestUrlStr = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
            let engine = VBookExtensionEngine(extensionId: extId)
            let jsResult = try await engine.executeScript(scriptName: "toc.js", source: source, arguments: [requestUrlStr])
            
            if let dataVal = jsResult.objectForKeyedSubscript("data"), dataVal.isArray {
                var parsedChapters: [BookChapter] = []
                let array = dataVal.toArray() ?? []
                
                for (i, item) in array.enumerated() {
                    guard let dict = item as? [String: Any],
                          let name = dict["name"] as? String,
                          let chapUrl = dict["url"] as? String else {
                        continue
                    }
                    
                    let chapter = BookChapter(
                        bookUrl: book.bookUrl,
                        index: i,
                        title: name,
                        url: chapUrl
                    )
                    parsedChapters.append(chapter)
                }
                return parsedChapters
            }
            throw NSError(domain: "MarkdownExporter", code: 611, userInfo: [NSLocalizedDescriptionKey: "Extension không trả về danh sách chương hợp lệ"])
        }
        
        guard let tocRule = source.ruleToc else {
            throw NSError(domain: "MarkdownExporter", code: 602, userInfo: [NSLocalizedDescriptionKey: "Quy tắc danh sách chương (ruleToc) trống"])
        }
        
        let requestUrlStr = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        let analyzeUrl = AnalyzeUrl(urlStr: requestUrlStr, source: source)
        
        let htmlResponse = try await NetworkManager.shared.request(analyzeUrl)
        
        let analyzer = AnalyzeRule(content: htmlResponse, baseUrl: requestUrlStr, source: source)
        
        let chapterListRule = tocRule.chapterList ?? ""
        let chapterNameRule = tocRule.chapterName ?? ""
        let chapterUrlRule = tocRule.chapterUrl ?? ""
        
        let chapterNodes = analyzer.getStringList(chapterListRule)
        var parsedChapters: [BookChapter] = []
        
        for (i, node) in chapterNodes.enumerated() {
            let name = analyzer.getString(chapterNameRule, from: node)
            let relativeUrl = analyzer.getString(chapterUrlRule, from: node)
            
            // Tạo URL tuyệt đối
            var absoluteUrl = relativeUrl
            if let base = URL(string: requestUrlStr), let absURL = URL(string: relativeUrl, relativeTo: base) {
                absoluteUrl = absURL.absoluteString
            }
            
            let chapter = BookChapter(
                bookUrl: book.bookUrl,
                index: i,
                title: name,
                url: absoluteUrl
            )
            parsedChapters.append(chapter)
        }
        
        return parsedChapters
    }
    
    /// Tải nội dung chương sách có hỗ trợ thử lại (Retry)
    private func fetchChapterContentWithRetry(
        chapter: BookChapter,
        source: BookSource,
        useTranslation: Bool,
        retryCount: Int
    ) async throws -> String {
        var attempts = 0
        while attempts <= retryCount {
            do {
                return try await fetchChapterContent(chapter: chapter, source: source, useTranslation: useTranslation)
            } catch {
                attempts += 1
                if attempts > retryCount {
                    throw error
                }
                // Chờ tăng dần trước khi thử lại
                try? await Task.sleep(nanoseconds: UInt64(attempts * 1_000_000_000))
            }
        }
        throw NSError(domain: "MarkdownExporter", code: 603, userInfo: [NSLocalizedDescriptionKey: "Không thể tải nội dung chương sau \(retryCount) lần thử lại"])
    }
    
    /// Tải nội dung một chương cụ thể
    private func fetchChapterContent(chapter: BookChapter, source: BookSource, useTranslation: Bool) async throws -> String {
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let engine = VBookExtensionEngine(extensionId: extId)
            let jsResult = try await engine.executeScript(scriptName: "chap.js", source: source, arguments: [chapter.url])
            guard let dataVal = jsResult.objectForKeyedSubscript("data"), dataVal.isString else {
                throw NSError(domain: "MarkdownExporter", code: 612, userInfo: [NSLocalizedDescriptionKey: "Extension không trả về nội dung chương dạng String"])
            }
            
            var processedText = dataVal.toString() ?? ""
            if useTranslation {
                processedText = await TranslateUtils.translateContent(processedText)
            }
            return processedText
        }
        
        guard let contentRule = source.ruleContent else {
            throw NSError(domain: "MarkdownExporter", code: 604, userInfo: [NSLocalizedDescriptionKey: "Quy tắc nội dung chương (ruleContent) trống"])
        }
        
        let analyzeUrl = AnalyzeUrl(urlStr: chapter.url, source: source)
        let htmlResponse = try await NetworkManager.shared.request(analyzeUrl)
        
        let analyzer = AnalyzeRule(content: htmlResponse, baseUrl: chapter.url, source: source)
        let rawContent = analyzer.getString(contentRule.content ?? "")
        
        // Áp dụng bộ lọc Regex/Lọc thay thế thô
        var processedText = rawContent
        
        // Nếu bật dịch tự động sang Việt ngữ (Hán-Việt)
        if useTranslation {
            processedText = await TranslateUtils.translateContent(processedText)
        }
        
        return processedText
    }
}
