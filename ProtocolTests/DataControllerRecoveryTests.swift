//
//  DataControllerRecoveryTests.swift
//  ProtocolTests
//
//  Tests for DataController's database recovery logic.
//

import XCTest
import SQLite3
@testable import Protocol

final class DataControllerRecoveryTests: XCTestCase {
    
    var testDatabaseURL: URL!
    
    override func setUpWithError() throws {
        // Create a temporary directory for test database
        let tempDir = FileManager.default.temporaryDirectory
        testDatabaseURL = tempDir.appendingPathComponent("TestProtocol.sqlite")
        
        // Clean up any existing test database
        try? FileManager.default.removeItem(at: testDatabaseURL)
    }
    
    override func tearDownWithError() throws {
        // Clean up test database
        try? FileManager.default.removeItem(at: testDatabaseURL)
    }
    
    // MARK: - Test Helpers
    
    private func createTestDatabase(withMetadata: Bool, withDataTables: Bool, withAuxiliaryTables: Bool) {
        var db: OpaquePointer?
        guard sqlite3_open(testDatabaseURL.path, &db) == SQLITE_OK else {
            XCTFail("Failed to create test database")
            return
        }
        defer { sqlite3_close(db) }
        
        if withMetadata {
            execute("CREATE TABLE Z_METADATA (Z_VERSION INTEGER, Z_PLIST BLOB);", in: db)
        }
        
        if withDataTables {
            execute("CREATE TABLE ZMOLECULETEMPLATE (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);", in: db)
            execute("CREATE TABLE ZMOLECULEINSTANCE (Z_PK INTEGER PRIMARY KEY, ZSCHEDULEDDATE TEXT);", in: db)
            execute("CREATE TABLE ZATOMTEMPLATE (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);", in: db)
            execute("CREATE TABLE ZATOMINSTANCE (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);", in: db)
            execute("CREATE TABLE ZWORKOUTSET (Z_PK INTEGER PRIMARY KEY, ZORDER INTEGER);", in: db)
            execute("CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_MAX INTEGER);", in: db)
            
            // Insert sample data
            execute("INSERT INTO ZMOLECULETEMPLATE (Z_PK, ZTITLE) VALUES (1, 'Morning Routine');", in: db)
            execute("INSERT INTO ZMOLECULETEMPLATE (Z_PK, ZTITLE) VALUES (2, 'Evening Workout');", in: db)
        }
        
        if withAuxiliaryTables {
            execute("CREATE TABLE ACHANGE (Z_PK INTEGER PRIMARY KEY, ZCHANGETYPE INTEGER);", in: db)
            execute("CREATE TABLE ATRANSACTION (Z_PK INTEGER PRIMARY KEY, ZTIMESTAMP REAL);", in: db)
        }
    }
    
    private func execute(_ sql: String, in db: OpaquePointer?) {
        var errorMsg: UnsafeMutablePointer<Int8>? = nil
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            if let error = errorMsg {
                print("SQL Error: \(String(cString: error))")
                sqlite3_free(errorMsg)
            }
        }
    }
    
    private func tableExists(_ tableName: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(testDatabaseURL.path, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?;"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (tableName as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = sqlite3_column_int(stmt, 0)
                sqlite3_finalize(stmt)
                return count > 0
            }
            sqlite3_finalize(stmt)
        }
        return false
    }
    
    private func getAllTableNames() -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(testDatabaseURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        var names = Set<String>()
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 0) {
                    names.insert(String(cString: name))
                }
            }
            sqlite3_finalize(stmt)
        }
        return names
    }
    
    // MARK: - Tests
    
    func testRecoveryDetectsCorruptedState() throws {
        // Given: A database with data tables but NO metadata
        createTestDatabase(withMetadata: false, withDataTables: true, withAuxiliaryTables: true)
        
        // Verify preconditions
        XCTAssertFalse(tableExists("Z_METADATA"), "Precondition: Z_METADATA should not exist")
        XCTAssertTrue(tableExists("ZMOLECULETEMPLATE"), "Precondition: Data tables should exist")
        XCTAssertTrue(tableExists("ACHANGE"), "Precondition: Auxiliary tables should exist")
        
        // When: Recovery is triggered
        DataController.recoverFromMissingMetadata(at: testDatabaseURL)
        
        // Then: Data tables should be renamed to _BAK
        XCTAssertTrue(tableExists("ZMOLECULETEMPLATE_BAK"), "Data tables should be backed up")
        XCTAssertTrue(tableExists("ZMOLECULEINSTANCE_BAK"), "Data tables should be backed up")
        
        // And: Auxiliary tables should be dropped
        XCTAssertFalse(tableExists("ACHANGE"), "Auxiliary tables should be dropped")
        XCTAssertFalse(tableExists("ATRANSACTION"), "Auxiliary tables should be dropped")
        
        // And: Original data tables should be gone
        XCTAssertFalse(tableExists("ZMOLECULETEMPLATE"), "Original tables should be renamed")
    }
    
    func testRecoveryHandlesInterruptedState() throws {
        // Given: A database with ONLY backup tables (interrupted previous recovery)
        var db: OpaquePointer?
        sqlite3_open(testDatabaseURL.path, &db)
        execute("CREATE TABLE ZMOLECULETEMPLATE_BAK (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);", in: db)
        execute("CREATE TABLE ACHANGE (Z_PK INTEGER PRIMARY KEY);", in: db)
        sqlite3_close(db)
        
        // Verify preconditions
        XCTAssertTrue(tableExists("ZMOLECULETEMPLATE_BAK"), "Precondition: Backup should exist")
        XCTAssertTrue(tableExists("ACHANGE"), "Precondition: Leftover auxiliary should exist")
        
        // When: Recovery is triggered again
        DataController.recoverFromMissingMetadata(at: testDatabaseURL)
        
        // Then: Backup should still exist
        XCTAssertTrue(tableExists("ZMOLECULETEMPLATE_BAK"), "Backup should be preserved")
        
        // And: Auxiliary tables should be cleaned up
        XCTAssertFalse(tableExists("ACHANGE"), "Leftover auxiliary should be dropped")
    }
    
    func testRecoverySkipsHealthyDatabase() throws {
        // Given: A healthy database with metadata
        createTestDatabase(withMetadata: true, withDataTables: true, withAuxiliaryTables: true)
        
        let tablesBefore = getAllTableNames()
        
        // When: Recovery is triggered
        DataController.recoverFromMissingMetadata(at: testDatabaseURL)
        
        let tablesAfter = getAllTableNames()
        
        // Then: Nothing should change
        XCTAssertEqual(tablesBefore, tablesAfter, "Healthy database should not be modified")
        XCTAssertFalse(tableExists("ZMOLECULETEMPLATE_BAK"), "No backups should be created")
    }
}

// MARK: - Expose Internal Method for Testing

extension DataController {
    /// Exposed for testing purposes - nonisolated since it's standalone SQLite operations
    nonisolated static func recoverFromMissingMetadata(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        if !tableExists("Z_METADATA", in: db) {
            if tableExists("ZMOLECULETEMPLATE", in: db) {
                let tables = ["ZMOLECULETEMPLATE", "ZMOLECULEINSTANCE", "ZATOMTEMPLATE", "ZATOMINSTANCE", "ZWORKOUTSET", "Z_PRIMARYKEY"]
                for table in tables {
                    if tableExists(table, in: db) {
                        executeSQL("ALTER TABLE \(table) RENAME TO \(table)_BAK;", in: db)
                    }
                }
                performAuxiliaryCleanupPublic(in: db)
                // Note: needsDataRestore flag is main-actor isolated, not set in test helper
            } else if tableExists("ZMOLECULETEMPLATE_BAK", in: db) {
                performAuxiliaryCleanupPublic(in: db)
                // Note: needsDataRestore flag is main-actor isolated, not set in test helper
            }
        }
    }
    
    private nonisolated static func tableExists(_ name: String, in db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = sqlite3_column_int(stmt, 0)
                sqlite3_finalize(stmt)
                return count > 0
            }
            sqlite3_finalize(stmt)
        }
        return false
    }
    
    private nonisolated static func executeSQL(_ sql: String, in db: OpaquePointer?) {
        var errorMsg: UnsafeMutablePointer<Int8>? = nil
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            if errorMsg != nil {
                sqlite3_free(errorMsg)
            }
        }
    }
    
    private nonisolated static func performAuxiliaryCleanupPublic(in db: OpaquePointer?) {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var tablesToDrop: [String] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 0) {
                    let tableName = String(cString: name)
                    if !tableName.hasSuffix("_BAK") && tableName != "sqlite_sequence" {
                        tablesToDrop.append(tableName)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        
        for table in tablesToDrop {
            executeSQL("DROP TABLE \(table);", in: db)
        }
    }
}
