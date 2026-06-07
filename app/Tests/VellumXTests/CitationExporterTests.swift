import XCTest
@testable import VellumX

final class CitationExporterTests: XCTestCase {

    private func makePaper(
        title: String = "Attention Is All You Need",
        authors: [String] = ["Ashish Vaswani", "Noam Shazeer"],
        year: Int? = 2017,
        venue: String = "NeurIPS",
        doi: String? = "https://doi.org/10.5555/3295222",
        landing: String = "https://example.org/paper"
    ) -> Paper {
        Paper(
            id: "W1", doi: doi, title: title, authors: authors,
            publicationYear: year, venue: venue, landingPageUrl: landing
        )
    }

    // MARK: - citeKey

    func testCiteKeyNormalCase() {
        XCTAssertEqual(CitationExporter.citeKey(for: makePaper()), "vaswani2017attention")
    }

    func testCiteKeyMissingAuthor() {
        let key = CitationExporter.citeKey(for: makePaper(authors: []))
        XCTAssertEqual(key, "anon2017attention")
    }

    func testCiteKeyMissingYear() {
        let key = CitationExporter.citeKey(for: makePaper(year: nil))
        XCTAssertEqual(key, "vaswaniattention")
    }

    func testCiteKeyStripsPunctuationAndUnicode() {
        let key = CitationExporter.citeKey(
            for: makePaper(title: "Café: Déjà-vu!", authors: ["Émile Zölá"], year: 2020)
        )
        // Non-ASCII letters are stripped; only ascii alnum remains.
        XCTAssertEqual(key, "zl2020caf")
    }

    func testCiteKeyFallsBackToRefWhenNothingASCII() {
        // Author present but non-ASCII, no year, no ASCII title word → empty → "ref".
        let key = CitationExporter.citeKey(for: makePaper(title: "！？", authors: ["你好"], year: nil))
        XCTAssertEqual(key, "ref")
    }

    // MARK: - BibTeX

    func testBibtexContainsCoreFields() {
        let bib = CitationExporter.bibtex(for: makePaper())
        XCTAssertTrue(bib.hasPrefix("@article{vaswani2017attention,"))
        XCTAssertTrue(bib.contains("author = {Ashish Vaswani and Noam Shazeer}"))
        XCTAssertTrue(bib.contains("journal = {NeurIPS}"))
        XCTAssertTrue(bib.contains("year = {2017}"))
        // DOI is exported bare (prefix stripped).
        XCTAssertTrue(bib.contains("doi = {10.5555/3295222}"))
        XCTAssertTrue(bib.contains("url = {https://example.org/paper}"))
        XCTAssertTrue(bib.hasSuffix("}"))
    }

    func testBibtexEscapesSpecialCharacters() {
        let bib = CitationExporter.bibtex(
            for: makePaper(title: "Cost & Benefit of 50% _gains_ #1", doi: nil)
        )
        XCTAssertTrue(bib.contains("Cost \\& Benefit of 50\\% \\_gains\\_ \\#1"))
    }

    func testBibtexOmitsMissingFields() {
        let bib = CitationExporter.bibtex(
            for: makePaper(authors: [], venue: "", doi: nil, landing: "")
        )
        XCTAssertFalse(bib.contains("author ="))
        XCTAssertFalse(bib.contains("journal ="))
        XCTAssertFalse(bib.contains("doi ="))
        XCTAssertFalse(bib.contains("url ="))
        XCTAssertTrue(bib.contains("title ="))
        XCTAssertTrue(bib.contains("year ="))
    }

    // MARK: - APA

    func testApaTwoAuthors() {
        let s = CitationExporter.apa(for: makePaper())
        XCTAssertEqual(
            s,
            "Vaswani, A., & Shazeer, N. (2017). Attention Is All You Need. NeurIPS. https://doi.org/10.5555/3295222"
        )
    }

    func testApaSingleAuthorFallbackToLandingUrl() {
        let s = CitationExporter.apa(for: makePaper(
            authors: ["Jane Doe"], doi: nil, landing: "https://example.org/paper"
        ))
        XCTAssertEqual(
            s,
            "Doe, J. (2017). Attention Is All You Need. NeurIPS. https://example.org/paper"
        )
    }

    func testApaSingleNameAuthorPreserved() {
        let s = CitationExporter.apa(for: makePaper(authors: ["Plato"]))
        XCTAssertTrue(s.hasPrefix("Plato. (2017)."))
    }

    func testApaNoYearUsesNd() {
        let s = CitationExporter.apa(for: makePaper(year: nil))
        XCTAssertTrue(s.contains("(n.d.)."))
    }

    func testApaCollapsesLongAuthorList() {
        let many = (1...25).map { "Author\($0) Surname\($0)" }
        let s = CitationExporter.apa(for: makePaper(authors: many))
        XCTAssertTrue(s.contains("Surname1, A."))
        XCTAssertTrue(s.contains("Surname19, A."))
        XCTAssertTrue(s.contains("… Surname25, A."))
        XCTAssertFalse(s.contains("Surname20, A."))
    }

    func testApaHyphenatedInitials() {
        let s = CitationExporter.apa(for: makePaper(authors: ["Jean-Luc Picard"]))
        XCTAssertTrue(s.hasPrefix("Picard, J.-L."))
    }
}
