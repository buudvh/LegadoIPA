import SwiftUI

/// Màn hình cấu hình động (Form) cho Tiện ích mở rộng VBook
public struct ExtensionConfigView: View {
    
    @Environment(\.presentationMode) var presentationMode
    
    let source: BookSource
    let onSave: () -> Void
    
    @State private var configDefinition: [String: ExtensionConfigField] = [:]
    @State private var configValues: [String: String] = [:]
    @State private var hasError = false
    @State private var errorMessage = ""
    
    public init(source: BookSource, onSave: @escaping () -> Void) {
        self.source = source
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationView {
            Form {
                if configDefinition.isEmpty {
                    Section {
                        Text("Tiện ích này không yêu cầu cấu hình thêm.")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                } else {
                    Section(header: Text("Tham số cấu hình tiện ích")) {
                        ForEach(configDefinition.keys.sorted(), id: \.self) { key in
                            let field = configDefinition[key]!
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(field.title ?? key)
                                    .font(.subheadline)
                                    .bold()
                                
                                TextField(field.default ?? "", text: Binding(
                                    get: { configValues[key] ?? "" },
                                    set: { configValues[key] = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disableAutocorrection(true)
                                .autocapitalization(.none)
                                
                                if let def = field.default, !def.isEmpty {
                                    Text("Mặc định: \(def)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section {
                        Button(action: resetToDefault) {
                            Text("Đặt lại cấu hình mặc định")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                if hasError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Cấu Hình \(source.bookSourceName)")
            .navigationBarItems(
                leading: Button("Hủy") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Lưu") {
                    saveConfiguration()
                }
                .bold()
            )
            .onAppear(perform: loadConfiguration)
        }
    }
    
    // MARK: - Logic Operations
    
    private func loadConfiguration() {
        // 1. Phân tích định nghĩa cấu hình
        if let defStr = source.extensionConfigDefinition,
           let defData = defStr.data(using: .utf8),
           let defDict = try? JSONDecoder().decode([String: ExtensionConfigField].self, from: defData) {
            configDefinition = defDict
        }
        
        // 2. Phân tích các giá trị cấu hình hiện tại
        if let valStr = source.extensionConfig,
           let valData = valStr.data(using: .utf8),
           let valDict = try? JSONSerialization.jsonObject(with: valData, options: []) as? [String: String] {
            configValues = valDict
        } else {
            // Nạp giá trị mặc định từ định nghĩa
            var defaults: [String: String] = [:]
            for (key, field) in configDefinition {
                defaults[key] = field.default ?? ""
            }
            configValues = defaults
        }
    }
    
    private func resetToDefault() {
        var defaults: [String: String] = [:]
        for (key, field) in configDefinition {
            defaults[key] = field.default ?? ""
        }
        configValues = defaults
    }
    
    private func saveConfiguration() {
        // Tự động gán CONFIG_URL tương đương với BASE_URL cấu hình mới để tương thích config.js
        if let newBase = configValues["BASE_URL"] {
            configValues["CONFIG_URL"] = newBase
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: configValues, options: []),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            hasError = true
            errorMessage = "Lỗi định dạng dữ liệu JSON cấu hình"
            return
        }
        
        var updatedSource = source
        updatedSource.extensionConfig = jsonStr
        
        Task {
            await DatabaseManager.shared.saveBookSource(updatedSource)
            onSave()
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
