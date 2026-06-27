import SwiftUI
import JavaScriptCore

/// Màn hình Khám phá & Tìm kiếm truyện (ExploreView)
public struct ExploreView: View {
    
    @State private var searchQuery: String = ""
    @State private var sources: [BookSource] = []
    @State private var selectedSourceIndex = 0
    @State private var searchResults: [Book] = []
    @State private var isSearching = false
    
    // Quản lý xem chi tiết sách
    @State private var selectedBookDetails: Book? = nil
    @State private var showDetailSheet = false
    @State private var isBookAdded = false
    @State private var detailChaptersCount = 0
    
    // Quản lý Khám phá danh mục/thể loại
    @State private var exploreCategories: [(name: String, url: String)] = []
    @State private var selectedCategoryIndex: Int? = nil
    @State private var currentPage = 1
    @State private var isExploringMode = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack {
                // 1. Thanh chọn nguồn sách
                if !sources.isEmpty {
                    Picker("Nguồn sách", selection: $selectedSourceIndex) {
                        ForEach(0..<sources.count, id: \.self) { idx in
                            Text(sources[idx].bookSourceName).tag(idx)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)
                } else {
                    Text("Chưa có nguồn sách. Hãy thêm nguồn trước!")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
                
                // 1.5. Danh mục khám phá (Explore Categories)
                if !exploreCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(0..<exploreCategories.count, id: \.self) { idx in
                                Button(action: {
                                    selectedCategoryIndex = idx
                                    currentPage = 1
                                    isExploringMode = true
                                    searchQuery = "" // Xóa từ khóa tìm kiếm cũ
                                    Task {
                                        await performExplore(categoryUrl: exploreCategories[idx].url, page: 1)
                                    }
                                }) {
                                    Text(exploreCategories[idx].name)
                                        .font(.caption)
                                        .bold()
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(selectedCategoryIndex == idx ? Color.blue : Color.gray.opacity(0.15))
                                        .foregroundColor(selectedCategoryIndex == idx ? .white : .primary)
                                        .cornerRadius(15)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .frame(height: 40)
                }
                
                // 2. Thanh tìm kiếm (Search Bar)
                HStack {
                    TextField("Tìm kiếm tên truyện, tác giả...", text: $searchQuery, onCommit: {
                        Task { await performSearch() }
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        Task { await performSearch() }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                // 3. Kết quả tìm kiếm / Khám phá
                if isSearching {
                    Spacer()
                    ProgressView("Đang tải dữ liệu...")
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    Text(isExploringMode ? "Không tải được dữ liệu thể loại này." : "Nhập từ khóa và chọn nguồn sách để bắt đầu tìm kiếm.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        if isExploringMode {
                            HStack {
                                Button(action: {
                                    if currentPage > 1 {
                                        currentPage -= 1
                                        Task {
                                            if let idx = selectedCategoryIndex {
                                                await performExplore(categoryUrl: exploreCategories[idx].url, page: currentPage)
                                            }
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "chevron.left")
                                        Text("Trang trước")
                                    }
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(currentPage > 1 ? Color.blue : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .disabled(currentPage <= 1)
                                
                                Spacer()
                                
                                Text("Trang \(currentPage)")
                                    .font(.subheadline)
                                    .bold()
                                
                                Spacer()
                                
                                Button(action: {
                                    currentPage += 1
                                    Task {
                                        if let idx = selectedCategoryIndex {
                                            await performExplore(categoryUrl: exploreCategories[idx].url, page: currentPage)
                                        }
                                    }
                                }) {
                                    HStack {
                                        Text("Trang sau")
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.05))
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(searchResults) { book in
                                    HStack {
                                        if let cover = book.coverUrl, let url = URL(string: cover) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().aspectRatio(contentMode: .fit)
                                            } placeholder: {
                                                Color.gray
                                                    .frame(width: 50, height: 70)
                                            }
                                            .frame(width: 50, height: 70)
                                            .cornerRadius(4)
                                        } else {
                                            Color.gray.frame(width: 50, height: 70).cornerRadius(4)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(book.name).font(.headline)
                                            Text(book.author ?? "Không rõ tác giả").font(.subheadline).foregroundColor(.secondary)
                                            if let intro = book.intro {
                                                Text(intro).font(.caption).foregroundColor(.gray).lineLimit(2)
                                            }
                                        }
                                        
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundColor(.gray)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        openBookDetail(book)
                                    }
                                    
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.hideKeyboard()
                    }
            )
            .navigationTitle("Khám Phá Sách")
            .onAppear {
                Task {
                    await loadSources()
                }
            }
            .onChange(of: selectedSourceIndex) { newValue in
                Task {
                    if newValue < sources.count {
                        await parseExploreUrl(from: sources[newValue])
                    }
                }
            }
            // Sheet hiển thị chi tiết sách và mục lục để nhập vào tủ sách
            .sheet(isPresented: $showDetailSheet) {
                if let book = selectedBookDetails {
                    bookDetailSheet(book: book)
                }
            }
        }
    }
    
    // MARK: - Book Detail Sheet View
    
    private func bookDetailSheet(book: Book) -> some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 15) {
                            if let cover = book.coverUrl, let url = URL(string: cover) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 100, height: 140)
                                .cornerRadius(8)
                            } else {
                                Color.gray.frame(width: 100, height: 140).cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(book.name)
                                    .font(.title2)
                                    .bold()
                                Text("Tác giả: \(book.author ?? "Ẩn danh")")
                                    .foregroundColor(.secondary)
                                Text("Nguồn: \(book.originName)")
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        
                        Divider()
                        
                        Text("Giới thiệu truyện")
                            .font(.headline)
                        Text(book.intro ?? "Không có tóm tắt.")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        HStack {
                            Text("Số chương:")
                            Spacer()
                            Text("\(detailChaptersCount) chương")
                                .bold()
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Nút hành động
                Button(action: {
                    Task { await addSelectedBookToShelf() }
                }) {
                    Text(isBookAdded ? "Đã trong tủ sách" : "Nhập vào Tủ sách")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isBookAdded ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding()
                }
                .disabled(isBookAdded)
            }
            .navigationTitle("Thông Tin Truyện")
            .navigationBarItems(trailing: Button("Đóng") { showDetailSheet = false })
        }
    }
    
    // MARK: - Core Scraping Logic
    
    private func loadSources() async {
        let list = await DatabaseManager.shared.getAllBookSources()
        // Chỉ chọn nguồn sách đang kích hoạt
        self.sources = list.filter { $0.enabled }
        if !self.sources.isEmpty {
            await parseExploreUrl(from: self.sources[selectedSourceIndex])
        }
    }
    
    private func parseExploreUrl(from source: BookSource) async {
        self.exploreCategories = []
        self.selectedCategoryIndex = nil
        self.isExploringMode = false
        
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let engine = VBookExtensionEngine(extensionId: extId)
            do {
                var jsResult: JSValue? = nil
                do {
                    jsResult = try await engine.executeScript(scriptName: "home.js", source: source)
                } catch {
                    jsResult = try await engine.executeScript(scriptName: "genre.js", source: source)
                }
                
                if let jsResult = jsResult,
                   let dataVal = jsResult.objectForKeyedSubscript("data"),
                   dataVal.isArray {
                    
                    var categories: [(name: String, url: String)] = []
                    let array = dataVal.toArray() ?? []
                    for item in array {
                        if let dict = item as? [String: Any],
                           let title = dict["title"] as? String,
                           let input = dict["input"] as? String,
                           let script = dict["script"] as? String {
                            // Định tuyến động dạng "tên_script|tham_số_input"
                            categories.append((name: title, url: "\(script)|\(input)"))
                        }
                    }
                    DispatchQueue.main.async {
                        self.exploreCategories = categories
                    }
                    return
                }
            } catch {
                Logger.shared.log("Extension load explore categories error: \(error)")
            }
        }
        
        guard let exploreUrlStr = source.exploreUrl, !exploreUrlStr.isEmpty else { return }
        
        // Dịch exploreUrl sang tiếng Việt
        let translatedRaw = await TranslateUtils.translateSortExploreUrl(exploreUrlStr) ?? exploreUrlStr
        
        let lines = translatedRaw.components(separatedBy: .newlines)
        var categories: [(name: String, url: String)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.contains("::") {
                let parts = trimmed.components(separatedBy: "::")
                if parts.count >= 2 {
                    let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = parts[1...].joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                    categories.append((name: name, url: url))
                }
            }
        }
        self.exploreCategories = categories
    }
    
    private func performExplore(categoryUrl: String, page: Int) async {
        guard !sources.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let source = sources[selectedSourceIndex]
        
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let parts = categoryUrl.components(separatedBy: "|")
            guard parts.count >= 2 else {
                isSearching = false
                return
            }
            let scriptName = parts[0]
            let inputUrl = parts[1]
            
            let engine = VBookExtensionEngine(extensionId: extId)
            do {
                let jsResult = try await engine.executeScript(scriptName: scriptName, source: source, arguments: [inputUrl, String(page)])
                if let dataVal = jsResult.objectForKeyedSubscript("data"), dataVal.isArray {
                    var parsedBooks: [Book] = []
                    let array = dataVal.toArray() ?? []
                    
                    for item in array {
                        guard let dict = item as? [String: Any],
                              let name = dict["name"] as? String,
                              let link = dict["link"] as? String else {
                            continue
                        }
                        
                        let author = dict["author"] as? String ?? ""
                        let cover = dict["cover"] as? String ?? ""
                        let desc = dict["description"] as? String ?? ""
                        
                        let book = Book(
                            bookUrl: link,
                            name: name,
                            author: author.isEmpty ? nil : author,
                            coverUrl: cover.isEmpty ? nil : cover,
                            intro: desc.isEmpty ? nil : desc,
                            origin: source.bookSourceUrl,
                            originName: source.bookSourceName
                        )
                        parsedBooks.append(book)
                    }
                    
                    DispatchQueue.main.async {
                        self.searchResults = parsedBooks
                        self.isSearching = false
                    }
                    return
                }
            } catch {
                Logger.shared.log("Extension performExplore error: \(error)")
                DispatchQueue.main.async {
                    self.isSearching = false
                }
                return
            }
        }
        
        // Định dạng URL danh mục khám phá
        var finalUrlStr = categoryUrl
        if finalUrlStr.contains("{page}") {
            finalUrlStr = finalUrlStr.replacingOccurrences(of: "{page}", with: String(page))
        } else if finalUrlStr.contains("{{page}}") {
            finalUrlStr = finalUrlStr.replacingOccurrences(of: "{{page}}", with: String(page))
        }
        
        // Giải quyết URL tuyệt đối cho danh mục
        var absoluteUrlStr = finalUrlStr
        if !finalUrlStr.hasPrefix("http://") && !finalUrlStr.hasPrefix("https://") {
            let baseUrl = source.bookSourceUrl
            if baseUrl.hasSuffix("/") && finalUrlStr.hasPrefix("/") {
                absoluteUrlStr = baseUrl + String(finalUrlStr.dropFirst())
            } else if !baseUrl.hasSuffix("/") && !finalUrlStr.hasPrefix("/") {
                absoluteUrlStr = baseUrl + "/" + finalUrlStr
            } else {
                absoluteUrlStr = baseUrl + finalUrlStr
            }
        }
        
        let analyzeUrl = AnalyzeUrl(urlStr: absoluteUrlStr, source: source)
        
        do {
            let html = try await NetworkManager.shared.request(analyzeUrl)
            let analyzer = AnalyzeRule(content: html, baseUrl: absoluteUrlStr, source: source)
            
            // Lấy quy tắc Explore (hoặc fallback Search)
            var listRule = ""
            var nameRule = ""
            var authorRule = ""
            var coverRule = ""
            var introRule = ""
            var urlRule = ""
            
            if let ruleExplore = source.ruleExplore {
                listRule = ruleExplore.bookList ?? ""
                nameRule = ruleExplore.name ?? ""
                authorRule = ruleExplore.author ?? ""
                coverRule = ruleExplore.coverUrl ?? ""
                introRule = ruleExplore.intro ?? ""
                urlRule = ruleExplore.bookUrl ?? ""
            } else if let ruleSearch = source.ruleSearch {
                listRule = ruleSearch.bookList ?? ""
                nameRule = ruleSearch.name ?? ""
                authorRule = ruleSearch.author ?? ""
                coverRule = ruleSearch.coverUrl ?? ""
                introRule = ruleSearch.intro ?? ""
                urlRule = ruleSearch.bookUrl ?? ""
            } else {
                isSearching = false
                return
            }
            
            let bookNodes = analyzer.getStringList(listRule, isListRule: true)
            Logger.shared.log("[performExplore] URL: \(absoluteUrlStr), HTML length: \(html.count), listRule: \(listRule), nodes count: \(bookNodes.count)")
            var parsedBooks: [Book] = []
            
            for node in bookNodes {
                let name = analyzer.getString(nameRule, from: node)
                let author = analyzer.getString(authorRule, from: node)
                let cover = analyzer.getString(coverRule, from: node)
                let intro = analyzer.getString(introRule, from: node)
                let relativeUrl = analyzer.getString(urlRule, from: node)
                
                // Giải quyết URL tuyệt đối cho từng cuốn sách
                var absoluteUrl = relativeUrl
                if let base = URL(string: absoluteUrlStr), let absURL = URL(string: relativeUrl, relativeTo: base) {
                    absoluteUrl = absURL.absoluteString
                }
                
                let book = Book(
                    bookUrl: absoluteUrl,
                    name: name,
                    author: author,
                    coverUrl: cover,
                    intro: intro,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                )
                Logger.shared.log("[performExplore] Parsed book -> Name: \(name), Author: \(author), Cover: \(cover), URL: \(absoluteUrl)")
                parsedBooks.append(book)
            }
            
            self.searchResults = parsedBooks
            isSearching = false
        } catch {
            Logger.shared.log("Explore Error: \(error)")
            isSearching = false
        }
    }
    
    private func performSearch() async {
        guard !searchQuery.isEmpty, !sources.isEmpty else { return }
        
        // Reset trạng thái khám phá thể loại khi tìm kiếm thủ công
        selectedCategoryIndex = nil
        isExploringMode = false
        
        isSearching = true
        searchResults = []
        
        let source = sources[selectedSourceIndex]
        
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let engine = VBookExtensionEngine(extensionId: extId)
            do {
                let jsResult = try await engine.executeScript(scriptName: "search.js", source: source, arguments: [searchQuery, "1"])
                if let dataVal = jsResult.objectForKeyedSubscript("data"), dataVal.isArray {
                    var parsedBooks: [Book] = []
                    let array = dataVal.toArray() ?? []
                    
                    for item in array {
                        guard let dict = item as? [String: Any],
                              let name = dict["name"] as? String,
                              let link = dict["link"] as? String else {
                            continue
                        }
                        
                        let author = dict["author"] as? String ?? ""
                        let cover = dict["cover"] as? String ?? ""
                        let desc = dict["description"] as? String ?? ""
                        
                        let book = Book(
                            bookUrl: link,
                            name: name,
                            author: author.isEmpty ? nil : author,
                            coverUrl: cover.isEmpty ? nil : cover,
                            intro: desc.isEmpty ? nil : desc,
                            origin: source.bookSourceUrl,
                            originName: source.bookSourceName
                        )
                        parsedBooks.append(book)
                    }
                    
                    DispatchQueue.main.async {
                        self.searchResults = parsedBooks
                        self.isSearching = false
                    }
                    return
                }
            } catch {
                Logger.shared.log("Extension performSearch error: \(error)")
                DispatchQueue.main.async {
                    self.isSearching = false
                }
                return
            }
        }
        
        var query = searchQuery
        if source.bookSourceUrl.contains("sudugu.org") || (source.bookSourceGroup ?? "").contains("Trung Quốc") {
            query = searchQuery.addingPercentEncodingForGBK()
        } else {
            query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        }
        
        // Cấu hình URL tìm kiếm
        // Android dùng: searchUrl: "https://example.com/search?key={key}"
        var searchUrlStr = source.searchUrl ?? ""
        searchUrlStr = searchUrlStr.replacingOccurrences(of: "{key}", with: query)
        
        let analyzeUrl = AnalyzeUrl(urlStr: searchUrlStr, source: source)
        
        do {
            let html = try await NetworkManager.shared.request(analyzeUrl)
            let analyzer = AnalyzeRule(content: html, baseUrl: searchUrlStr, source: source)
            
            guard let ruleSearch = source.ruleSearch else {
                isSearching = false
                return
            }
            
            let listRule = ruleSearch.bookList ?? ""
            let nameRule = ruleSearch.name ?? ""
            let authorRule = ruleSearch.author ?? ""
            let coverRule = ruleSearch.coverUrl ?? ""
            let introRule = ruleSearch.intro ?? ""
            let urlRule = ruleSearch.bookUrl ?? ""
            
            let bookNodes = analyzer.getStringList(listRule, isListRule: true)
            Logger.shared.log("[performSearch] URL: \(searchUrlStr), HTML length: \(html.count), listRule: \(listRule), nodes count: \(bookNodes.count)")
            var parsedBooks: [Book] = []
            
            for node in bookNodes {
                let name = analyzer.getString(nameRule, from: node)
                let author = analyzer.getString(authorRule, from: node)
                let cover = analyzer.getString(coverRule, from: node)
                let intro = analyzer.getString(introRule, from: node)
                let relativeUrl = analyzer.getString(urlRule, from: node)
                
                // Giải quyết URL tuyệt đối
                var absoluteUrl = relativeUrl
                if let base = URL(string: searchUrlStr), let absURL = URL(string: relativeUrl, relativeTo: base) {
                    absoluteUrl = absURL.absoluteString
                }
                
                let book = Book(
                    bookUrl: absoluteUrl,
                    name: name,
                    author: author,
                    coverUrl: cover,
                    intro: intro,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                )
                Logger.shared.log("[performSearch] Parsed book -> Name: \(name), Author: \(author), Cover: \(cover), URL: \(absoluteUrl)")
                parsedBooks.append(book)
            }
            
            self.searchResults = parsedBooks
            isSearching = false
        } catch {
            Logger.shared.log("Search Error: \(error)")
            isSearching = false
        }
    }
    
    private func openBookDetail(_ book: Book) {
        selectedBookDetails = book
        isBookAdded = false
        detailChaptersCount = 0
        showDetailSheet = true
        
        Task {
            // Tải chi tiết và đếm chương trước
            await fetchBookDetails(book)
        }
    }
    
    private func fetchBookDetails(_ book: Book) async {
        guard let source = await DatabaseManager.shared.getBookSource(url: book.origin) else { return }
        
        // 1. Kiểm tra xem sách đã tồn tại trong DB chưa
        if await DatabaseManager.shared.getBook(url: book.bookUrl) != nil {
            isBookAdded = true
        }
        
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let engine = VBookExtensionEngine(extensionId: extId)
            do {
                let jsResult = try await engine.executeScript(scriptName: "detail.js", source: source, arguments: [book.bookUrl])
                if let dataVal = jsResult.objectForKeyedSubscript("data"), !dataVal.isUndefined && !dataVal.isNull {
                    let dict = dataVal.toDictionary() as? [String: Any] ?? [:]
                    
                    var updatedBook = book
                    if let name = dict["name"] as? String, !name.isEmpty { updatedBook.name = name }
                    if let author = dict["author"] as? String, !author.isEmpty { updatedBook.author = author }
                    if let cover = dict["cover"] as? String, !cover.isEmpty { updatedBook.coverUrl = cover }
                    if let desc = dict["description"] as? String, !desc.isEmpty { updatedBook.intro = desc }
                    
                    // Lấy số chương bằng cách gọi toc.js để đếm
                    let tocResult = try await engine.executeScript(scriptName: "toc.js", source: source, arguments: [book.bookUrl])
                    if let tocData = tocResult.objectForKeyedSubscript("data"), tocData.isArray {
                        let chaptersArray = tocData.toArray() ?? []
                        DispatchQueue.main.async {
                            self.detailChaptersCount = chaptersArray.count
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.selectedBookDetails = updatedBook
                    }
                    return
                }
            } catch {
                Logger.shared.log("Extension fetchBookDetails error: \(error)")
                return
            }
        }
        
        // 2. Tải trang chi tiết sách
        let requestUrl = book.bookUrl
        let analyzeUrl = AnalyzeUrl(urlStr: requestUrl, source: source)
        
        guard let html = try? await NetworkManager.shared.request(analyzeUrl) else {
            Logger.shared.log("Failed to fetch book detail page for \(book.name)")
            return
        }
        
        let analyzer = AnalyzeRule(content: html, baseUrl: requestUrl, source: source)
        
        // Cập nhật các thông tin chi tiết từ ruleBookInfo
        var updatedBook = book
        Logger.shared.log("[fetchBookDetails] Detail HTML length: \(html.count), updatedBook.name: \(updatedBook.name), author: \(updatedBook.author ?? "")")
        if let ruleBookInfo = source.ruleBookInfo {
            if let nameRule = ruleBookInfo.name, !nameRule.isEmpty {
                let name = analyzer.getString(nameRule)
                if !name.isEmpty { updatedBook.name = name }
            }
            if let authorRule = ruleBookInfo.author, !authorRule.isEmpty {
                let author = analyzer.getString(authorRule)
                if !author.isEmpty { updatedBook.author = author }
            }
            if let coverRule = ruleBookInfo.coverUrl, !coverRule.isEmpty {
                let cover = analyzer.getString(coverRule)
                if !cover.isEmpty { updatedBook.coverUrl = cover }
            }
            if let introRule = ruleBookInfo.intro, !introRule.isEmpty {
                let intro = analyzer.getString(introRule)
                if !intro.isEmpty { updatedBook.intro = intro }
            }
            if let wordCountRule = ruleBookInfo.wordCount, !wordCountRule.isEmpty {
                let wordCount = analyzer.getString(wordCountRule)
                if !wordCount.isEmpty { updatedBook.wordCount = wordCount }
            }
        }
        
        // Lấy TOC url từ chi tiết sách (nếu có rule)
        var tocUrl = book.bookUrl
        if let tocRuleStr = source.ruleBookInfo?.tocUrl, !tocRuleStr.isEmpty {
            let relTocUrl = analyzer.getString(tocRuleStr)
            if !relTocUrl.isEmpty, let base = URL(string: requestUrl), let absToc = URL(string: relTocUrl, relativeTo: base) {
                tocUrl = absToc.absoluteString
            }
        }
        updatedBook.tocUrl = tocUrl
        
        // Cập nhật ngay thông tin sách lên giao diện
        self.selectedBookDetails = updatedBook
        
        // 3. Tải danh sách chương (TOC) độc lập để đếm số chương
        let tocAnalyzeUrl = AnalyzeUrl(urlStr: tocUrl, source: source)
        if let tocHtml = try? await NetworkManager.shared.request(tocAnalyzeUrl) {
            let tocAnalyzer = AnalyzeRule(content: tocHtml, baseUrl: tocUrl, source: source)
            let chapterListRule = source.ruleToc?.chapterList ?? ""
            let chapterNodes = tocAnalyzer.getStringList(chapterListRule, isListRule: true)
            Logger.shared.log("[fetchBookDetails] TOC HTML length: \(tocHtml.count), chapterListRule: \(chapterListRule), chapters count: \(chapterNodes.count)")
            
            // Lưu lại số lượng chương hiển thị trên UI
            self.detailChaptersCount = chapterNodes.count
        }
    }
    
    private func addSelectedBookToShelf() async {
        guard let book = selectedBookDetails,
              let source = await DatabaseManager.shared.getBookSource(url: book.origin) else { return }
        
        // Phân nhánh chạy Extension VBook
        if source.isExtension == true, let extId = source.extensionId {
            let engine = VBookExtensionEngine(extensionId: extId)
            do {
                let jsResult = try await engine.executeScript(scriptName: "toc.js", source: source, arguments: [book.bookUrl])
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
                    
                    await DatabaseManager.shared.saveBook(book)
                    await DatabaseManager.shared.saveChapters(parsedChapters, forBookUrl: book.bookUrl)
                    
                    DispatchQueue.main.async {
                        self.isBookAdded = true
                        self.showDetailSheet = false
                    }
                    return
                }
            } catch {
                Logger.shared.log("Extension addSelectedBookToShelf error: \(error)")
                return
            }
        }
        
        // Tải toàn bộ chương và lưu vào DB
        let tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        let tocAnalyzeUrl = AnalyzeUrl(urlStr: tocUrl, source: source)
        
        if let tocHtml = try? await NetworkManager.shared.request(tocAnalyzeUrl) {
            let tocAnalyzer = AnalyzeRule(content: tocHtml, baseUrl: tocUrl, source: source)
            
            let chapterListRule = source.ruleToc?.chapterList ?? ""
            let chapterNameRule = source.ruleToc?.chapterName ?? ""
            let chapterUrlRule = source.ruleToc?.chapterUrl ?? ""
            
            let chapterNodes = tocAnalyzer.getStringList(chapterListRule, isListRule: true)
            Logger.shared.log("[addSelectedBookToShelf] TOC HTML length: \(tocHtml.count), chapterListRule: \(chapterListRule), chapters count: \(chapterNodes.count)")
            var parsedChapters: [BookChapter] = []
            
            for (i, node) in chapterNodes.enumerated() {
                let name = tocAnalyzer.getString(chapterNameRule, from: node)
                let relativeUrl = tocAnalyzer.getString(chapterUrlRule, from: node)
                
                var absoluteUrl = relativeUrl
                if let base = URL(string: tocUrl), let absURL = URL(string: relativeUrl, relativeTo: base) {
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
            
            // Lưu sách và danh sách chương vào DB
            await DatabaseManager.shared.saveBook(book)
            await DatabaseManager.shared.saveChapters(parsedChapters, forBookUrl: book.bookUrl)
            
            isBookAdded = true
            showDetailSheet = false
        }
    }
}

#if canImport(UIKit)
extension View {
    public func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

extension String {
    fileprivate func addingPercentEncodingForGBK() -> String {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding("gbk" as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            if let data = self.data(using: String.Encoding(rawValue: nsEncoding)) {
                return data.map { String(format: "%%%02X", $0) }.joined()
            }
        }
        return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
