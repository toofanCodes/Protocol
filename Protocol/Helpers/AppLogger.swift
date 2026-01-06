//
//  AppLogger.swift
//  Protocol
//
//  Centralized logging using OSLog for structured, filterable logs.
//  Usage: AppLogger.data.info("Message") or AppLogger.audit.error("Error: \(error)")
//

import Foundation
import OSLog

// MARK: - Log Categories

/// Centralized logging facade using Apple's OSLog framework.
/// Provides structured, filterable logs viewable in Console.app.
enum AppLogger {
    
    // MARK: - Subsystem
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.Toofan.Protocol"
    
    // MARK: - Category Loggers
    
    /// Data layer operations (SwiftData, persistence)
    static let data = Logger(subsystem: subsystem, category: "data")
    
    /// UI and view-related logs
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// Notification scheduling and handling
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    
    /// Audit trail logging (tracked separately from AuditLogger)
    static let audit = Logger(subsystem: subsystem, category: "audit")
    
    /// Background tasks and scheduling
    static let background = Logger(subsystem: subsystem, category: "background")
    
    /// Backup and restore operations
    static let backup = Logger(subsystem: subsystem, category: "backup")
    
    /// General app lifecycle and misc
    static let general = Logger(subsystem: subsystem, category: "general")
}

// MARK: - Legacy Print Replacement

/// Convenience wrapper for migrating from print() statements.
/// Logs to the 'general' category at debug level.
/// - Parameter message: The message to log
func appLog(_ message: String, file: String = #file, line: Int = #line) {
    let fileName = (file as NSString).lastPathComponent
    AppLogger.general.debug("[\(fileName):\(line)] \(message)")
}

// MARK: - Error Logging Extension

extension Logger {
    /// Logs an error with full context before allowing silent failure.
    /// Use this before `try?` to ensure errors are captured.
    /// - Parameters:
    ///   - error: The error to log
    ///   - context: Additional context about what operation failed
    func logError(_ error: Error, context: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        self.error("[\(fileName):\(line)] \(context): \(error.localizedDescription)")
    }
    
    /// Logs a warning for recoverable issues.
    func logWarning(_ message: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        self.warning("[\(fileName):\(line)] \(message)")
    }
}
