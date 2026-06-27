import SwiftUI

/// Màn hình Tủ sách (BookshelfView)
public struct BookshelfView: View {
    @State private var books: [Book] = []
    @State private var selectedBook: Book? = nil
    
    // Trạng thái xuất Markdown
    @State private var exportingBook: Book? = nil
    @State private var exportProgress: Double = 0.0
    @State private var exportMessage: String = ""
    @State private var showExportAlert = false
    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemGroupedBackground), Color(.systemBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if books.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text("Tủ sách trống")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Hãy qua tab Khám phá để tìm và nhập sách nhé!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            ForEach(books) { book in
                                bookCard(book: book)
                            }
                        }
                        .padding()
                    }
                }
                
                // Overlay Tiến độ Xuất Markdown
                if exportingBook != nil {
                    exportProgressOverlay
                }
            }
            .navigationTitle("Tủ Sách Legado")
            .onAppear {
                Task {
                    await refreshBookshelf()
                }
            }
            // Điều hướng sang màn hình đọc truyện
            .fullScreenCover(item: $selectedBook) { book in
                BookReaderView(book: book)
            }
            // Sheet chia sẻ file .md sau khi xuất xong
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    // MARK: - Book Card Component
    
    private func bookCard(book: Book) -> some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .bottomTrailing) {
                // Ảnh bìa
                if let coverStr = book.coverUrl, let url = URL(string: coverStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            placeholderCover(name: book.name)
                        }
                    }
                    .frame(height: 180)
                    .clipped()
                } else {
                    placeholderCover(name: book.name)
                        .frame(height: 180)
                }
                
                // Nút Export Markdown nhanh ở góc dưới ảnh bìa
                Button(action: {
                    startMarkdownExport(for: book)
                }) {
                    Image(systemName: "arrow.down.doc.fill")
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.green)
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(book.author ?? "Ẩn danh")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Tiến độ đọc
                let totalChaps = 100 // Giả lập tổng chương
                let percent = Double(book.durChapterIndex + 1) / Double(totalChaps) * 100
                Text("Đã đọc: \(Int(percent))%")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
        .onTapGesture {
            selectedBook = book
        }
    }
    
    private func placeholderCover(name: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(name.prefix(3)))
                .font(.title2)
                .bold()
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Progress Overlay
    
    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Đang xuất sách dạng Markdown")
                    .font(.headline)
                
                ProgressView(value: exportProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 250)
                
                Text(exportMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }
            .padding(30)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 10)
        }
    }
    
    // MARK: - Operations
    
    private func refreshBookshelf() async {
        let list = await DatabaseManager.shared.getAllBooks()
        self.books = list
    }
    
    private func startMarkdownExport(for book: Book) {
        exportingBook = book
        exportProgress = 0.0
        exportMessage = "Bắt đầu khởi động..."
        
        Task {
            // Lấy nguồn sách
            guard let source = await DatabaseManager.shared.getBookSource(url: book.origin) else {
                exportingBook = nil
                return
            }
            
            do {
                let fileURL = try await MarkdownExporter.shared.exportBook(book, source: source) { progress, message in
                    DispatchQueue.main.async {
                        self.exportProgress = progress
                        self.exportMessage = message
                    }
                }
                
                // Xuất file xong
                DispatchQueue.main.async {
                    self.exportedFileURL = fileURL
                    self.exportingBook = nil
                    self.showShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.exportMessage = "Lỗi: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.exportingBook = nil
                    }
                }
            }
        }
    }
}

// MARK: - Share Sheet Helper (UIActivityViewController Wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
