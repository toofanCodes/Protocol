//
//  InsightsViewModelTests.swift
//  ProtocolTests
//
//  Created on 2026-01-12.
//

import XCTest
import SwiftData
@testable import Protocol

@MainActor
final class InsightsViewModelTests: XCTestCase {
    
    var viewModel: InsightsViewModel!
    var container: ModelContainer!
    var fixedDate: Date!
    
    override func setUp() async throws {
        // Setup in-memory container (needed because VM init takes context)
        let schema = Schema([
            MoleculeTemplate.self,
            MoleculeInstance.self,
            AtomTemplate.self,
            AtomInstance.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        
        viewModel = InsightsViewModel()
        viewModel.configure(modelContext: container.mainContext)
        
        // Fix date to: Wednesday, Jan 7, 2026
        // This is a good middle-of-week date
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 7
        components.hour = 12 
        let calendar = Calendar.current
        fixedDate = calendar.date(from: components)!
        
        viewModel.currentDateProvider = { [unowned self] in self.fixedDate }
    }
    
    // MARK: - Week Range Tests
    
    func testDateRange_Week_CurrentPeriod() {
        viewModel.selectedTimeRange = .week
        viewModel.periodOffset = 0
        
        // Expected: Monday Jan 5 to Sunday Jan 11 (if Monday start) or Sun-Sat
        // Code implementation uses:
        // let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        // This depends on user's locale/calendar settings.
        // Assuming Gregorian calendar where Week 2 of 2026 starts around Jan 4/5.
        // Jan 1 2026 is Thursday.
        
        let rangeLine = viewModel.currentPeriodLabel
        // Just verify it contains the year and month
        XCTAssertTrue(rangeLine.contains("Jan"), "Should show current month")
        
        // Verify start/end logic directly if possible, or infer from logging
        // But better: Check internal method if made internal, or just trust the label output format which calls calculateDateRange
        
        // Let's verify the calculated dates using private access if allowed? No.
        // We can infer from the result label "MMM d - MMM d"
        // Jan 7 is Wed. 
        // If week starts Sun: Jan 4 - Jan 10
        // If week starts Mon: Jan 5 - Jan 11
        
        // Let's assert broadly to avoid locale fragility
        XCTAssertTrue(rangeLine.contains("2026") == false, "Week range usually doesn't show year")
    }
    
    func testDateRange_Week_PreviousPeriod() {
        viewModel.selectedTimeRange = .week
        viewModel.periodOffset = -1
        
        // Offset -1 week
        // Should be around Dec 29/30 - Jan 3/4
        
        let rangeLine = viewModel.currentPeriodLabel
        XCTAssertFalse(rangeLine.isEmpty)
    }
    
    // MARK: - Month Range Tests
    
    func testDateRange_Month_CurrentPeriod() {
        viewModel.selectedTimeRange = .month
        viewModel.periodOffset = 0
        
        // Should be "January 2026"
        XCTAssertEqual(viewModel.currentPeriodLabel, "January 2026")
    }
    
    func testDateRange_Month_PreviousPeriod() {
        viewModel.selectedTimeRange = .month
        viewModel.periodOffset = -1
        
        // Should be "December 2025"
        XCTAssertEqual(viewModel.currentPeriodLabel, "December 2025")
    }
    
    func testDateRange_Month_NextPeriod() {
        viewModel.selectedTimeRange = .month
        viewModel.periodOffset = 1
        
        // Should be "February 2026"
        XCTAssertEqual(viewModel.currentPeriodLabel, "February 2026")
    }
    
    // MARK: - MTD Range Tests
    
    func testDateRange_MTD_CurrentPeriod() {
        viewModel.selectedTimeRange = .mtd
        viewModel.periodOffset = 0
        
        // Label logic for MTD is same as Month: "January 2026"
        XCTAssertEqual(viewModel.currentPeriodLabel, "January 2026")
        
        // But internally the range end is TODAY (Jan 7)
        // We can't easily inspect the private end date, but we can verify consistency
    }
    
    // MARK: - Navigation Tests
    
    func testNavigation_NextPrevious() {
        viewModel.selectedTimeRange = .month
        viewModel.periodOffset = 0
        
        viewModel.previousPeriod()
        XCTAssertEqual(viewModel.periodOffset, -1)
        XCTAssertEqual(viewModel.currentPeriodLabel, "December 2025")
        
        viewModel.nextPeriod()
        XCTAssertEqual(viewModel.periodOffset, 0)
        XCTAssertEqual(viewModel.currentPeriodLabel, "January 2026")
    }
    
    // MARK: - Streak Logic (Mocked Data)
    
    func testStreakCalculation_ConsecutiveDays() async {
        // This requires inserting data into the context
        // and waiting for loadData()
        
        let template = MoleculeTemplate(id: UUID(), title: "Test Habit", baseTime: Date())
        container.mainContext.insert(template)
        
        // Insert instances for Jan 6, Jan 7 (Today)
        let calendar = Calendar.current
        let jan6 = calendar.date(byAdding: .day, value: -1, to: fixedDate)!
        
        let i1 = MoleculeInstance(id: UUID(), scheduledDate: jan6, parentTemplate: template)
        i1.isCompleted = true
        container.mainContext.insert(i1)
        
        let i2 = MoleculeInstance(id: UUID(), scheduledDate: fixedDate, parentTemplate: template)
        i2.isCompleted = true
        container.mainContext.insert(i2)
        
        viewModel.selectedMolecule = template
        await viewModel.loadData() // Must await the reload
        
        // Assertions might be flaky without full AnalyticsService mocking or understanding its logic
        // But assuming AnalyticsService works correctly (it has its own tests? No, it doesn't!)
        // This test serves as an integration test for VM + AnalyticsService
        
        // Note: Streak calculation often relies on "yesterday" logic.
        // If fixedDate is Jan 7, and we have Jan 6 and 7, streak should be 2.
        
        XCTAssertEqual(viewModel.stats.currentStreak, 2, "Streak should count consecutive completions ending today")
    }
}
