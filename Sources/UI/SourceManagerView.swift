import SwiftUI
import UniformTypeIdentifiers

/// Màn hình Quản lý nguồn sách (SourceManagerView)
public struct SourceManagerView: View {
    
    @State private var sources: [BookSource] = []
    
    // Import Sheet
    @State private var showImportSheet = false
    @State private var importMethod = 0 // 0: Dán JSON, 1: Nhập từ URL, 2: Chọn tệp JSON
    @State private var importJsonText = ""
    @State private var importUrlText = ""
    @State private var showDocumentPicker = false
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
                trailing: HStack(spacing: 20) {
                    NavigationLink(destination: ExtensionStoreView()) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.title2)
                    }
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
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
                Picker("Phương thức nhập", selection: $importMethod) {
                    Text("Dán JSON").tag(0)
                    Text("Nhập từ URL").tag(1)
                    Text("Chọn tệp").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)
                
                if importMethod == 0 {
                    // Dán JSON
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dán mã nguồn JSON Legado (hỗ trợ dạng mảng hoặc đối tượng đơn lẻ):")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        TextEditor(text: $importJsonText)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .frame(height: 250)
                        
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
                                    .padding(.horizontal)
                            }
                        }
                        .disabled(importJsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    }
                } else if importMethod == 1 {
                    // Nhập từ URL
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Nhập liên kết (URL) chứa tệp JSON nguồn sách:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        TextField("https://example.com/sources.json", text: $importUrlText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                        
                        Button(action: {
                            Task { await importFromUrl() }
                        }) {
                            if isImporting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Tải và nhập nguồn sách")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                            }
                        }
                        .disabled(importUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    }
                } else {
                    // Chọn tệp
                    VStack(spacing: 20) {
                        Text("Chọn tệp JSON nguồn sách từ bộ nhớ thiết bị của bạn:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        Button(action: {
                            showDocumentPicker = true
                        }) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                Text("Chọn tệp JSON từ thiết bị...")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .disabled(isImporting)
                    }
                    .padding(.vertical, 20)
                }
                
                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundColor(importMessage.hasPrefix("Thành công") ? .green : .red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .navigationTitle("Nhập Nguồn Sách")
            .navigationBarItems(leading: Button("Hủy") { showImportSheet = false })
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(allowedContentTypes: [.json], allowsMultipleSelection: false) { urls in
                    guard let url = urls.first else { return }
                    Task {
                        await importFromFile(url: url)
                    }
                } onCancel: {
                    print("[DocumentPicker] Người dùng đã hủy chọn tệp.")
                }
            }
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
        
        await parseAndSaveSources(data: jsonData)
    }
    
    private func importFromFile(url: URL) async {
        isImporting = true
        importMessage = ""
        
        do {
            let data = try Data(contentsOf: url)
            await parseAndSaveSources(data: data)
        } catch {
            importMessage = "Lỗi đọc file: \(error.localizedDescription)"
            isImporting = false
        }
    }
    
    private func importFromUrl() async {
        let urlStr = importUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlStr.isEmpty else { return }
        
        guard let url = URL(string: urlStr) else {
            importMessage = "Liên kết URL không hợp lệ"
            return
        }
        
        isImporting = true
        importMessage = ""
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
                importMessage = "Lỗi tải về: HTTP \(httpRes.statusCode)"
                isImporting = false
                return
            }
            
            await parseAndSaveSources(data: data)
        } catch {
            importMessage = "Lỗi tải URL: \(error.localizedDescription)"
            isImporting = false
        }
    }
    
    private func parseAndSaveSources(data: Data) async {
        do {
            let decoder = JSONDecoder()
            var importedList: [BookSource] = []
            
            if let list = try? decoder.decode([BookSource].self, from: data) {
                importedList = list
            } else if let single = try? decoder.decode(BookSource.self, from: data) {
                importedList = [single]
            } else {
                throw NSError(domain: "SourceManager", code: 801, userInfo: [NSLocalizedDescriptionKey: "Sai định dạng JSON nguồn sách Legado hoặc thiếu trường bắt buộc."])
            }
            
            for source in importedList {
                await DatabaseManager.shared.saveBookSource(source)
            }
            
            importMessage = "Thành công: Đã nhập \(importedList.count) nguồn sách!"
            importJsonText = ""
            importUrlText = ""
            isImporting = false
            
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
