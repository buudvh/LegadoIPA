import Foundation

/// Bộ phân tích và chia tách quy tắc cào truyện (tách biệt @, &&, ||...) mà không làm vỡ các biểu thức ngoặc
public final class RuleAnalyzer {
    
    private var queue: String
    private var pos = 0
    private var start = 0
    private var startX = 0
    private var rule: [String] = []
    private var step = 0
    private var elementsType = ""
    private let code: Bool
    
    private static let ESC: Character = "\\"
    
    public init(data: String, code: Bool = false) {
        self.queue = data
        self.code = code
    }
    
    private func chompBalanced(open: Character, close: Character) -> Bool {
        return code ? chompCodeBalanced(open: open, close: close) : chompRuleBalanced(open: open, close: close)
    }
    
    private func trim() {
        let chars = Array(queue)
        if pos < chars.count && (chars[pos] == "@" || chars[pos].isWhitespace) {
            pos += 1
            while pos < chars.count && (chars[pos] == "@" || chars[pos].isWhitespace) {
                pos += 1
            }
            start = pos
            startX = pos
        }
    }
    
    private func consumeTo(_ seq: String) -> Bool {
        start = pos
        let suffix = queue.suffix(queue.count - pos)
        if let range = suffix.range(of: seq) {
            let offset = queue.distance(from: queue.startIndex, to: range.lowerBound)
            pos = offset
            return true
        }
        return false
    }
    
    private func consumeToAny(_ seqs: [String]) -> Bool {
        let chars = Array(queue)
        var tempPos = pos
        while tempPos < chars.count {
            for seq in seqs {
                let seqChars = Array(seq)
                if tempPos + seqChars.count <= chars.count {
                    let sub = chars[tempPos..<(tempPos + seqChars.count)]
                    if sub == seqChars {
                        step = seqChars.count
                        self.pos = tempPos
                        return true
                    }
                }
            }
            tempPos += 1
        }
        return false
    }
    
    private func findToAny(_ seqs: [Character]) -> Int {
        let chars = Array(queue)
        var tempPos = pos
        while tempPos < chars.count {
            if seqs.contains(chars[tempPos]) {
                return tempPos
            }
            tempPos += 1
        }
        return -1
    }
    
    private func chompCodeBalanced(_ open: Character, _ close: Character) -> Bool {
        let chars = Array(queue)
        var tempPos = pos
        
        var depth = 0
        var otherDepth = 0
        
        var inSingleQuote = false
        var inDoubleQuote = false
        
        repeat {
            if tempPos >= chars.count { break }
            let c = chars[tempPos]
            tempPos += 1
            
            if c != RuleAnalyzer.ESC {
                if c == "'" && !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if c == "\"" && !inSingleQuote {
                    inDoubleQuote.toggle()
                }
                
                if inSingleQuote || inDoubleQuote { continue }
                
                if c == "[" {
                    depth += 1
                } else if c == "]" {
                    depth -= 1
                } else if depth == 0 {
                    if c == open {
                        otherDepth += 1
                    } else if c == close {
                        otherDepth -= 1
                    }
                }
            } else {
                if tempPos < chars.count {
                    tempPos += 1
                }
            }
        } while depth > 0 || otherDepth > 0
        
        if depth > 0 || otherDepth > 0 {
            return false
        } else {
            self.pos = tempPos
            return true
        }
    }
    
    private func chompRuleBalanced(_ open: Character, _ close: Character) -> Bool {
        let chars = Array(queue)
        var tempPos = pos
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        
        repeat {
            if tempPos >= chars.count { break }
            let c = chars[tempPos]
            tempPos += 1
            
            if c == "\\" {
                if tempPos < chars.count {
                    tempPos += 1
                }
                continue
            }
            
            if c == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if c == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            }
            
            if inSingleQuote || inDoubleQuote {
                continue
            }
            
            if c == open {
                depth += 1
            } else if c == close {
                depth -= 1
            }
        } while depth > 0
        
        if depth > 0 {
            return false
        } else {
            self.pos = tempPos
            return true
        }
    }
    
    /// Chia tách rule bằng mảng các ký tự phân cách (VD: @, &&, ||...)
    public func splitRule(_ split: String...) -> [String] {
        self.rule = []
        self.pos = 0
        self.startX = 0
        
        if split.count == 1 {
            elementsType = split[0]
            if !consumeTo(elementsType) {
                let startIdx = queue.index(queue.startIndex, offsetBy: startX)
                rule.append(String(queue[startIdx...]))
                return rule
            } else {
                step = elementsType.count
                return splitRuleNext()
            }
        }
        
        return splitRuleFirstStage(split)
    }
    
    private func splitRuleFirstStage(_ split: [String]) -> [String] {
        if !consumeToAny(split) {
            let startIdx = queue.index(queue.startIndex, offsetBy: startX)
            rule.append(String(queue[startIdx...]))
            return rule
        }
        
        let end = pos
        pos = start
        
        while true {
            let st = findToAny(["[", "("])
            if st == -1 {
                let startIdx = queue.index(queue.startIndex, offsetBy: startX)
                let endIdx = queue.index(queue.startIndex, offsetBy: end)
                rule = [String(queue[startIdx..<endIdx])]
                
                let elStartIdx = queue.index(queue.startIndex, offsetBy: end)
                let elEndIdx = queue.index(elStartIdx, offsetBy: step)
                elementsType = String(queue[elStartIdx..<elEndIdx])
                
                pos = end + step
                while consumeTo(elementsType) {
                    let sIdx = queue.index(queue.startIndex, offsetBy: start)
                    let pIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[sIdx..<pIdx]))
                    pos += step
                }
                
                let remIdx = queue.index(queue.startIndex, offsetBy: pos)
                rule.append(String(queue[remIdx...]))
                return rule
            }
            
            if st > end {
                let startIdx = queue.index(queue.startIndex, offsetBy: startX)
                let endIdx = queue.index(queue.startIndex, offsetBy: end)
                rule = [String(queue[startIdx..<endIdx])]
                
                let elStartIdx = queue.index(queue.startIndex, offsetBy: end)
                let elEndIdx = queue.index(elStartIdx, offsetBy: step)
                elementsType = String(queue[elStartIdx..<elEndIdx])
                
                pos = end + step
                while consumeTo(elementsType) && pos < st {
                    let sIdx = queue.index(queue.startIndex, offsetBy: start)
                    let pIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[sIdx..<pIdx]))
                    pos += step
                }
                
                if pos > st {
                    startX = start
                    return splitRuleNext()
                } else {
                    let remIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[remIdx...]))
                    return rule
                }
            }
            
            pos = st
            let chars = Array(queue)
            let nextChar: Character = chars[pos] == "[" ? "]" : ")"
            _ = chompBalanced(open: chars[pos], close: nextChar)
            
            if end <= pos {
                break
            }
        }
        
        start = pos
        return splitRuleFirstStage(split)
    }
    
    private func splitRuleNext() -> [String] {
        let end = pos
        pos = start
        
        while true {
            let st = findToAny(["[", "("])
            if st == -1 {
                let startIdx = queue.index(queue.startIndex, offsetBy: startX)
                let endIdx = queue.index(queue.startIndex, offsetBy: end)
                rule.append(String(queue[startIdx..<endIdx]))
                
                pos = end + step
                while consumeTo(elementsType) {
                    let sIdx = queue.index(queue.startIndex, offsetBy: start)
                    let pIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[sIdx..<pIdx]))
                    pos += step
                }
                
                let remIdx = queue.index(queue.startIndex, offsetBy: pos)
                rule.append(String(queue[remIdx...]))
                return rule
            }
            
            if st > end {
                let startIdx = queue.index(queue.startIndex, offsetBy: startX)
                let endIdx = queue.index(queue.startIndex, offsetBy: end)
                rule.append(String(queue[startIdx..<endIdx]))
                
                pos = end + step
                while consumeTo(elementsType) && pos < st {
                    let sIdx = queue.index(queue.startIndex, offsetBy: start)
                    let pIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[sIdx..<pIdx]))
                    pos += step
                }
                
                if pos > st {
                    startX = start
                    return splitRuleNext()
                } else {
                    let remIdx = queue.index(queue.startIndex, offsetBy: pos)
                    rule.append(String(queue[remIdx...]))
                    return rule
                }
            }
            
            pos = st
            let chars = Array(queue)
            let nextChar: Character = chars[pos] == "[" ? "]" : ")"
            _ = chompBalanced(open: chars[pos], close: nextChar)
            
            if end <= pos {
                break
            }
        }
        
        start = pos
        if !consumeTo(elementsType) {
            let startIdx = queue.index(queue.startIndex, offsetBy: startX)
            rule.append(String(queue[startIdx...]))
            return rule
        }
        return splitRuleNext()
    }
    
    /// Hỗ trợ parse và thay thế nội dung các quy tắc chèn dạng {...}
    public func innerRule(inner: String, startStep: Int = 1, endStep: Int = 1, fr: (String) -> String?) -> String {
        var st = ""
        while consumeTo(inner) {
            let posPre = pos
            if chompCodeBalanced("{", "}") {
                let startIdx = queue.index(queue.startIndex, offsetBy: posPre + startStep)
                let endIdx = queue.index(queue.startIndex, offsetBy: pos - endStep)
                let subStr = String(queue[startIdx..<endIdx])
                
                if let frv = fr(subStr), !frv.isEmpty {
                    let startXIdx = queue.index(queue.startIndex, offsetBy: startX)
                    let posPreIdx = queue.index(queue.startIndex, offsetBy: posPre)
                    st += String(queue[startXIdx..<posPreIdx]) + frv
                    startX = pos
                    continue
                }
            }
            pos += inner.count
        }
        
        if startX == 0 {
            return ""
        } else {
            let startXIdx = queue.index(queue.startIndex, offsetBy: startX)
            return st + String(queue[startXIdx...])
        }
    }
    
    /// Hỗ trợ thay thế quy tắc chèn dạng startStr...endStr
    public func innerRule(startStr: String, endStr: String, fr: (String) -> String?) -> String {
        var st = ""
        while consumeTo(startStr) {
            let startMatchPos = pos
            pos += startStr.count
            let posPre = pos
            if consumeTo(endStr) {
                let posPreIdx = queue.index(queue.startIndex, offsetBy: posPre)
                let posIdx = queue.index(queue.startIndex, offsetBy: pos)
                let subStr = String(queue[posPreIdx..<posIdx])
                let frv = fr(subStr) ?? ""
                
                let startXIdx = queue.index(queue.startIndex, offsetBy: startX)
                let startMatchIdx = queue.index(queue.startIndex, offsetBy: startMatchPos)
                st += String(queue[startXIdx..<startMatchIdx]) + frv
                
                pos += endStr.count
                startX = pos
            }
        }
        
        if startX == 0 {
            return queue
        } else {
            let startXIdx = queue.index(queue.startIndex, offsetBy: startX)
            return st + String(queue[startXIdx...])
        }
    }
}
