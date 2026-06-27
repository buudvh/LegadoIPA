import Foundation

/// Định nghĩa các loại nguồn sách
public enum BookSourceType: Int, Codable {
    case text = 0      // Truyện chữ (Text)
    case audio = 1     // Truyện nói (Audio)
    case image = 2     // Truyện tranh (Manga/Comic)
    case file = 3      // Tệp tải về (Download file)
    case video = 4     // Phim/Video
}

/// Quy tắc tìm kiếm sách (Search Rule)
public struct SearchRule: Codable, Equatable {
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        checkKeyWord: String? = nil,
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.checkKeyWord = checkKeyWord
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}

/// Quy tắc khám phá/danh mục (Explore Rule)
public struct ExploreRule: Codable, Equatable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}

/// Quy tắc thông tin chi tiết sách (Book Info Rule)
public struct BookInfoRule: Codable, Equatable {
    public var initRule: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?

    public init(
        initRule: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil,
        wordCount: String? = nil,
        canReName: String? = nil
    ) {
        self.initRule = initRule
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
        self.wordCount = wordCount
        self.canReName = canReName
    }
}

/// Quy tắc danh sách chương (Table of Contents Rule)
public struct TocRule: Codable, Equatable {
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var isVip: String?
    public var isVolume: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?

    public init(
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        isVip: String? = nil,
        isVolume: String? = nil,
        isPay: String? = nil,
        updateTime: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.isVip = isVip
        self.isVolume = isVolume
        self.isPay = isPay
        self.updateTime = updateTime
        self.nextTocUrl = nextTocUrl
    }
}

/// Quy tắc lấy nội dung chương (Content Rule)
public struct ContentRule: Codable, Equatable {
    public var content: String?
    public var nextContentUrl: String?
    public var title: String?
    public var sourceRegex: String?
    public var webJs: String?
    public var imageStyle: String?
    public var payAction: String?

    public init(
        content: String? = nil,
        nextContentUrl: String? = nil,
        title: String? = nil,
        sourceRegex: String? = nil,
        webJs: String? = nil,
        imageStyle: String? = nil,
        payAction: String? = nil
    ) {
        self.content = content
        self.nextContentUrl = nextContentUrl
        self.title = title
        self.sourceRegex = sourceRegex
        self.webJs = webJs
        self.imageStyle = imageStyle
        self.payAction = payAction
    }
}

/// Quy tắc bình luận đoạn văn (Review Rule)
public struct ReviewRule: Codable, Equatable {
    public var reviewUrl: String?
    public var avatar: String?
    public var content: String?
    public var postTime: String?
    public var user: String?

    public init(
        reviewUrl: String? = nil,
        avatar: String? = nil,
        content: String? = nil,
        postTime: String? = nil,
        user: String? = nil
    ) {
        self.reviewUrl = reviewUrl
        self.avatar = avatar
        self.content = content
        self.postTime = postTime
        self.user = user
    }
}

/// Quy tắc xuất Markdown (Markdown Export Rule)
public struct MarkdownExportTemplate: Codable, Equatable {
    public var frontmatter: String?
    public var chapterHeader: String?
    public var chapterContentFormat: String?
    public var useVietPhrase: Bool

    public init(
        frontmatter: String? = "---\ntitle: \"{title}\"\nauthor: \"{author}\"\nsource: \"{sourceUrl}\"\ndescription: \"{intro}\"\nexport_date: \"{currentDate}\"\n---\n\n",
        chapterHeader: String? = "\n\n# {chapterTitle}\n\n",
        chapterContentFormat: String? = "{paragraph}\n",
        useVietPhrase: Bool = true
    ) {
        self.frontmatter = frontmatter
        self.chapterHeader = chapterHeader
        self.chapterContentFormat = chapterContentFormat
        self.useVietPhrase = useVietPhrase
    }
}

public struct CrawlerSettings: Codable, Equatable {
    public var concurrentRequests: Int
    public var delayBetweenRequestsMs: Int
    public var timeoutMs: Int
    public var retryCount: Int

    public init(
        concurrentRequests: Int = 3,
        delayBetweenRequestsMs: Int = 500,
        timeoutMs: Int = 15000,
        retryCount: Int = 3
    ) {
        self.concurrentRequests = concurrentRequests
        self.delayBetweenRequestsMs = delayBetweenRequestsMs
        self.timeoutMs = timeoutMs
        self.retryCount = retryCount
    }
}

public struct MarkdownExportRule: Codable, Equatable {
    public var saveFormat: String // "markdown" hoặc "text"
    public var outputTemplate: MarkdownExportTemplate
    public var crawlerSettings: CrawlerSettings

    public init(
        saveFormat: String = "markdown",
        outputTemplate: MarkdownExportTemplate = MarkdownExportTemplate(),
        crawlerSettings: CrawlerSettings = CrawlerSettings()
    ) {
        self.saveFormat = saveFormat
        self.outputTemplate = outputTemplate
        self.crawlerSettings = crawlerSettings
    }
}

/// Đối tượng nguồn sách chính (BookSource)
public struct BookSource: Codable, Identifiable, Equatable {
    public var id: String { bookSourceUrl } // Thỏa mãn giao thức Identifiable trong SwiftUI
    
    public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    public var bookSourceType: BookSourceType
    public var bookUrlPattern: String?
    public var customOrder: Int
    public var enabled: Bool
    public var enabledExplore: Bool
    public var jsLib: String?
    public var enabledCookieJar: Bool?
    public var concurrentRate: String?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var coverDecodeJs: String?
    public var bookSourceComment: String?
    public var variableComment: String?
    public var lastUpdateTime: Int64
    public var respondTime: Int64
    public var weight: Int
    public var exploreUrl: String?
    public var exploreScreen: String?
    
    public var ruleExplore: ExploreRule?
    public var searchUrl: String?
    public var ruleSearch: SearchRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?
    public var ruleReview: ReviewRule?
    
    public var eventListener: Bool
    public var customButton: Bool
    
    // Cấu hình xuất Markdown đi kèm nguồn sách
    public var markdownExportRule: MarkdownExportRule?

    public init(
        bookSourceUrl: String = "",
        bookSourceName: String = "",
        bookSourceGroup: String? = nil,
        bookSourceType: BookSourceType = .text,
        bookUrlPattern: String? = nil,
        customOrder: Int = 0,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        jsLib: String? = nil,
        enabledCookieJar: Bool? = true,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        bookSourceComment: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64 = 0,
        respondTime: Int64 = 180000,
        weight: Int = 0,
        exploreUrl: String? = nil,
        exploreScreen: String? = nil,
        ruleExplore: ExploreRule? = nil,
        searchUrl: String? = nil,
        ruleSearch: SearchRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil,
        ruleReview: ReviewRule? = nil,
        eventListener: Bool = false,
        customButton: Bool = false,
        markdownExportRule: MarkdownExportRule? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookUrlPattern = bookUrlPattern
        self.customOrder = customOrder
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.coverDecodeJs = coverDecodeJs
        self.bookSourceComment = bookSourceComment
        self.variableComment = variableComment
        self.lastUpdateTime = lastUpdateTime
        self.respondTime = respondTime
        self.weight = weight
        self.exploreUrl = exploreUrl
        self.exploreScreen = exploreScreen
        self.ruleExplore = ruleExplore
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.ruleReview = ruleReview
        self.eventListener = eventListener
        self.customButton = customButton
        self.markdownExportRule = markdownExportRule
    }
}
