import Foundation

/// Thỏa diện giao diện tra cứu từ điển
public protocol TrieDictionaryProtocol {
    func findLongestMatch(text: String, startIndex: Int) -> (Int, String)?
    func findLongestMatch(chars: [Unicode.Scalar], startIndex: Int) -> (Int, String)?
    subscript(key: String) -> String? { get }
}

/// Hiện thực cấu trúc mảng đôi (Double-Array Trie) phiên bản Swift
/// Tương thích định dạng nhị phân VERSION 3 của Legado-QT (Big Endian)
public final class DoubleArrayTrie: TrieDictionaryProtocol {
    
    private var base: [Int32] = []
    private var check: [Int32] = []
    private var fastCharMap = [Int32](repeating: 0, count: 65536)
    private var charMap: [Unicode.Scalar: Int32] = [:]
    
    // String pool chứa các cụm từ nghĩa tiếng Việt
    private var stringPool = Data()
    private var isMapped = false
    private var size = 0
    private var maxCharValue = 0
    
    // Thuộc tính dùng khi build
    private var used: [Bool] = []
    private var nextCheckPos = 0
    
    private static let MAGIC: Int32 = 0x44415432
    private static let VERSION: Int32 = 3
    
    public init() {}
    
    // MARK: - LOOKUP (Tra cứu)
    
    /// Tìm kiếm khớp dài nhất bắt đầu tại vị trí startIndex
    public func findLongestMatch(text: String, startIndex: Int) -> (Int, String)? {
        let scalars = Array(text.unicodeScalars)
        return findLongestMatch(chars: scalars, startIndex: startIndex)
    }

    /// Phiên bản tối ưu: Sử dụng mảng Unicode.Scalar đã được phân rã sẵn bên ngoài để tránh cấp phát lặp lại O(N)
    public func findLongestMatch(chars: [Unicode.Scalar], startIndex: Int) -> (Int, String)? {
        guard startIndex < chars.count else { return nil }
        
        var currentState: Int32 = 1
        var matchLen = -1
        var matchStringPoolOffset: Int32 = -1
        var currentIndex = startIndex
        
        let checkCount = check.count
        
        while currentIndex < chars.count {
            let scalar = chars[currentIndex]
            let charCodeValue = scalar.value
            
            // Tra cứu mã ký tự được map
            let charCode: Int32
            if charCodeValue < 65536 {
                charCode = fastCharMap[Int(charCodeValue)]
            } else {
                charCode = charMap[scalar] ?? 0
            }
            
            if charCode == 0 { break }
            
            let nextState = base[Int(currentState)] + charCode
            if nextState < 0 || nextState >= checkCount || check[Int(nextState)] != currentState {
                break
            }
            
            // Kiểm tra trạng thái kết thúc (Terminal node)
            let termState = base[Int(nextState)]
            if termState >= 0 && termState < checkCount && check[Int(termState)] == nextState {
                matchStringPoolOffset = base[Int(termState)]
                matchLen = currentIndex - startIndex + 1
            }
            
            currentState = nextState
            currentIndex += 1
        }
        
        if matchLen > 0 && matchStringPoolOffset >= 0 {
            // Lấy chuỗi từ stringPool dựa trên offset
            let offset = Int(matchStringPoolOffset)
            if offset + 2 <= stringPool.count {
                let lenBytes = stringPool.subdata(in: offset..<offset+2)
                let strLen = Int(UInt16(bigEndian: lenBytes.withUnsafeBytes { $0.load(as: UInt16.self) }))
                if offset + 2 + strLen <= stringPool.count {
                    let strData = stringPool.subdata(in: (offset + 2)..<(offset + 2 + strLen))
                    if let valStr = String(data: strData, encoding: .utf8) {
                        return (matchLen, valStr)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Tra cứu từ điển bằng subscript
    public subscript(key: String) -> String? {
        guard let match = findLongestMatch(text: key, startIndex: 0) else { return nil }
        return match.0 == key.count ? match.1 : nil
    }
    
    // MARK: - LOADING BINARY (Tải file nhị phân)
    
    /// Nạp dữ liệu nhị phân từ đường dẫn tệp (hỗ trợ Memory Mapping qua options của Data)
    public func load(from fileURL: URL) throws {
        // Tương tự mmap bằng cách dùng NSData.ReadingOptions.mappedIfSafe
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe, .uncached])
        
        guard data.count >= 24 else {
            throw NSError(domain: "DoubleArrayTrie", code: 101, userInfo: [NSLocalizedDescriptionKey: "Kích thước file quá nhỏ"])
        }
        
        // Đọc header
        let magic = data.readBigEndianInt32(at: 0)
        let version = data.readBigEndianInt32(at: 4)
        
        guard magic == DoubleArrayTrie.MAGIC else {
            throw NSError(domain: "DoubleArrayTrie", code: 102, userInfo: [NSLocalizedDescriptionKey: "Định dạng magic DAT không hợp lệ"])
        }
        guard version == DoubleArrayTrie.VERSION else {
            throw NSError(domain: "DoubleArrayTrie", code: 103, userInfo: [NSLocalizedDescriptionKey: "Phiên bản DAT không được hỗ trợ"])
        }
        
        self.size = Int(data.readBigEndianInt32(at: 8))
        let baseLen = Int(data.readBigEndianInt32(at: 12))
        let charMapSize = Int(data.readBigEndianInt32(at: 16))
        self.maxCharValue = Int(data.readBigEndianInt32(at: 20))
        
        // Đọc char mapping
        fastCharMap = [Int32](repeating: 0, count: 65536)
        charMap.removeAll(keepingCapacity: true)
        
        var offset = 24
        for _ in 0..<charMapSize {
            let charCode = data.readBigEndianInt32(at: offset)
            let mappedCode = data.readBigEndianInt32(at: offset + 4)
            offset += 8
            
            if charCode >= 0 && charCode < 65536 {
                fastCharMap[Int(charCode)] = mappedCode
            }
            if let scalar = UnicodeScalar(UInt32(charCode)) {
                charMap[scalar] = mappedCode
            }
        }
        
        // Đọc base và check arrays
        let baseByteOffset = offset
        let checkByteOffset = baseByteOffset + baseLen * 4
        let stringPoolSizeOffset = checkByteOffset + baseLen * 4
        
        guard baseByteOffset % 4 == 0 && checkByteOffset % 4 == 0 else {
            throw NSError(domain: "DoubleArrayTrie", code: 106, userInfo: [NSLocalizedDescriptionKey: "Offset mảng không căn lề đúng 4-byte"])
        }
        
        guard stringPoolSizeOffset + 4 <= data.count else {
            throw NSError(domain: "DoubleArrayTrie", code: 104, userInfo: [NSLocalizedDescriptionKey: "File bị hỏng, kích thước mảng không khớp"])
        }
        
        base = [Int32](repeating: 0, count: baseLen)
        check = [Int32](repeating: 0, count: baseLen)
        
        // Sửa lỗi Memory Alignment: Dùng copyBytes thay vì bindMemory trực tiếp từ raw pointer
        let baseByteCount = baseLen * 4
        var tempBase = [Int32](repeating: 0, count: baseLen)
        _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &tempBase, count: baseLen), from: baseByteOffset..<(baseByteOffset + baseByteCount))
        for i in 0..<baseLen {
            base[i] = Int32(bigEndian: tempBase[i])
        }
        
        var tempCheck = [Int32](repeating: 0, count: baseLen)
        _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &tempCheck, count: baseLen), from: checkByteOffset..<(checkByteOffset + baseByteCount))
        for i in 0..<baseLen {
            check[i] = Int32(bigEndian: tempCheck[i])
        }
        
        // Đọc string pool
        let poolSize = Int(data.readBigEndianInt32(at: stringPoolSizeOffset))
        let poolBytesOffset = stringPoolSizeOffset + 4
        
        guard poolBytesOffset + poolSize <= data.count else {
            throw NSError(domain: "DoubleArrayTrie", code: 105, userInfo: [NSLocalizedDescriptionKey: "Kích thước string pool không hợp lệ"])
        }
        
        self.stringPool = data.subdata(in: poolBytesOffset..<(poolBytesOffset + poolSize))
        self.isMapped = true
    }
    
    // MARK: - BUILDING & SAVING (Xây dựng từ điển)
    
    /// Xây dựng và lưu cấu trúc Trie ra tệp nhị phân
    public func save(to outputStream: OutputStream, entries: [(String, String)]) throws {
        let sortedEntries = entries.sorted { $0.0 < $1.0 }
        
        // Tạo string pool và lưu offsets
        var poolData = Data()
        var stringOffsets = [Int](repeating: 0, count: sortedEntries.count)
        
        for i in 0..<sortedEntries.count {
            stringOffsets[i] = poolData.count
            if let utf8Bytes = sortedEntries[i].1.data(using: .utf8) {
                var len = UInt16(utf8Bytes.count).bigEndian
                withUnsafeBytes(of: &len) { poolData.append(contentsOf: $0) }
                poolData.append(utf8Bytes)
            } else {
                var len: UInt16 = 0
                withUnsafeBytes(of: &len) { poolData.append(contentsOf: $0) }
            }
        }
        
        let keys = sortedEntries.map { $0.0 }
        buildForSave(keys: keys, stringOffsets: stringOffsets)
        
        // Ghi dữ liệu ra stream
        outputStream.open()
        defer { outputStream.close() }
        
        func writeInt32(_ val: Int32) {
            var bigEndianVal = val.bigEndian
            withUnsafeBytes(of: &bigEndianVal) {
                _ = $0.withMemoryRebound(to: UInt8.self) { ptr in
                    outputStream.write(ptr.baseAddress!, maxLength: 4)
                }
            }
        }
        
        writeInt32(DoubleArrayTrie.MAGIC)
        writeInt32(DoubleArrayTrie.VERSION)
        writeInt32(Int32(size))
        writeInt32(Int32(base.count))
        writeInt32(Int32(charMap.count))
        writeInt32(Int32(maxCharValue))
        
        // Ghi char map
        // Sắp xếp charMap theo mã key
        let sortedCharMap = charMap.sorted { $0.key < $1.key }
        for (char, code) in sortedCharMap {
            let charCode = Int32(char.utf16.first ?? 0)
            writeInt32(charCode)
            writeInt32(code)
        }
        
        // Ghi mảng base
        for val in base {
            writeInt32(val)
        }
        
        // Ghi mảng check
        for val in check {
            writeInt32(val)
        }
        
        // Ghi string pool size và data
        writeInt32(Int32(poolData.count))
        _ = poolData.withUnsafeBytes {
            outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: poolData.count)
        }
        
        // Giải phóng mảng build
        used.removeAll()
    }
    
    private func buildForSave(keys: [String], stringOffsets: [Int]) {
        if keys.isEmpty {
            base = [0]
            check = [-1]
            used = [false]
            size = 0
            return
        }
        
        size = keys.count
        buildCharMapping(keys: keys)
        
        let initialSize = max(1024, calculateInitialSize(keys: keys))
        base = [Int32](repeating: 0, count: initialSize)
        check = [Int32](repeating: -1, count: initialSize)
        used = [Bool](repeating: false, count: initialSize)
        nextCheckPos = 0
        
        check[1] = 0
        base[1] = 1
        
        let root = Node(code: 0, depth: 0, left: 0, right: keys.count)
        let siblings = fetch(parent: root, keys: keys)
        insertWithOffsets(siblings: siblings, parentIndex: 1, keys: keys, stringOffsets: stringOffsets)
        compactArrays()
    }
    
    private func buildCharMapping(keys: [String]) {
        var uniqueScalars = Set<Unicode.Scalar>()
        for key in keys {
            for scalar in key.unicodeScalars {
                uniqueScalars.insert(scalar)
            }
        }
        
        charMap.removeAll()
        fastCharMap = [Int32](repeating: 0, count: 65536)
        
        var code: Int32 = 1
        let sortedScalars = uniqueScalars.sorted()
        for scalar in sortedScalars {
            let c = code
            code += 1
            charMap[scalar] = c
            
            let charCodeValue = scalar.value
            if charCodeValue < 65536 {
                fastCharMap[Int(charCodeValue)] = c
            }
        }
        maxCharValue = Int(code)
    }
    
    private func calculateInitialSize(keys: [String]) -> Int {
        let totalChars = keys.reduce(0) { $0 + $1.count }
        return Int(Double(totalChars) * 1.8) + keys.count + 2048
    }
    
    private struct Node {
        let code: Int32
        let depth: Int
        let left: Int
        let right: Int
    }
    
    private func fetch(parent: Node, keys: [String]) -> [Node] {
        var siblings: [Node] = []
        var prevCode: Int32 = -1
        
        var i = parent.left
        while i < parent.right {
            let key = keys[i]
            let code: Int32
            if parent.depth < key.count {
                let charIndex = key.index(key.startIndex, offsetBy: parent.depth)
                let char = key[charIndex]
                code = charMap[char] ?? 0
            } else {
                code = 0
            }
            
            if code != prevCode {
                siblings.append(Node(code: code, depth: parent.depth + 1, left: i, right: i + 1))
                prevCode = code
            } else {
                if !siblings.isEmpty {
                    let lastIdx = siblings.count - 1
                    let last = siblings[lastIdx]
                    siblings[lastIdx] = Node(code: last.code, depth: last.depth, left: last.left, right: i + 1)
                }
            }
            i += 1
        }
        return siblings
    }
    
    private func insertWithOffsets(siblings: [Node], parentIndex: Int, keys: [String], stringOffsets: [Int]) {
        if siblings.isEmpty { return }
        var begin = 0
        var pos = max(nextCheckPos, Int(siblings[0].code) + 1) - 1
        
        while true {
            pos += 1
            ensureCapacity(minSize: pos + 1)
            if check[pos] != -1 { continue }
            begin = pos - Int(siblings[0].code)
            if begin <= 0 { continue }
            
            if used.count <= begin {
                ensureCapacity(minSize: begin + Int(siblings.last!.code) + 1)
            }
            if begin + Int(siblings.last!.code) >= check.count {
                ensureCapacity(minSize: begin + Int(siblings.last!.code) + 1)
            }
            if used[begin] { continue }
            
            var conflict = false
            for s in siblings {
                let idx = begin + Int(s.code)
                if idx >= check.count {
                    ensureCapacity(minSize: idx + 1)
                }
                if check[idx] != -1 {
                    conflict = true
                    break
                }
            }
            if !conflict { break }
        }
        
        used[begin] = true
        base[parentIndex] = Int32(begin)
        if pos + 1 > nextCheckPos {
            nextCheckPos = pos
        }
        
        for s in siblings {
            check[begin + Int(s.code)] = Int32(parentIndex)
        }
        
        for s in siblings {
            let idx = begin + Int(s.code)
            if s.code == 0 {
                base[idx] = Int32(stringOffsets[s.left])
                continue
            }
            
            let newSiblings = fetch(parent: s, keys: keys)
            if newSiblings.isEmpty { continue }
            insertWithOffsets(siblings: newSiblings, parentIndex: idx, keys: keys, stringOffsets: stringOffsets)
        }
    }
    
    private func ensureCapacity(minSize: Int) {
        if minSize <= base.count { return }
        var newSize = base.count
        while newSize < minSize {
            newSize *= 2
            if newSize <= 0 {
                newSize = minSize
                break
            }
        }
        
        let oldSize = base.count
        
        var newBase = [Int32](repeating: 0, count: newSize)
        newBase.replaceSubrange(0..<oldSize, with: base)
        base = newBase
        
        var newCheck = [Int32](repeating: -1, count: newSize)
        newCheck.replaceSubrange(0..<oldSize, with: check)
        check = newCheck
        
        var newUsed = [Bool](repeating: false, count: newSize)
        newUsed.replaceSubrange(0..<oldSize, with: used)
        used = newUsed
    }
    
    private func compactArrays() {
        var maxUsed = 0
        for i in (0..<check.count).reversed() {
            if check[i] != -1 {
                maxUsed = i
                break
            }
        }
        
        if maxUsed < base.count - 1 {
            let compactSize = maxUsed + 1
            base = Array(base[0..<compactSize])
            check = Array(check[0..<compactSize])
            used = Array(used[0..<compactSize])
        }
    }
}

// MARK: - Extension Helper đọc Big Endian
extension Data {
    fileprivate func readBigEndianInt32(at offset: Int) -> Int32 {
        let val = self.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Int32.self) }
        return Int32(bigEndian: val)
    }
}
