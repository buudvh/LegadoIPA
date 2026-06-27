import SwiftUI

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
                
                // 3. Kết quả tìm kiếm
                if isSearching {
                    Spacer()
                    ProgressView("Đang tìm kiếm...")
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    Text("Nhập từ khóa và chọn nguồn sách để bắt đầu tìm kiếm.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    List(searchResults) { book in
                        HStack {
                            if let cover = book.coverUrl, let url = URL(string: cover) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openBookDetail(book)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Khám Phá Sách")
            .onAppear {
                Task {
                    await loadSources()
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
    }
    
    private func performSearch() async {
        guard !searchQuery.isEmpty, !sources.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let source = sources[selectedSourceIndex]
        let query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        
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
            
            let bookNodes = analyzer.getStringList(listRule)
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
                parsedBooks.append(book)
            }
            
            self.searchResults = parsedBooks
            isSearching = false
        } catch {
            print("Search Error: \(error)")
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
        
        // 2. Phân tích TOC (Đếm số chương)
        let requestUrl = book.bookUrl
        let analyzeUrl = AnalyzeUrl(urlStr: requestUrl, source: source)
        
        if let html = try? await NetworkManager.shared.request(analyzeUrl) {
            let analyzer = AnalyzeRule(content: html, baseUrl: requestUrl, source: source)
            
            // Lấy TOC url từ chi tiết sách (nếu có rule)
            var tocUrl = book.bookUrl
            if let tocRuleStr = source.ruleBookInfo?.tocUrl, !tocRuleStr.isEmpty {
                let relTocUrl = analyzer.getString(tocRuleStr)
                if !relTocUrl.isEmpty, let base = URL(string: requestUrl), let absToc = URL(string: relTocUrl, relativeTo: base) {
                    tocUrl = absToc.absoluteString
                }
            }
            
            // Tải danh sách chương
            let tocAnalyzeUrl = AnalyzeUrl(urlStr: tocUrl, source: source)
            if let tocHtml = try? await NetworkManager.shared.request(tocAnalyzeUrl) {
                let tocAnalyzer = AnalyzeRule(content: tocHtml, baseUrl: tocUrl, source: source)
                let chapterListRule = source.ruleToc?.chapterList ?? ""
                let chapterNodes = tocAnalyzer.getStringList(chapterListRule)
                
                // Lưu lại số lượng chương hiển thị trên UI
                self.detailChaptersCount = chapterNodes.count
                
                // Cập nhật thông tin chi tiết (tóm tắt đầy đủ)
                var updatedBook = book
                updatedBook.tocUrl = tocUrl
                if let introRuleStr = source.ruleBookInfo?.intro, !introRuleStr.isEmpty {
                    let fullIntro = analyzer.getString(introRuleStr)
                    if !fullIntro.isEmpty {
                        updatedBook.intro = fullIntro
                    }
                }
                
                self.selectedBookDetails = updatedBook
            }
        }
    }
    
    private func addSelectedBookToShelf() async {
        guard let book = selectedBookDetails,
              let source = await DatabaseManager.shared.getBookSource(url: book.origin) else { return }
        
        // Tải toàn bộ chương và lưu vào DB
        let tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        let tocAnalyzeUrl = AnalyzeUrl(urlStr: tocUrl, source: source)
        
        if let tocHtml = try? await NetworkManager.shared.request(tocAnalyzeUrl) {
            let tocAnalyzer = AnalyzeRule(content: tocHtml, baseUrl: tocUrl, source: source)
            
            let chapterListRule = source.ruleToc?.chapterList ?? ""
            let chapterNameRule = source.ruleToc?.chapterName ?? ""
            let chapterUrlRule = source.ruleToc?.chapterUrl ?? ""
            
            let chapterNodes = tocAnalyzer.getStringList(chapterListRule)
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
