import SQLite3
import XCTest
@testable import VellumX

@MainActor
final class PaperStoreCollectionsTests: XCTestCase {
    func testCreateCollectionTrimsNameAndBuildsSubtree() throws {
        let store = PaperStore(databaseURL: try temporaryDatabaseURL())

        let parent = try XCTUnwrap(store.createCollection(name: "  Parent  ", color: "blue", icon: "book"))
        let child = try XCTUnwrap(store.createCollection(name: "  Child  ", parentId: parent.id))

        XCTAssertEqual(parent.name, "Parent")
        XCTAssertEqual(child.name, "Child")
        XCTAssertEqual(store.collectionSubtreeIds(parent.id), Set([parent.id, child.id]))
        XCTAssertNil(store.createCollection(name: "   "))
    }

    func testDeleteCollectionRemovesWholeSubtreeMembershipOnly() throws {
        let store = PaperStore(databaseURL: try temporaryDatabaseURL())
        _ = store.addOrUpdate(papers: [makePaper(id: "p1", title: "Paper One")])

        let parent = try XCTUnwrap(store.createCollection(name: "Parent"))
        let child = try XCTUnwrap(store.createCollection(name: "Child", parentId: parent.id))
        let sibling = try XCTUnwrap(store.createCollection(name: "Sibling"))

        store.addPaperToCollection(paperId: "p1", collectionId: child.id)
        store.addPaperToCollection(paperId: "p1", collectionId: sibling.id)
        store.deleteCollection(id: parent.id)

        XCTAssertFalse(store.allCollections.contains { $0.id == parent.id || $0.id == child.id })
        XCTAssertTrue(store.allCollections.contains { $0.id == sibling.id })
        XCTAssertEqual(store.papers.first?.collectionIds, [sibling.id])
    }

    func testLegacyCollectionsSchemaMigratesWithoutNameUniqueConstraint() throws {
        let dbURL = try temporaryDatabaseURL()
        try createLegacyCollectionsDatabase(at: dbURL)

        let store = PaperStore(databaseURL: dbURL)
        XCTAssertEqual(store.allCollections.first?.name, "Root")

        let duplicate = try XCTUnwrap(store.createCollection(name: "Root"))
        XCTAssertEqual(duplicate.name, "Root")
        XCTAssertEqual(store.allCollections.filter { $0.name == "Root" }.count, 2)
    }

    private func temporaryDatabaseURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VellumXTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir.appendingPathComponent("vellumx.db")
    }

    private func createLegacyCollectionsDatabase(at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        INSERT INTO collections (id, name, color) VALUES ('root', 'Root', NULL);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
