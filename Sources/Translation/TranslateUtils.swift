import Foundation
import CryptoKit

/// Tiện ích dịch thuật tự động Việt hóa Hán-Việt cho LegadoIPA
public final class TranslateUtils {
    
    // Cache lưu trữ các bản dịch trong RAM (giới hạn 10MB bộ nhớ)
    private static let translationCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 Megabytes
        return cache
    }()
    
    public static var isTranslateEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "translateEnable")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "translateEnable")
            clearCache()
        }
    }
    
    // Bản đồ chuyển đổi dấu câu Trung -> Việt
    private static let punctuationMapping: [Character: String] = [
        "。": ". ", "．": ". ", "，": ", ", "、": ", ", "；": ";", "：": ": ", "！": "!", "？": "?", "…": "...",
        "（": "【", "）": "】",
        "〔": "【", "〕": "】",
        "【": "【", "】": "】",
        "〖": "【", "〗": "】",
        "〘": "【", "〙": "】",
        "〚": "【", "〛": "】",
        "『": "【", "』": "】",
        "《": "【", "》": "】",
        "〈": "【", "〉": "】",
        "｛": "【", "｝": "】",
        "「": "【", "」": "】",
        "(": "【", ")": "】",
        "{": "【", "}": "】",
        "～": "~", "—": "-", "　": " "
    ]
    
    // Bản đồ phân loại chương
    private static let chapterUnitMap: [String: String] = [
        "卷": "Quyển",
        "回": "Hồi",
        "章": "Chương",
        "幕": "Màn",
        "折": "Chiết",
        "节": "Tiết",
        "集": "Tập"
    ]
    
    private init() {}
    
    /// Dịch tiêu đề chương (VD: 第二十二章: 斩首 -> Chương 22: Trảm Thủ)
    public static func translateChapterTitle(_ raw: String) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if !isTranslateEnabled { return text }
        
        // Regex: Thứ [số Trung Quốc hoặc chữ số] [đơn vị]
        let pattern = "第\\s*([0-9一二三四五六七八九十百千零〇两]+)\\s*([卷回章节幕折集])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return await translateMeta(text)
        }
        
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return await translateMeta(text)
        }
        
        // Trích xuất phần số và đơn vị
        guard let numRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return await translateMeta(text)
        }
        
        let numberCn = String(text[numRange])
        let unitCn = String(text[unitRange])
        
        let number = chineseNumberToInt(numberCn)
        let unitVi = chapterUnitMap[unitCn] ?? "Chương"
        
        let chapterPart = "\(unitVi) \(number)"
        
        // Dịch phần trước và sau match
        let matchStart = match.range.location
        let matchEnd = match.range.location + match.range.length
        
        let preMatchRange = text.startIndex..<text.index(text.startIndex, offsetBy: matchStart)
        let postMatchRange = text.index(text.startIndex, offsetBy: matchEnd)..<text.endIndex
        
        let preMatch = String(text[preMatchRange])
        let postMatch = String(text[postMatchRange])
        
        let translatedPre = preMatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : await translateMeta(preMatch) + " "
        let translatedPostRaw = postMatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : (await translateMeta(postMatch)).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let separator: String
        if !translatedPostRaw.isEmpty {
            if translatedPostRaw.hasPrefix(":") || translatedPostRaw.hasPrefix("：") {
                separator = ""
            } else {
                separator = ": "
            }
        } else {
            separator = ""
        }
        
        let translatedPost = !translatedPostRaw.isEmpty ? separator + translatedPostRaw : ""
        
        return "\(translatedPre)\(chapterPart)\(translatedPost)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Dịch siêu dữ liệu (tên sách, tác giả, tóm tắt)
    public static func translateMeta(_ text: String?) async -> String {
        return await translateText(text, isMeta: true)
    }
    
    /// Dịch nội dung chương truyện
    public static func translateContent(_ text: String?) async -> String {
        return await translateText(text, isMeta: false)
    }
    
    /// Dịch nguồn phân loại hoặc link explore (Name::URL)
    public static func translateSortExploreUrl(_ raw: String?) async -> String? {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return raw }
        if !isTranslateEnabled { return raw }
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("@js:") || trimmed.lowercased().hasPrefix("<js>") {
            return raw
        }
        if trimmed.hasPrefix("[") {
            return await translateCode(raw)
        }
        
        let lines = raw.components(separatedBy: .newlines)
        var resultLines: [String] = []
        for line in lines {
            if line.contains("::") {
                let parts = line.components(separatedBy: "::")
                if parts.count >= 2 {
                    let name = parts[0]
                    let url = parts[1...].joined(separator: "::")
                    let translatedName = await translateCode(name)
                    resultLines.append("\(translatedName)::\(url)")
                } else {
                    resultLines.append(await translateCode(line))
                }
            } else {
                resultLines.append(await translateCode(line))
            }
        }
        return resultLines.joined(separator: "\n")
    }
    
    /// Dịch cấu trúc code / JSON nguồn truyện (giữ nguyên cú pháp)
    public static func translateCode(_ text: String?) async -> String {
        guard let text = text, !text.isEmpty else { return text ?? "" }
        if !isTranslateEnabled { return text }
        
        let cacheKey = "translate|vietphrase|v2|code|" + md5_16(text)
        if let cached = translationCache.object(forKey: cacheKey as NSString) {
            return cached as String
        }
        
        let translated = await performCodeTranslation(text)
        let cost = translated.utf8.count + cacheKey.utf8.count
        translationCache.setObject(translated as NSString, forKey: cacheKey as NSString, cost: cost)
        return translated
    }
    
    // MARK: - Core Algorithm (Thuật toán lõi)
    
    private static func translateText(_ text: String?, isMeta: Bool) async -> String {
        guard let text = text, !text.isEmpty else { return text ?? "" }
        if !isTranslateEnabled { return text }
        
        let cacheKey = generateCacheKey(text, isMeta: isMeta)
        if let cached = translationCache.object(forKey: cacheKey as NSString) {
            return cached as String
        }
        
        let translated = await performTranslation(text)
        let cost = translated.utf8.count + cacheKey.utf8.count
        translationCache.setObject(translated as NSString, forKey: cacheKey as NSString, cost: cost)
        return translated
    }
    
    private static func performTranslation(_ text: String) async -> String {
        guard let data = try? await TranslationLoader.shared.loadTranslationData() else {
            return text
        }
        
        // Bước 1: Chuyển đổi dấu câu
        let convertedText = convertPunctuation(text)
        
        // Bước 2: Tách từ
        let tokens = tokenize(convertedText, data: data)
        
        // Bước 3: Dịch nghĩa & Phiên âm
        var translatedWords: [String] = []
        for token in tokens {
            if token == "的" || token == "了" || token == "著" {
                continue
            }
            
            var translation = searchInDictionaries(token, data: data)
            if let trans = translation {
                if trans.contains("/") {
                    translation = trans.components(separatedBy: "/").first
                }
            } else {
                translation = token
            }
            
            let finalWord: String
            if translation == token {
                finalWord = data.chinesePhienAm[token] ?? " \(token) "
            } else {
                finalWord = translation ?? token
            }
            
            translatedWords.append(finalWord)
        }
        
        // Bước 4: Chuẩn hóa khoảng trắng & Viết hoa đầu câu
        return processText(translatedWords.joined(separator: " "))
    }
    
    private static func performCodeTranslation(_ text: String) async -> String {
        guard let data = try? await TranslationLoader.shared.loadTranslationData() else {
            return text
        }
        
        let tokens = tokenize(text, data: data)
        var result = ""
        
        for token in tokens {
            if token.isEmpty { continue }
            
            guard let firstChar = token.first, isChineseCharacter(firstChar) else {
                result += token
                continue
            }
            
            if token == "的" || token == "了" || token == "著" {
                continue
            }
            
            var translation = searchInDictionaries(token, data: data)
            if let trans = translation {
                if trans.contains("/") {
                    translation = trans.components(separatedBy: "/").first
                }
                
                if let lastChar = result.last, lastChar.isLetter || lastChar.isNumber {
                    result += " "
                }
                result += translation ?? ""
            } else {
                if let phienAm = data.chinesePhienAm[token] {
                    if let lastChar = result.last, lastChar.isLetter || lastChar.isNumber {
                        result += " "
                    }
                    result += phienAm
                } else {
                    result += token
                }
            }
        }
        
        return result
    }
    
    private static func searchInDictionaries(_ key: String, data: TranslationData) -> String? {
        if let match = data.names.findLongestMatch(text: key, startIndex: 0), match.0 == key.count {
            return match.1
        }
        if let match = data.vietPhrase.findLongestMatch(text: key, startIndex: 0), match.0 == key.count {
            return match.1
        }
        return nil
    }
    
    private static func tokenize(_ text: String, data: TranslationData) -> [String] {
        var output: [String] = []
        let scalars = Array(text.unicodeScalars)
        let length = scalars.count
        var currentIndex = 0
        
        while currentIndex < length {
            var longestMatchLen = 0
            
            // Tìm trong từ điển Names
            if let match = data.names.findLongestMatch(chars: scalars, startIndex: currentIndex) {
                if match.0 > longestMatchLen {
                    longestMatchLen = match.0
                }
            }
            
            // Tìm trong từ điển VietPhrase
            if let match = data.vietPhrase.findLongestMatch(chars: scalars, startIndex: currentIndex) {
                if match.0 > longestMatchLen {
                    longestMatchLen = match.0
                }
            }
            
            if longestMatchLen > 0 {
                var tokenScalars = [UnicodeScalar]()
                tokenScalars.reserveCapacity(longestMatchLen)
                for idx in currentIndex..<(currentIndex + longestMatchLen) {
                    tokenScalars.append(scalars[idx])
                }
                output.append(String(String.UnicodeScalarView(tokenScalars)))
                currentIndex += longestMatchLen
            } else {
                let scalar = scalars[currentIndex]
                if isChineseCharacter(scalar) {
                    output.append(String(scalar))
                    currentIndex += 1
                } else {
                    // Nhóm các ký tự Latin/số/dấu câu
                    var nonCnStr = String(scalar)
                    currentIndex += 1
                    while currentIndex < length && !isChineseCharacter(scalars[currentIndex]) {
                        nonCnStr.append(Character(scalars[currentIndex]))
                        currentIndex += 1
                    }
                    output.append(nonCnStr)
                }
            }
        }
        
        return output
    }
    
    private static func isChineseCharacter(_ scalar: Unicode.Scalar) -> Bool {
        return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
    }
    
    private static func convertPunctuation(_ text: String) -> String {
        var result = ""
        for char in text {
            if let mapped = punctuationMapping[char] {
                result += mapped
            } else {
                result.append(char)
            }
        }
        return result
    }
    
    private static func processText(_ input: String) -> String {
        let lines = input.components(separatedBy: .newlines)
        let processingLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = processingLines.joined(separator: "\n")
        
        // 1. Sửa khoảng trắng trước các dấu câu
        let trimBeforePattern = " +([,.?!\\]>”’):】])"
        if let regex = try? NSRegularExpression(pattern: trimBeforePattern, options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: nsRange, withTemplate: "$1")
        }
        
        // 2. Sửa khoảng trắng sau các dấu mở ngoặc/ngoặc kép
        let trimAfterPattern = "([<\\[“‘(【]) +"
        if let regex = try? NSRegularExpression(pattern: trimAfterPattern, options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: nsRange, withTemplate: "$1")
        }
        
        // 3. Viết hoa ký tự đầu tiên sau các dấu chấm câu kết đoạn/câu
        result = capitalizeSentences(in: result)
        
        // 4. Chuẩn hóa các dấu ngoặc kép của Trung Quốc thành chuẩn quốc tế
        result = result.replacingOccurrences(of: "“", with: "\"")
                       .replacingOccurrences(of: "”", with: "\"")
                       .replacingOccurrences(of: "‘", with: "'")
                       .replacingOccurrences(of: "’", with: "'")
        
        // 5. Loại bỏ khoảng trắng thừa liên tiếp
        if let regex = try? NSRegularExpression(pattern: " +", options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: nsRange, withTemplate: " ")
        }
        
        return result
    }
    
    private static func capitalizeSentences(in text: String) -> String {
        // Regex bắt đầu câu hoặc sau dấu chấm câu kết thúc (. ! ? " ' [ 【 -)
        let pattern = "(^\\s*|[.!?\"'\\[【-]\\s*)(\\p{Ll})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return text
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        
        let matches = regex.matches(in: text, options: [], range: range)
        for match in matches.reversed() {
            guard let p2Range = Range(match.range(at: 2), in: result) else { continue }
            let uppercaseChar = result[p2Range].uppercased()
            result.replaceSubrange(p2Range, with: uppercaseChar)
        }
        return result
    }
    
    // MARK: - Utility Methods
    
    private static func chineseNumberToInt(_ chineseNumber: String) -> Int {
        if chineseNumber.allSatisfy({ $0.isNumber }) {
            return Int(chineseNumber) ?? 0
        }
        
        let cnDigitMap: [Character: Int] = [
            "零": 0, "〇": 0,
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        
        let multipliers: Set<Character> = ["十", "百", "千", "万"]
        let hasMultiplier = chineseNumber.contains(where: { multipliers.contains($0) })
        
        if !hasMultiplier {
            // Trường hợp chữ số liệt kê liền kề (Ví dụ: 一二三 -> 123)
            var numStr = ""
            for char in chineseNumber {
                if let val = cnDigitMap[char] {
                    numStr += "\(val)"
                } else if char.isNumber {
                    numStr += String(char)
                }
            }
            return Int(numStr) ?? 0
        }
        
        var result = 0
        var temp = 0
        
        for char in chineseNumber {
            if let val = cnDigitMap[char] {
                temp = val
            } else if char == "十" {
                if temp == 0 { temp = 1 }
                result += temp * 10
                temp = 0
            } else if char == "百" {
                result += temp * 100
                temp = 0
            } else if char == "千" {
                result += temp * 1000
                temp = 0
            } else if char == "万" {
                result += temp
                result *= 10000
                temp = 0
            } else if char.isNumber {
                temp = Int(String(char)) ?? 0
            }
        }
        result += temp
        return result
    }
    
    private static func generateCacheKey(_ text: String, isMeta: Bool) -> String {
        let md5 = md5_16(text)
        let type = isMeta ? "meta" : "content"
        return "translate|vietphrase|v2|\(type)|\(md5)"
    }
    
    private static func md5_16(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        let hexString = digest.map { String(format: "%02hhx", $0) }.joined()
        // Trả về 16 ký tự ở giữa (từ index 8 đến 24) tương tự như MD5Utils.md5Encode16 trên Android
        let start = hexString.index(hexString.startIndex, offsetBy: 8)
        let end = hexString.index(start, offsetBy: 16)
        return String(hexString[start..<end])
    }
    
    public static func clearCache() {
        translationCache.removeAllObjects()
    }
}
