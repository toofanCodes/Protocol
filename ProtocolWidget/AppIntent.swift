//
//  AppIntent.swift
//  Protocol
//
//  Created on 2025-12-31.
//

import AppIntents
import WidgetKit
import SQLite3
import Foundation

struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Habit"
    
    @Parameter(title: "Habit ID")
    var id: String
    
    // App Group for shared database
    private static let appGroupIdentifier = "group.com.Toofan.Toofanprotocol.shared"
    
    init() {}
    
    init(id: UUID) {
        self.id = id.uuidString
    }
    
    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: id) else {
            return .result()
        }
        
        guard let dbURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("Protocol.sqlite") else {
            return .result()
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            return .result()
        }
        defer { sqlite3_close(db) }
        
        // First, get current completion status
        let selectSQL = "SELECT Z_PK, ZISCOMPLETED FROM ZMOLECULEINSTANCE WHERE ZID = ?;"
        var selectStmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            // Bind UUID as blob
            let uuidData = withUnsafeBytes(of: uuid.uuid) { Data($0) }
            _ = uuidData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(selectStmt, 1, bytes.baseAddress, Int32(uuidData.count), nil)
            }
            
            if sqlite3_step(selectStmt) == SQLITE_ROW {
                let pk = sqlite3_column_int64(selectStmt, 0)
                let currentCompleted = sqlite3_column_int(selectStmt, 1) != 0
                let newCompleted = !currentCompleted
                
                sqlite3_finalize(selectStmt)
                
                // Update completion status
                let updateSQL: String
                if newCompleted {
                    // Set completed with timestamp
                    let completedAt = Date().timeIntervalSinceReferenceDate
                    updateSQL = "UPDATE ZMOLECULEINSTANCE SET ZISCOMPLETED = 1, ZCOMPLETEDAT = \(completedAt), ZUPDATEDAT = \(completedAt) WHERE Z_PK = \(pk);"
                } else {
                    // Set incomplete, clear timestamp
                    let updatedAt = Date().timeIntervalSinceReferenceDate
                    updateSQL = "UPDATE ZMOLECULEINSTANCE SET ZISCOMPLETED = 0, ZCOMPLETEDAT = NULL, ZUPDATEDAT = \(updatedAt) WHERE Z_PK = \(pk);"
                }
                
                var updateStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
                    sqlite3_step(updateStmt)
                    sqlite3_finalize(updateStmt)
                }
            } else {
                sqlite3_finalize(selectStmt)
            }
        }
        
        // Refresh widget timeline
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
