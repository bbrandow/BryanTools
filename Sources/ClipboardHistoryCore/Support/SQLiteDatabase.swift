import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase {
    fileprivate var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle {
                sqlite3_close(handle)
            }
            throw ClipboardHistoryError.database(message)
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw ClipboardHistoryError.database(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw ClipboardHistoryError.database(lastErrorMessage)
        }
        return SQLiteStatement(database: self, statement: statement)
    }

    fileprivate var lastErrorMessage: String {
        guard let handle else {
            return "Database handle is closed"
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}

final class SQLiteStatement {
    private unowned let database: SQLiteDatabase
    private var statement: OpaquePointer?

    fileprivate init(database: SQLiteDatabase, statement: OpaquePointer) {
        self.database = database
        self.statement = statement
    }

    deinit {
        if let statement {
            sqlite3_finalize(statement)
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withCString {
                sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try check(result)
    }

    func bind(_ value: Int, at index: Int32) throws {
        try check(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(statement, index, value))
    }

    func bind(_ value: UUID, at index: Int32) throws {
        try bind(value.uuidString, at: index)
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            return false
        }
        throw ClipboardHistoryError.database(database.lastErrorMessage)
    }

    func run() throws {
        _ = try step()
    }

    func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func columnInt64(_ index: Int32) -> Int64 {
        Int64(sqlite3_column_int64(statement, index))
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw ClipboardHistoryError.database(database.lastErrorMessage)
        }
    }
}
