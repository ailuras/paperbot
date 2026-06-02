import Foundation

/// Pure, dependency-free citation string builders. No UI / SQLite / network —
/// fully unit-testable. Reads only from the in-memory `Paper` DTO.
enum CitationExporter {

    // MARK: - Cite key

    /// `<firstAuthorSurname><year><firstTitleWord>`, lowercased and stripped to
    /// ASCII alphanumerics. Degrades gracefully: no author → `anon`, no year is
    /// simply omitted, no usable title word is omitted.
    static func citeKey(for paper: Paper) -> String {
        let surname = paper.authors.first.flatMap { surnameToken(from: $0) } ?? "anon"
        let year = paper.publicationYear.map(String.init) ?? ""
        let titleWord = firstWord(of: paper.title)
        let key = surname + year + titleWord
        let cleaned = asciiAlnum(key)
        return cleaned.isEmpty ? "ref" : cleaned
    }

    // MARK: - BibTeX

    static func bibtex(for paper: Paper) -> String {
        var fields: [(String, String)] = []

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            // Double braces preserve the original capitalization in most styles.
            fields.append(("title", "{\(escapeBibtex(title))}"))
        }
        if !paper.authors.isEmpty {
            let authors = paper.authors
                .map { escapeBibtex($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .joined(separator: " and ")
            fields.append(("author", authors))
        }
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            fields.append(("journal", escapeBibtex(venue)))
        }
        if let year = paper.publicationYear {
            fields.append(("year", String(year)))
        }
        if let doi = bareDoi(paper.doi) {
            fields.append(("doi", escapeBibtex(doi)))
        }
        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !landing.isEmpty {
            fields.append(("url", escapeBibtex(landing)))
        }

        let body = fields
            .map { "  \($0.0) = {\($0.1)}" }
            .joined(separator: ",\n")

        return "@article{\(citeKey(for: paper)),\n\(body)\n}"
    }

    // MARK: - RIS

    static func ris(for paper: Paper) -> String {
        var lines: [String] = ["TY  - JOUR"]

        for author in paper.authors {
            let a = author.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty { lines.append("AU  - \(a)") }
        }
        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { lines.append("TI  - \(title)") }

        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty { lines.append("JO  - \(venue)") }

        if let year = paper.publicationYear { lines.append("PY  - \(year)") }
        if let doi = bareDoi(paper.doi) { lines.append("DO  - \(doi)") }

        let landing = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !landing.isEmpty { lines.append("UR  - \(landing)") }

        lines.append("ER  - ")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// BibTeX special characters that must be escaped with a backslash.
    private static func escapeBibtex(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "{", "}", "&", "%", "$", "#", "_":
                out.append("\\"); out.append(ch)
            case "~":
                out.append("\\textasciitilde{}")
            case "^":
                out.append("\\textasciicircum{}")
            case "\\":
                out.append("\\textbackslash{}")
            default:
                out.append(ch)
            }
        }
        return out
    }

    /// Strips the `https://doi.org/` style prefix so the exported DOI is bare.
    private static func bareDoi(_ doi: String?) -> String? {
        guard let doi = doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty else {
            return nil
        }
        return PdfResolver.stripDoiPrefix(doi)
    }

    /// Last whitespace-separated token of an author string ("Jane Q. Doe" → "Doe").
    private static func surnameToken(from author: String) -> String? {
        let parts = author.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return parts.last.map(String.init)
    }

    /// First word of the title that contains a letter or digit.
    private static func firstWord(of title: String) -> String {
        for token in title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            return String(token)
        }
        return ""
    }

    private static func asciiAlnum(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
        }.map(Character.init))
    }
}
