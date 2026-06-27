import SwiftUI

/// Màn hình Quản lý nguồn sách (SourceManagerView)
public struct SourceManagerView: View {
    
    @State private var sources: [BookSource] = []
    
    // Import Sheet
    @State private var showImportSheet = false
    @State private var importJsonText = ""
    @State private var importMessage = ""
    @State private var isImporting = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                if sources.isEmpty {
                    Text("Chưa có nguồn sách nào được nhập. Bấm dấu cộng bên góc để nhập nguồn sách JSON của Legado nhé!")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(sources) { source in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.bookSourceName)
                                    .font(.headline)
                                Text(source.bookSourceUrl)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Toggle bật/tắt nhanh
                            Toggle("", isOn: Binding(
                                get: { source.enabled },
                                set: { val in
                                    var updated = source
                                    updated.enabled = val
                                    updateSource(updated)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete(perform: deleteSource)
                }
            }
            .navigationTitle("Nguồn Sách")
            .navigationBarItems(
                leading: EditButton(),
                trailing: Button(action: { showImportSheet = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                }
            )
            .onAppear {
                Task {
                    await refreshSources()
                }
            }
            // Sheet nhập nguồn
            .sheet(isPresented: $showImportSheet) {
                importSheetView
            }
        }
    }
    
    // MARK: - Import Sheet View
    
    private var importSheetView: some View {
        NavigationView {
            VStack(spacing: 15) {
                Text("Dán mã nguồn JSON Legado (hỗ trợ dạng mảng hoặc đối tượng đơn lẻ):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                TextEditor(text: $importJsonText)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .frame(height: 300)
                
                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundColor(importMessage.hasPrefix("Thành công") ? .green : .red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await performImport() }
                }) {
                    if isImporting {
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Nhập nguồn sách")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding()
                    }
                }
                .disabled(importJsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
            .navigationTitle("Nhập Nguồn Sách")
            .navigationBarItems(leading: Button("Hủy") { showImportSheet = false })
        }
    }
    
    // MARK: - Operations
    
    private func refreshSources() async {
        let list = await DatabaseManager.shared.getAllBookSources()
        self.sources = list
    }
    
    private func updateSource(_ source: BookSource) {
        Task {
            await DatabaseManager.shared.saveBookSource(source)
            await refreshSources()
        }
    }
    
    private func deleteSource(at offsets: IndexSet) {
        for index in offsets {
            let src = sources[index]
            Task {
                await DatabaseManager.shared.deleteBookSource(url: src.bookSourceUrl)
                await refreshSources()
            }
        }
    }
    
    private func performImport() async {
        let jsonStr = importJsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jsonStr.isEmpty else { return }
        
        isImporting = true
        importMessage = ""
        
        guard let jsonData = jsonStr.data(using: .utf8) else {
            importMessage = "Mã hóa UTF-8 không hợp lệ"
            isImporting = false
            return
        }
        
        do {
            let decoder = JSONDecoder()
            var importedList: [BookSource] = []
            
            // Thử decode dưới dạng mảng [BookSource] trước, sau đó là đối tượng đơn lẻ BookSource
            if let list = try? decoder.decode([BookSource].self, from: jsonData) {
                importedList = list
            } else if let single = try? decoder.decode(BookSource.self, from: jsonData) {
                importedList = [single]
            } else {
                // Thử parse JSON thủ công nếu định dạng có sự sai lệch nhỏ trong trường key
                throw NSError(domain: "SourceManager", code: 801, userInfo: [NSLocalizedDescriptionKey: "Sai định dạng JSON nguồn sách Legado"])
            }
            
            for source in importedList {
                await DatabaseManager.shared.saveBookSource(source)
            }
            
            importMessage = "Thành công: Đã nhập \(importedList.count) nguồn sách!"
            importJsonText = ""
            isImporting = false
            
            // Tự động đóng sheet sau 1.5 giây
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showImportSheet = false
                Task {
                    await self.refreshSources()
                }
            }
        } catch {
            importMessage = "Lỗi: \(error.localizedDescription)"
            isImporting = false
        }
    }
}
