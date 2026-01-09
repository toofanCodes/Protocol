//
//  ModelTests.swift
//  ProtocolTests
//
//  Unit tests for model computed properties and business logic.
//

import XCTest
import SwiftData
@testable import Protocol

final class ModelTests: XCTestCase {
    
    // MARK: - MoleculeInstance Progress Tests
    
    func testMoleculeInstanceProgress_ReturnsZeroWhenNoAtomsCompleted() {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date())
        let atom1 = AtomInstance(title: "Task 1", isCompleted: false, parentMoleculeInstance: instance)
        let atom2 = AtomInstance(title: "Task 2", isCompleted: false, parentMoleculeInstance: instance)
        instance.atomInstances = [atom1, atom2]
        
        // Then
        XCTAssertEqual(instance.progress, 0.0, "Progress should be 0 when no atoms completed")
    }
    
    func testMoleculeInstanceProgress_ReturnsCorrectPercentage() {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date())
        let atom1 = AtomInstance(title: "Task 1", isCompleted: true, parentMoleculeInstance: instance)
        let atom2 = AtomInstance(title: "Task 2", isCompleted: false, parentMoleculeInstance: instance)
        instance.atomInstances = [atom1, atom2]
        
        // Then
        XCTAssertEqual(instance.progress, 0.5, "Progress should be 0.5 when 1 of 2 atoms completed")
    }
    
    func testMoleculeInstanceProgress_ReturnsOneWhenAllAtomsCompleted() {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date())
        let atom1 = AtomInstance(title: "Task 1", isCompleted: true, parentMoleculeInstance: instance)
        let atom2 = AtomInstance(title: "Task 2", isCompleted: true, parentMoleculeInstance: instance)
        instance.atomInstances = [atom1, atom2]
        
        // Then
        XCTAssertEqual(instance.progress, 1.0, "Progress should be 1.0 when all atoms completed")
    }
    
    func testMoleculeInstanceProgress_ReturnsOneWhenMarkedComplete() {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date(), isCompleted: true)
        let atom1 = AtomInstance(title: "Task 1", isCompleted: false, parentMoleculeInstance: instance)
        instance.atomInstances = [atom1]
        
        // Then
        XCTAssertEqual(instance.progress, 1.0, "Progress should be 1.0 when instance is marked complete")
    }
    
    func testMoleculeInstanceProgress_ReturnsZeroForEmptyAtomsNotCompleted() {
        // Given
        let instance = MoleculeInstance(scheduledDate: Date(), isCompleted: false)
        instance.atomInstances = []
        
        // Then
        XCTAssertEqual(instance.progress, 0.0, "Progress should be 0 for empty atoms when not completed")
    }
    
    // MARK: - AtomInstance Progress Tests
    
    func testAtomInstanceProgress_Binary_ReturnsZeroOrOne() {
        // Given
        let incompleteAtom = AtomInstance(title: "Binary Task", inputType: .binary, isCompleted: false)
        let completeAtom = AtomInstance(title: "Binary Task", inputType: .binary, isCompleted: true)
        
        // Then
        XCTAssertEqual(incompleteAtom.progress, 0.0, "Incomplete binary should be 0")
        XCTAssertEqual(completeAtom.progress, 1.0, "Complete binary should be 1")
    }
    
    func testAtomInstanceProgress_Counter_ReturnsRatio() {
        // Given
        let atom = AtomInstance(
            title: "Counter Task",
            inputType: .counter,
            currentValue: 3,
            targetValue: 10
        )
        
        // Then
        XCTAssertEqual(atom.progress, 0.3, accuracy: 0.001, "Counter progress should be 3/10 = 0.3")
    }
    
    func testAtomInstanceProgress_Counter_CapsAtOne() {
        // Given
        let atom = AtomInstance(
            title: "Counter Task",
            inputType: .counter,
            currentValue: 15,
            targetValue: 10
        )
        
        // Then
        XCTAssertEqual(atom.progress, 1.0, "Counter progress should cap at 1.0")
    }
    
    // MARK: - AtomInstance Increment/Decrement Tests
    
    func testAtomInstanceIncrement_IncreasesValue() {
        // Given
        let atom = AtomInstance(
            title: "Counter",
            inputType: .counter,
            currentValue: 2,
            targetValue: 5
        )
        
        // When
        atom.increment()
        
        // Then
        XCTAssertEqual(atom.currentValue, 3, "Value should increase by 1")
        XCTAssertFalse(atom.isCompleted, "Should not be completed yet")
    }
    
    func testAtomInstanceIncrement_AutoCompletesAtTarget() {
        // Given
        let atom = AtomInstance(
            title: "Counter",
            inputType: .counter,
            currentValue: 4,
            targetValue: 5
        )
        
        // When
        atom.increment()
        
        // Then
        XCTAssertEqual(atom.currentValue, 5, "Value should be 5")
        XCTAssertTrue(atom.isCompleted, "Should auto-complete when target reached")
        XCTAssertNotNil(atom.completedAt, "Should have completion timestamp")
    }
    
    func testAtomInstanceDecrement_DecreasesValue() {
        // Given
        let atom = AtomInstance(
            title: "Counter",
            inputType: .counter,
            currentValue: 3,
            targetValue: 5
        )
        
        // When
        atom.decrement()
        
        // Then
        XCTAssertEqual(atom.currentValue, 2, "Value should decrease by 1")
    }
    
    func testAtomInstanceDecrement_DoesNotGoBelowZero() {
        // Given
        let atom = AtomInstance(
            title: "Counter",
            inputType: .counter,
            currentValue: 0,
            targetValue: 5
        )
        
        // When
        atom.decrement()
        
        // Then
        XCTAssertEqual(atom.currentValue, 0, "Value should not go below 0")
    }
    
    func testAtomInstanceDecrement_UncompletesWhenBelowTarget() {
        // Given
        let atom = AtomInstance(
            title: "Counter",
            inputType: .counter,
            isCompleted: true,
            currentValue: 5,
            targetValue: 5
        )
        atom.completedAt = Date()
        
        // When
        atom.decrement()
        
        // Then
        XCTAssertEqual(atom.currentValue, 4, "Value should be 4")
        XCTAssertFalse(atom.isCompleted, "Should uncomplete when below target")
        XCTAssertNil(atom.completedAt, "Should clear completion timestamp")
    }
    
    // MARK: - AtomInstance Workout Tests
    
    func testAtomInstance_IsWorkoutExercise() {
        // Given
        let workoutAtom = AtomInstance(
            title: "Bench Press",
            inputType: .value,
            targetSets: 4,
            targetReps: 10
        )
        let regularAtom = AtomInstance(
            title: "Drink Water",
            inputType: .binary
        )
        
        // Then
        XCTAssertTrue(workoutAtom.isWorkoutExercise, "Should be workout exercise")
        XCTAssertFalse(regularAtom.isWorkoutExercise, "Should not be workout exercise")
    }
    
    func testAtomInstance_WorkoutTargetString() {
        // Given
        let atom = AtomInstance(
            title: "Bench Press",
            inputType: .value,
            targetSets: 4,
            targetReps: 10
        )
        
        // Then
        XCTAssertEqual(atom.workoutTargetString, "4 Sets × 10 Reps")
    }
    
    // MARK: - MoleculeInstance Date Tests
    
    func testMoleculeInstance_IsToday() {
        // Given
        let todayInstance = MoleculeInstance(scheduledDate: Date())
        let yesterdayInstance = MoleculeInstance(
            scheduledDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        
        // Then
        XCTAssertTrue(todayInstance.isToday, "Instance scheduled for now should be today")
        XCTAssertFalse(yesterdayInstance.isToday, "Instance scheduled for yesterday should not be today")
    }
    
    func testMoleculeInstance_IsPast() {
        // Given
        let pastInstance = MoleculeInstance(
            scheduledDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        )
        let futureInstance = MoleculeInstance(
            scheduledDate: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        )
        
        // Then
        XCTAssertTrue(pastInstance.isPast, "Instance 1 hour ago should be past")
        XCTAssertFalse(futureInstance.isPast, "Instance 1 hour ahead should not be past")
    }
}
