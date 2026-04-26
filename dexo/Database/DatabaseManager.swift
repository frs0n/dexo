import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    private let dbPool: DatabasePool

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport.appendingPathComponent("dexo.sqlite")
            dbPool = try DatabasePool(path: dbURL.path)
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "forumInstance") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("iconURL", .text)
                t.column("apiKey", .text)
                t.column("apiUsername", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "forumInstance") { t in
                t.add(column: "username", .text)
            }
        }

        return migrator
    }

    // MARK: - Forum CRUD

    func fetchAllForums() throws -> [ForumInstance] {
        try dbPool.read { db in
            try ForumInstance.order(Column("sortOrder").asc, Column("addedAt").asc).fetchAll(db)
        }
    }

    @discardableResult
    func saveForum(_ forum: inout ForumInstance) throws -> ForumInstance {
        try dbPool.write { db in
            try forum.save(db)
            return forum
        }
    }

    func deleteForum(_ forum: ForumInstance) throws {
        try dbPool.write { db in
            _ = try forum.delete(db)
        }
    }

    func nextForumSortOrder() throws -> Int {
        try dbPool.read { db in
            let max = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM forumInstance") ?? -1
            return max + 1
        }
    }

    func updateForumOrder(_ forums: [ForumInstance]) throws {
        try dbPool.write { db in
            for (index, forum) in forums.enumerated() {
                var updated = forum
                updated.sortOrder = index
                try updated.update(db)
            }
        }
    }
}
