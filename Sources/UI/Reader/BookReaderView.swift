import SwiftUI
import UIKit

/// Màn hình Đọc truyện chính (BookReaderView) trong SwiftUI
/// Sử dụng UIPageViewController ngầm để lật trang mượt mà (Curl / Slide) và CoreText để render văn bản
public struct BookReaderView: View {
    
    @State private var book: Book
    @State private var chapters: [BookChapter] = []
    
    @State private var currentChapterIndex: Int
    @State private var currentPageIndex: Int = 0
    
    // Nội dung chương đang tải
    @State private var chapterText: String = ""
    @State private var pages: [NSRange] = []
    @State private var isLoading = false
    @State private var showMenu = false
    
    // Config đọc truyện
    @State private var readerConfig = ReaderConfig()
    @State private var isTranslateEnabled = TranslateUtils.isTranslateEnabled
    
    // Theme màu nền đọc truyện
    @State private var themeIndex = 0
    private let themes: [(bg: Color, uiBg: UIColor, text: UIColor)] = [
        (Color(red: 0.96, green: 0.95, blue: 0.90), UIColor(red: 0.96, green: 0.95, blue: 0.90, alpha: 1.0), .black), // Giấy cổ điển
        (.white, .white, .black), // Sáng
        (Color(red: 0.90, green: 0.94, blue: 0.90), UIColor(red: 0.90, green: 0.94, blue: 0.90, alpha: 1.0), UIColor(red: 0.1, green: 0.3, blue: 0.1, alpha: 1.0)), // Xanh bảo vệ mắt
        (Color(red: 0.12, green: 0.12, blue: 0.14), UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0), .lightGray) // Tối (Night Mode)
    ]
    
    public init(book: Book) {
        _book = State(initialValue: book)
        _currentChapterIndex = State(initialValue: book.durChapterIndex)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Màu nền của Reader
                themes[themeIndex].bg.ignoresSafeArea()
                
                // 2. Nội dung hiển thị
                if isLoading {
                    ProgressView("Đang tải chương...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if pages.isEmpty {
                    VStack {
                        Text("Không có nội dung")
                        Button("Tải lại") {
                            Task { await loadChapterContent() }
                        }
                        .padding()
                    }
                } else {
                    // Trình lật trang UIPageViewController ngầm
                    PageViewControllerRepresentable(
                        text: chapterText,
                        pages: pages,
                        currentPageIndex: $currentPageIndex,
                        config: readerConfig,
                        onPageChanged: { newPageIdx in
                            // Lưu tiến độ đọc sách khi chuyển trang
                            saveReadingProgress()
                        },
                        onSwipePastEnd: {
                            Task { await navigateToNextChapter() }
                        },
                        onSwipePastStart: {
                            Task { await navigateToPrevChapter() }
                        }
                    )
                    .id("\(currentChapterIndex)_\(chapterText.count)") // Force redraw khi đổi chương
                }
                
                // 3. Vùng nhận diện Tap ở giữa để mở Menu điều khiển
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.5)
                    .onTapGesture {
                        withAnimation { showMenu.toggle() }
                    }
                
                // 4. Menu Overlay Điều khiển
                if showMenu {
                    readerMenuOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await loadChaptersAndProgress()
            }
        }
    }
    
    // MARK: - Subviews (Reader Menu Overlay)
    
    private var readerMenuOverlay: some View {
        VStack {
            // Thanh điều khiển trên cùng (Top Bar)
            HStack {
                Button(action: {
                    // Back và lưu tiến độ
                    saveReadingProgress()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .padding()
                }
                
                Spacer()
                
                if !chapters.isEmpty && currentChapterIndex < chapters.count {
                    Text(chapters[currentChapterIndex].title)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: 200)
                }
                
                Spacer()
                
                // Nút Dịch Nhanh Quick Translate (QT)
                Button(action: {
                    isTranslateEnabled.toggle()
                    TranslateUtils.isTranslateEnabled = isTranslateEnabled
                    // Reload lại chương hiện tại để áp dụng dịch
                    Task { await loadChapterContent() }
                }) {
                    Text(isTranslateEnabled ? "Dịch: Bật" : "Dịch: Tắt")
                        .font(.subheadline)
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isTranslateEnabled ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.top, 40)
            .background(Color(.systemBackground).opacity(0.95))
            .foregroundColor(.primary)
            
            Spacer()
            
            // Thanh cấu hình dưới cùng (Bottom Settings Panel)
            VStack(spacing: 20) {
                // Điều chỉnh kích thước chữ (Font size)
                HStack {
                    Text("Cỡ chữ")
                    Spacer()
                    HStack(spacing: 20) {
                        Button(action: { changeFontSize(delta: -1.0) }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        Text("\(Int(readerConfig.fontSize))")
                            .font(.headline)
                        Button(action: { changeFontSize(delta: 1.0) }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                    }
                    .font(.title3)
                }
                
                // Chọn Theme màu nền
                HStack {
                    Text("Màu nền")
                    Spacer()
                    HStack(spacing: 15) {
                        ForEach(0..<themes.count, id: \.self) { index in
                            Circle()
                                .fill(themes[index].bg)
                                .frame(width: 35, height: 35)
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue, lineWidth: themeIndex == index ? 3 : 0)
                                )
                                .onTapGesture {
                                    themeIndex = index
                                    readerConfig.textColor = themes[index].text
                                    // Báo vẽ lại
                                    updateConfig()
                                }
                        }
                    }
                }
                
                // Thanh trượt chương (Chapter Slider)
                if !chapters.isEmpty {
                    HStack {
                        Button(action: { Task { await navigateToPrevChapter() } }) {
                            Text("Chương trước")
                        }
                        .disabled(currentChapterIndex == 0)
                        
                        Slider(value: Binding(
                            get: { Double(currentChapterIndex) },
                            set: { val in
                                currentChapterIndex = Int(val)
                                Task { await loadChapterContent() }
                            }
                        ), in: 0...Double(chapters.count - 1), step: 1.0)
                        
                        Button(action: { Task { await navigateToNextChapter() } }) {
                            Text("Chương sau")
                        }
                        .disabled(currentChapterIndex >= chapters.count - 1)
                    }
                    .font(.footnote)
                }
            }
            .padding()
            .background(Color(.systemBackground).opacity(0.95))
            .foregroundColor(.primary)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Logic Operations
    
    private func loadChaptersAndProgress() async {
        // Tải danh sách chương từ DB
        let dbChapters = await DatabaseManager.shared.getChapters(forBookUrl: book.bookUrl)
        self.chapters = dbChapters
        
        // Khởi động config đọc truyện
        readerConfig.textColor = themes[themeIndex].text
        
        await loadChapterContent()
    }
    
    private func loadChapterContent() async {
        guard !chapters.isEmpty, currentChapterIndex < chapters.count else { return }
        isLoading = true
        
        let chapter = chapters[currentChapterIndex]
        
        // Trích xuất BookSource tương ứng
        guard let source = await DatabaseManager.shared.getBookSource(url: book.origin) else {
            isLoading = false
            return
        }
        
        do {
            let requestUrl = chapter.url
            let analyzeUrl = AnalyzeUrl(urlStr: requestUrl, source: source)
            let htmlResponse = try await NetworkManager.shared.request(analyzeUrl)
            
            let analyzer = AnalyzeRule(content: htmlResponse, baseUrl: requestUrl, source: source)
            var rawText = analyzer.getString(source.ruleContent?.content ?? "")
            
            if isTranslateEnabled {
                rawText = await TranslateUtils.translateContent(rawText)
            }
            
            self.chapterText = rawText
            
            // Tính toán phân trang
            // Sử dụng kích thước ước lượng màn hình (ví dụ 390x844 của iPhone 14)
            let screenSize = UIScreen.main.bounds.size
            self.pages = CoreTextPager.shared.paginate(text: rawText, config: readerConfig, boundsSize: screenSize)
            self.currentPageIndex = min(book.durChapterIndex == currentChapterIndex ? book.durChapterPos : 0, max(0, pages.count - 1))
            
            isLoading = false
        } catch {
            print("Reader Error: \(error)")
            self.chapterText = "Lỗi khi tải nội dung chương: \(error.localizedDescription)"
            self.pages = []
            isLoading = false
        }
    }
    
    private func changeFontSize(delta: CGFloat) {
        readerConfig.fontSize += delta
        updateConfig()
    }
    
    private func updateConfig() {
        let screenSize = UIScreen.main.bounds.size
        self.pages = CoreTextPager.shared.paginate(text: chapterText, config: readerConfig, boundsSize: screenSize)
        self.currentPageIndex = min(currentPageIndex, max(0, pages.count - 1))
    }
    
    private func saveReadingProgress() {
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterPos = currentPageIndex
        updatedBook.durChapterTime = Int64(Date().timeIntervalSince1970)
        
        self.book = updatedBook
        Task {
            await DatabaseManager.shared.saveBook(updatedBook)
        }
    }
    
    private func navigateToNextChapter() async {
        if currentChapterIndex < chapters.count - 1 {
            currentChapterIndex += 1
            await loadChapterContent()
            currentPageIndex = 0
            saveReadingProgress()
        }
    }
    
    private func navigateToPrevChapter() async {
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            await loadChapterContent()
            currentPageIndex = max(0, pages.count - 1)
            saveReadingProgress()
        }
    }
}

// MARK: - UIPageViewController Wrapper (UIViewControllerRepresentable)
struct PageViewControllerRepresentable: UIViewControllerRepresentable {
    
    let text: String
    let pages: [NSRange]
    @Binding var currentPageIndex: Int
    let config: ReaderConfig
    
    var onPageChanged: (Int) -> Void
    var onSwipePastEnd: () -> Void
    var onSwipePastStart: () -> Void
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(navigationOrientation: .horizontal, transitionStyle: .pageCurl, options: nil)
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        
        let initialVC = context.coordinator.viewControllerAtIndex(currentPageIndex)
        pageVC.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        
        return pageVC
    }
    
    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.text = text
        context.coordinator.pages = pages
        context.coordinator.config = config
        
        // Cập nhật trang hiện tại nếu có sự thay đổi ngoài luồng swipe (ví dụ do đổi chương)
        if let currentVC = uiViewController.viewControllers?.first as? PageContentViewController,
           currentVC.index != currentPageIndex {
            let direction: UIPageViewController.NavigationDirection = currentPageIndex > currentVC.index ? .forward : .reverse
            let targetVC = context.coordinator.viewControllerAtIndex(currentPageIndex)
            uiViewController.setViewControllers([targetVC], direction: direction, animated: true, completion: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageViewControllerRepresentable
        
        var text: String
        var pages: [NSRange]
        var config: ReaderConfig
        
        init(_ parent: PageViewControllerRepresentable) {
            self.parent = parent
            self.text = parent.text
            self.pages = parent.pages
            self.config = parent.config
        }
        
        func viewControllerAtIndex(_ index: Int) -> UIViewController {
            guard index >= 0 && index < pages.count else {
                return UIViewController()
            }
            let contentVC = PageContentViewController()
            contentVC.index = index
            contentVC.text = text
            contentVC.range = pages[index]
            contentVC.config = config
            return contentVC
        }
        
        // MARK: - UIPageViewControllerDataSource
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let contentVC = viewController as? PageContentViewController else { return nil }
            let index = contentVC.index - 1
            if index < 0 {
                // Swipe ngược qua trang đầu tiên -> chuyển về chương trước
                parent.onSwipePastStart()
                return nil
            }
            return viewControllerAtIndex(index)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let contentVC = viewController as? PageContentViewController else { return nil }
            let index = contentVC.index + 1
            if index >= pages.count {
                // Swipe xuôi qua trang cuối -> chuyển sang chương kế tiếp
                parent.onSwipePastEnd()
                return nil
            }
            return viewControllerAtIndex(index)
        }
        
        // MARK: - UIPageViewControllerDelegate
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed,
               let currentVC = pageViewController.viewControllers?.first as? PageContentViewController {
                parent.currentPageIndex = currentVC.index
                parent.onPageChanged(currentVC.index)
            }
        }
    }
}

/// UIViewController đại diện cho 1 trang đọc
class PageContentViewController: UIViewController {
    var index: Int = 0
    var text: String = ""
    var range: NSRange = NSRange(location: 0, length: 0)
    var config = ReaderConfig()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let pageView = CoreTextPageView()
        pageView.backgroundColor = .clear
        pageView.attributedString = CoreTextPager.shared.createAttributedString(text: text, config: config)
        pageView.range = range
        pageView.margins = config.margins
        
        pageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageView)
        
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: view.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
