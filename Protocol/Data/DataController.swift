//
//  DataController.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import SwiftData
import Foundation
import SQLite3

@MainActor
class DataController {
    static let shared = DataController()
    
    // App Group ID for shared container with Widget
    static let appGroupIdentifier = "group.com.Toofan.Toofanprotocol.shared"
    
    let container: ModelContainer
    
    init() {
        // Use the versioned schema from our migration plan
        let schema = Schema(versionedSchema: SchemaV1.self)
        
        var modelConfiguration: ModelConfiguration
        var sqliteURL: URL?
        
        // 1. Determine Database Path
        if let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            sqliteURL = directoryURL.appendingPathComponent("Protocol.sqlite")
            
            // 2. Check for corruption & recover
            if let dbURL = sqliteURL, FileManager.default.fileExists(atPath: dbURL.path) {
                Self.recoverFromMissingMetadata(at: dbURL)
            }
            
            if let safeURL = sqliteURL {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    url: safeURL,
                    allowsSave: true
                )
            } else {
                fatalError("Critical: Failed to resolve SQLite URL.")
            }
        } else {
            // Fallback for non-app-group environments (e.g. tests)
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }
        
        // 3. Create Container with Migration Plan
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            
            // 4. Restore data if needed (from recovery)
            if let dbURL = sqliteURL, Self.needsDataRestore {
                Self.restoreDataFromBackup(at: dbURL)
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    // MARK: - Recovery Logic
    
    static var needsDataRestore = false
    
    private static func recoverFromMissingMetadata(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        // Check if Z_METADATA is missing
        if !tableExists("Z_METADATA", in: db) {
            // SCENARIO 1: Standard Corruption (Tables exist but metadata missing)
            if tableExists("ZMOLECULETEMPLATE", in: db) {
                let tables = ["ZMOLECULETEMPLATE", "ZMOLECULEINSTANCE", "ZATOMTEMPLATE", "ZATOMINSTANCE", "ZWORKOUTSET", "Z_PRIMARYKEY"]
                
                for table in tables {
                    if tableExists(table, in: db) {
                        execute("ALTER TABLE \(table) RENAME TO \(table)_BAK;", in: db)
                    }
                }
                
                performAuxiliaryCleanup(in: db)
                needsDataRestore = true
            }
            // SCENARIO 2: Interrupted Recovery
            else if tableExists("ZMOLECULETEMPLATE_BAK", in: db) {
                performAuxiliaryCleanup(in: db)
                needsDataRestore = true
            }
        }
    }
    
    private static func performAuxiliaryCleanup(in db: OpaquePointer?) {
        let allTables = getAllTableNames(in: db)
        for table in allTables {
            if !table.hasSuffix("_BAK") && table != "sqlite_sequence" {
                execute("DROP TABLE \(table);", in: db)
            }
        }
    }
    
    private static func restoreDataFromBackup(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        let tables = ["ZMOLECULETEMPLATE", "ZMOLECULEINSTANCE", "ZATOMTEMPLATE", "ZATOMINSTANCE", "ZWORKOUTSET", "Z_PRIMARYKEY"]
        
        for table in tables {
            let backupTable = "\(table)_BAK"
            if tableExists(backupTable, in: db) {
                copyData(from: backupTable, to: table, in: db)
                execute("DROP TABLE \(backupTable);", in: db)
            }
        }
        
        needsDataRestore = false
    }
    
    // MARK: - SQLite Helpers
    
    private static func tableExists(_ tableName: String, in db: OpaquePointer?) -> Bool {
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
    
    private static func execute(_ sql: String, in db: OpaquePointer?) {
        var errorMsg: UnsafeMutablePointer<Int8>? = nil
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            if let errorPointer = errorMsg {
                print("❌ SQL Error: \(String(cString: errorPointer)) in: \(sql)")
                sqlite3_free(errorMsg)
            }
        }
    }
    
    private static func copyData(from source: String, to dest: String, in db: OpaquePointer?) {
        let sourceCols = getColumns(for: source, in: db)
        let destCols = getColumns(for: dest, in: db)
        
        let commonCols = sourceCols.intersection(destCols)
        let commonColsList = commonCols.joined(separator: ", ")
        
        guard !commonCols.isEmpty else { return }
        
        var insertCols = commonColsList
        var selectCols = commonColsList
        
        // Handle new columns with defaults
        if destCols.contains("ZISALLDAY") && !sourceCols.contains("ZISALLDAY") {
            insertCols += ", ZISALLDAY"
            selectCols += ", 0"
        }
        
        let sql = "INSERT INTO \(dest) (\(insertCols)) SELECT \(selectCols) FROM \(source);"
        execute(sql, in: db)
    }
    
    private static func getColumns(for table: String, in db: OpaquePointer?) -> Set<String> {
        var columns = Set<String>()
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    columns.insert(String(cString: name))
                }
            }
            sqlite3_finalize(stmt)
        }
        return columns
    }
    
    private static func getAllTableNames(in db: OpaquePointer?) -> [String] {
        var names: [String] = []
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 0) {
                    names.append(String(cString: name))
                }
            }
            sqlite3_finalize(stmt)
        }
        return names
    }
}
