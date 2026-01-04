//
//  CSVManager.swift
//  Protocol
//
//  Blueprint Import - CSV parsing with robust validation and user feedback.
//

import Foundation
import SwiftData

// MARK: - Data Structures

/// Represents an error found during CSV parsing with user-friendly guidance
struct ImportError: Identifiable, Error {
    let id = UUID()
    let rowNumber: Int
    let rawContent: String
    let userGuidance: String
}

/// Result of CSV analysis containing valid items and errors
struct ImportReport {
    let validItems: [ParsedMolecule]
    let errors: [ImportError]
    
    var hasErrors: Bool { !errors.isEmpty }
    var isEmpty: Bool { validItems.isEmpty && errors.isEmpty }
}

/// Parsed molecule data ready for conversion to MoleculeTemplate
struct ParsedMolecule: Identifiable {
    let id = UUID()
    let name: String
    let time: Date
    let atoms: [String]
    let isAllDay: Bool
}

// MARK: - CSVManager

/// Two-pass CSV parser for Blueprint Import
/// Pass 1: analyze() - Parse and validate without saving
/// Pass 2: commit() - Save valid items to ModelContext
class CSVManager {
    
    // MARK: - Public API
    
    /// Analyzes a CSV string and returns a validation report
    /// - Parameter csvString: Raw CSV content
    /// - Returns: ImportReport with valid items and errors
    func analyze(csvString: String) -> ImportReport {
        var validItems: [ParsedMolecule] = []
        var errors: [ImportError] = []
        
        // Preprocess: Remove BOM and normalize line endings
        var content = removeBOM(from: csvString)
        content = content.replacingOccurrences(of: "\r\n", with: "\n")
        content = content.replacingOccurrences(of: "\r", with: "\n")
        
        // Detect delimiter (European CSVs use semicolons)
        let delimiter = detectDelimiter(in: content)
        
        // Split into rows
        let rows = content.components(separatedBy: "\n")
        
        // Track row number (1-indexed for user display)
        var rowNumber = 0
        
        for row in rows {
            rowNumber += 1
            
            // Skip ghost rows (empty, whitespace-only, or just delimiters)
            let trimmedRow = row.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentWithoutDelimiters = trimmedRow
                .replacingOccurrences(of: String(delimiter), with: "")
                .replacingOccurrences(of: "|", with: "")
                .trimmingCharacters(in: .whitespaces)
            if contentWithoutDelimiters.isEmpty {
                continue
            }
            
            // Skip header row
            if isHeaderRow(trimmedRow) {
                continue
            }
            
            // Parse the row
            let result = parseRow(trimmedRow, delimiter: delimiter, rowNumber: rowNumber)
            
            switch result {
            case .success(let molecule):
                validItems.append(molecule)
            case .failure(let error):
                errors.append(error)
            }
        }
        
        return ImportReport(validItems: validItems, errors: errors)
    }
    
    /// Commits parsed molecules to the ModelContext
    /// - Parameters:
    ///   - items: Parsed molecules to save
    ///   - context: SwiftData ModelContext
    /// - Returns: Created MoleculeTemplate objects
    func commit(items: [ParsedMolecule], context: ModelContext) -> [MoleculeTemplate] {
        var templates: [MoleculeTemplate] = []
        
        for item in items {
            let template = MoleculeTemplate(
                title: item.name,
                baseTime: item.time,
                recurrenceFreq: .daily, // Default to daily
                isAllDay: item.isAllDay
            )
            
            // Create AtomTemplates for each atom
            for (index, atomName) in item.atoms.enumerated() {
                let atomTemplate = AtomTemplate(
                    title: atomName.trimmingCharacters(in: .whitespaces),
                    order: index,
                    parentMoleculeTemplate: template
                )
                template.atomTemplates.append(atomTemplate)
            }
            
            context.insert(template)
            templates.append(template)
            
            // Generate initial instances (30 days)
            let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
            let instances = template.generateInstances(until: targetDate, in: context)
            for instance in instances {
                context.insert(instance)
            }
        }
        
        try? context.save()
        
        // Schedule notifications for new instances
        Task {
            for template in templates {
                for instance in template.instances {
                    await NotificationManager.shared.scheduleNotifications(for: instance)
                }
            }
        }
        
        return templates
    }
    
    /// Generates a sample CSV template
    func generateTemplate() -> String {
        return """
        Time,MoleculeName,Atoms,IsAllDay
        07:00,Morning Routine,Meditation|Journaling|Stretching,false
        ,Weekly Review,Review Goals|Plan Week,true
        06:30,Workout,Warmup|Pushups|Squats|Cooldown,false
        08:00,Breakfast,Prepare|Eat|Cleanup,false
        """
    }
    
    // MARK: - Private Methods
    
    /// Removes UTF-8 BOM if present
    private func removeBOM(from string: String) -> String {
        if string.hasPrefix("\u{FEFF}") {
            return String(string.dropFirst())
        }
        return string
    }
    
    /// Detects whether the CSV uses commas or semicolons as delimiter
    private func detectDelimiter(in content: String) -> Character {
        let commaCount = content.filter { $0 == "," }.count
        let semicolonCount = content.filter { $0 == ";" }.count
        return semicolonCount > commaCount ? ";" : ","
    }
    
    /// Checks if a row is a header row
    private func isHeaderRow(_ row: String) -> Bool {
        let lowercased = row.lowercased()
        return lowercased.contains("moleculename") || 
               lowercased.contains("molecule_name") ||
               (lowercased.contains("time") && lowercased.contains("name") && lowercased.contains("atoms"))
    }
    
    /// Parses a single CSV row
    private func parseRow(_ row: String, delimiter: Character, rowNumber: Int) -> Result<ParsedMolecule, ImportError> {
        let columns = row.components(separatedBy: String(delimiter))
        
        // Expected: Time, MoleculeName, Atoms, IsAllDay
        guard columns.count >= 2 else {
            return .failure(ImportError(
                rowNumber: rowNumber,
                rawContent: row,
                userGuidance: "Row has too few columns. Expected at least: Time, MoleculeName"
            ))
        }
        
        // Parse MoleculeName (Required)
        let nameIndex = min(1, columns.count - 1)
        let name = columns[nameIndex].trimmingCharacters(in: .whitespaces)
        
        if name.isEmpty {
            return .failure(ImportError(
                rowNumber: rowNumber,
                rawContent: row,
                userGuidance: "Missing molecule name. The second column (MoleculeName) is required."
            ))
        }
        
        // Parse IsAllDay FIRST (before time validation)
        var isAllDay = false
        if columns.count >= 4 {
            isAllDay = parseBool(columns[3])
        }
        
        // Parse Time (SKIP validation entirely if all-day)
        var time = Date()
        if !isAllDay {
            // Aggressively clean time string of hidden characters
            let timeString = columns[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{00A0}", with: "") // Non-breaking space
                .replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
                .replacingOccurrences(of: "\t", with: "")       // Tab
                .trimmingCharacters(in: .whitespaces)
            
            if !timeString.isEmpty {
                if let parsedTime = parseTime(timeString) {
                    time = parsedTime
                } else {
                    return .failure(ImportError(
                        rowNumber: rowNumber,
                        rawContent: row,
                        userGuidance: "Invalid time format '\(timeString)'. Use HH:mm (e.g., 14:30) or h:mm a (e.g., 2:30 PM)."
                    ))
                }
            }
        }
        // Note: For all-day events, time is ignored so we use default Date()
        
        // Parse Atoms (pipe-separated)
        var atoms: [String] = []
        if columns.count >= 3 {
            let atomsString = columns[2].trimmingCharacters(in: .whitespaces)
            if !atomsString.isEmpty {
                atoms = atomsString.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        
        return .success(ParsedMolecule(
            name: name,
            time: time,
            atoms: atoms,
            isAllDay: isAllDay
        ))
    }
    
    /// Parses various boolean representations
    private func parseBool(_ string: String) -> Bool {
        let lowercased = string.trimmingCharacters(in: .whitespaces).lowercased()
        return ["true", "1", "yes", "y"].contains(lowercased)
    }
    
    /// Parses time strings in various formats
    private func parseTime(_ string: String) -> Date? {
        let formats = [
            "HH:mm",      // 14:30
            "H:mm",       // 9:30
            "h:mm a",     // 2:30 PM
            "h:mma",      // 2:30PM
            "hh:mm a",    // 02:30 PM
            "hh:mma"      // 02:30PM
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                // Combine with today's date
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
                var todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
                todayComponents.hour = timeComponents.hour
                todayComponents.minute = timeComponents.minute
                return calendar.date(from: todayComponents)
            }
        }
        
        return nil
    }
}
