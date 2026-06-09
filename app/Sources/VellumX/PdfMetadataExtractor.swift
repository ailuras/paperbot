import Foundation
import PDFKit

/// Utility class for extracting academic paper metadata from PDF files using pure-local heuristics and system PDFKit APIs.
struct PdfMetadataExtractor {
    
    struct ExtractedData {
        var doi: String?
        var title: String?
        var authors: [String] = []
        var abstract: String?
        var year: Int?
    }
    
    /// Extract metadata from PDF data in memory.
    static func extract(from pdfData: Data) -> ExtractedData {
        guard let document = PDFDocument(data: pdfData) else { return ExtractedData() }
        var data = ExtractedData()
        
        // 1. Extract plain text from the first 3 pages
        var pageTexts: [String] = []
        for i in 0..<min(document.pageCount, 3) {
            if let pageText = document.page(at: i)?.string {
                pageTexts.append(pageText)
            }
        }
        let fullText = pageTexts.joined(separator: "\n")
        
        // 2. Identify DOI or arXiv ID
        if let doi = matchDOI(in: fullText) {
            data.doi = doi
        } else if let arxivId = matchArXiv(in: fullText) {
            // Map arXiv:YYMM.NNNNN to arXiv DOI prefix: 10.48550/arXiv.YYMM.NNNNN
            data.doi = "10.48550/arXiv.\(arxivId)"
        }
        
        // 3. Extract Title using typography size heuristics from page 0
        if let firstPage = document.page(at: 0) {
            data.title = extractTitle(from: firstPage)
        }
        
        // 4. Extract Abstract
        data.abstract = extractAbstract(from: fullText)
        
        // 5. Extract Authors using text between Title and Abstract
        if let title = data.title, let firstPage = document.page(at: 0), let pageText = firstPage.string {
            data.authors = extractAuthors(pageText: pageText, title: title, abstractText: fullText)
        }
        
        // 6. Extract Year
        data.year = extractYear(from: fullText)
        
        return data
    }
    
    // MARK: - RegEx Identifier Extraction
    
    /// Finds standard DOI format (10.xxxx/xxxx) and cleans common suffixes.
    static func matchDOI(in text: String) -> String? {
        let pattern = #"\b10\.\d{4,9}/[a-zA-Z0-9\-\.\_\;\(\)\/\:\+\=\<\>\~\@\?\&\%]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        var matched = String(text[Range(match.range, in: text)!])
        
        // Clean trailing punctuation
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}> ")
        while let last = matched.last, String(last).rangeOfCharacter(from: trailingPunctuation) != nil {
            matched.removeLast()
        }
        
        return matched.isEmpty ? nil : matched
    }
    
    /// Finds arXiv identifiers (e.g. arXiv:1706.03762 or YYMM.NNNNN).
    static func matchArXiv(in text: String) -> String? {
        // Clean and validate helper
        func cleanAndValidate(_ rawId: String) -> String? {
            var id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            if let vRange = id.range(of: "v\\d+$", options: .regularExpression) {
                id.removeSubrange(vRange)
            }
            guard id.count >= 4 else { return nil }
            let year = Int(id.prefix(2)) ?? 0
            let month = Int(id.dropFirst(2).prefix(2)) ?? 0
            if (year >= 91 || year <= 29) && (month >= 1 && month <= 12) {
                return id
            }
            return nil
        }
        
        // Pattern 1: explicitly starting with arXiv:YYMM.NNNNN
        let explicitPattern = #"(?i)\barXiv:\s*(\d{4}\.\d{4,5}(v\d+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: explicitPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            let nsMatched = text as NSString
            let range = match.range(at: 1)
            if range.location != NSNotFound {
                let candidate = nsMatched.substring(with: range)
                if let validated = cleanAndValidate(candidate) {
                    return validated
                }
            }
        }
        
        // Pattern 2: bare arXiv ID in format YYMM.NNNN(N)
        let barePattern = #"\b(\d{4}\.\d{4,5})\b"#
        if let regex = try? NSRegularExpression(pattern: barePattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let candidate = (text as NSString).substring(with: range)
                    if let validated = cleanAndValidate(candidate) {
                        return validated
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Title Heuristics
    
    /// Finds the largest font blocks in the first page to reconstruct the title.
    static func extractTitle(from page: PDFPage) -> String? {
        guard let attrString = page.attributedString else {
            return fallbackTitle(from: page.string)
        }
        
        struct TextBlock {
            let text: String
            let size: CGFloat
        }
        
        var blocks: [TextBlock] = []
        
        attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, _ in
            let text = attrString.attributedSubstring(from: range).string
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            var fontSize: CGFloat = 10
            if let font = value as? NSFont {
                fontSize = font.pointSize
            }
            blocks.append(TextBlock(text: text, size: fontSize))
        }
        
        // Filter out blocks likely to be header markers (e.g. page numbers, small margins)
        // Title font size in academic papers is almost always >= 13pt
        let titleCandidates = blocks.filter { $0.size >= 13.0 }
        
        if !titleCandidates.isEmpty {
            // Find the maximum font size among candidates
            let maxSize = titleCandidates.map(\.size).max() ?? 13.0
            
            // Collect all continuous chunks of this max size
            // Note: sometimes there are minor font size variations or tiny non-max characters (like superscript footnote indicators)
            // inside a title. We'll grab any candidate that is within 1pt of the max size.
            let titleChunks = titleCandidates.filter { abs($0.size - maxSize) <= 1.0 }
            
            let combined = titleChunks.map(\.text).joined(separator: "")
            let cleaned = cleanString(combined)
            if cleaned.count >= 5 {
                return cleaned
            }
        }
        
        return fallbackTitle(from: page.string)
    }
    
    private static func fallbackTitle(from pageText: String?) -> String? {
        guard let text = pageText else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Skip first 1-2 short header lines if they look like journal headers (e.g. "Preprint", "arXiv:...")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.lowercased().contains("journal") ||
                line.lowercased().contains("arxiv") ||
                line.lowercased().contains("preprint") ||
                line.count < 6 {
                index += 1
            } else {
                break
            }
        }
        
        if index < lines.count {
            // Join first two meaningful lines as fallback title
            var candidate = lines[index]
            if index + 1 < lines.count && lines[index+1].count > 10 && !lines[index+1].contains("@") {
                candidate += " " + lines[index+1]
            }
            return cleanString(candidate)
        }
        return nil
    }
    
    // MARK: - Abstract Heuristics
    
    static func extractAbstract(from text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        
        // Find abstract boundary keywords
        let abstractKeywords = ["abstract", "a b s t r a c t", "摘要"]
        var abstractStartIndex: String.Index?
        
        for keyword in abstractKeywords {
            if let range = normalized.range(of: keyword, options: [.caseInsensitive]) {
                abstractStartIndex = range.upperBound
                break
            }
        }
        
        guard let startIdx = abstractStartIndex else { return nil }
        
        var abstractContent = String(normalized[startIdx...])
        
        // Clean leading symbols (e.g. ".", ":", "—", spaces, linebreaks)
        let leadingExclusions = CharacterSet(charactersIn: ".:—-\r\n\t ")
        while let first = abstractContent.first, String(first).rangeOfCharacter(from: leadingExclusions) != nil {
            abstractContent.removeFirst()
        }
        
        // Locate end boundary of the abstract (typically the start of "1 Introduction" or similar sections)
        let introKeywords = [
            "\n1 introduction", "\n1. introduction", "\ni. introduction",
            "\n1.  introduction", "\nintroduction", "\n1  introduction",
            "\n1. background", "\n1 background", "\nbackground"
        ]
        
        var abstractEndIndex = abstractContent.endIndex
        
        for keyword in introKeywords {
            if let range = abstractContent.range(of: keyword, options: [.caseInsensitive]) {
                if range.lowerBound < abstractEndIndex {
                    abstractEndIndex = range.lowerBound
                }
            }
        }
        
        // If we found a boundary, slice it. Otherwise clamp it to a maximum of 1800 characters to avoid grabbing the whole paper
        let sliced = String(abstractContent[..<abstractEndIndex])
        let cleaned = cleanString(sliced)
        
        if cleaned.count > 1800 {
            return String(cleaned.prefix(1500)) + "..."
        }
        return cleaned.isEmpty ? nil : cleaned
    }
    
    // MARK: - Authors Heuristics
    
    static func extractAuthors(pageText: String, title: String, abstractText: String) -> [String] {
        let normalizedPage = pageText.replacingOccurrences(of: "\r", with: "\n")
        
        // Find Abstract boundary
        let abstractKeywords = ["abstract", "摘要"]
        var abstractIndex: String.Index?
        for kw in abstractKeywords {
            if let range = normalizedPage.range(of: kw, options: [.caseInsensitive]) {
                abstractIndex = range.lowerBound
                break
            }
        }
        
        // Take everything before abstract, or fallback to first 12 lines
        let candidateText: String
        if let idx = abstractIndex {
            candidateText = String(normalizedPage[..<idx])
        } else {
            let lines = normalizedPage.components(separatedBy: .newlines)
            candidateText = lines.prefix(12).joined(separator: "\n")
        }
        
        let lines = candidateText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        // Filter lines
        var filteredLines: [String] = []
        let titleLower = title.lowercased().replacingOccurrences(of: " ", with: "")
        
        let exclusions = [
            "university", "institute", "dept", "department", "school", "laboratory",
            "lab", "center", "centre", "corporation", "inc.", "co.", "ltd", "email",
            "@", "abstract", "http", "www", "research", "technology", "sciences",
            "china", "usa", "state", "national", "association", "society"
        ]
        
        for line in lines {
            let lineLower = line.lowercased()
            let lineNoSpace = lineLower.replacingOccurrences(of: " ", with: "")
            
            // 1. Skip if this line is part of the title
            if titleLower.contains(lineNoSpace) || lineNoSpace.contains(titleLower) && lineNoSpace.count > 4 {
                continue
            }
            
            // 2. Skip if it contains institutional keyword
            var isExcluded = false
            for exclusion in exclusions {
                if lineLower.contains(exclusion) {
                    isExcluded = true
                    break
                }
            }
            if isExcluded { continue }
            
            // 3. Skip if it looks like a header, page number or preprint tag (e.g. "Preprint", "arXiv:")
            if lineLower.contains("preprint") || lineLower.contains("arxiv") || line.count < 3 {
                continue
            }
            
            // 4. Skip if it contains too many numbers (zip codes or phones)
            let digits = line.filter { $0.isNumber }.count
            if digits > 4 {
                continue
            }
            
            filteredLines.append(line)
        }
        
        // The first 1-2 lines remaining in filteredLines are most likely the author line
        guard !filteredLines.isEmpty else { return [] }
        
        var authorLine = filteredLines[0]
        // If the first line is short and there's a second line without institutional elements, join them
        if filteredLines.count > 1 && filteredLines[0].count < 20 && !filteredLines[1].contains(",") {
            authorLine += ", " + filteredLines[1]
        }
        
        // Clean out superscript indicators (*, 1, 2, †, ‡ etc.)
        let cleanAuthorLine = authorLine.replacingOccurrences(of: "[0-9*†‡§\\\\#]", with: "", options: .regularExpression)
        
        // Split by commas, "and", "&", ";"
        let separators = [" and ", " & ", ",", ";"]
        var parsedAuthors: [String] = [cleanAuthorLine]
        
        for sep in separators {
            var temp: [String] = []
            for item in parsedAuthors {
                let parts = item.components(separatedBy: sep)
                temp.append(contentsOf: parts)
            }
            parsedAuthors = temp
        }
        return parsedAuthors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !$0.lowercased().contains("and") }
    }
    
    // MARK: - Year Heuristics
    
    static func extractYear(from text: String) -> Int? {
        // Find 4 digit numbers representing years between 1990 and 2029
        let pattern = #"\b(19\d{2}|20[0-2]\d)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        // Often the first matching year in header/footer represents the publication year.
        // We evaluate candidates and prefer ones that appear early or are surrounded by parentheses (2021) or next to "received" / "published"
        var candidates: [Int] = []
        for match in matches {
            let range = match.range
            if range.location != NSNotFound {
                let candidateStr = (text as NSString).substring(with: range)
                if let val = Int(candidateStr) {
                    candidates.append(val)
                }
            }
        }
        
        // First, check if there's any year next to "journal" or inside parentheses (e.g. "(2020)")
        let parenPattern = #"\((19\d{2}|20[0-2]\d)\)"#
        if let parenRegex = try? NSRegularExpression(pattern: parenPattern, options: []),
           let firstMatch = parenRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            let nsMatched = text as NSString
            let range = firstMatch.range(at: 1)
            if range.location != NSNotFound {
                if let val = Int(nsMatched.substring(with: range)) {
                    return val
                }
            }
        }
        
        // Fallback to the first found candidate year
        return candidates.first
    }
    
    // MARK: - Helper Cleaners
    
    private static func cleanString(_ input: String) -> String {
        // Replace multiple whitespace/linebreaks with a single space
        let spaced = input.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
