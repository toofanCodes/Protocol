//
//  CalendarView.swift
//  Protocol
//
//  Created on 2025-12-29.
//

import SwiftUI
import SwiftData

/// The Main Calendar Hub Interface
struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @Query(sort: \MoleculeInstance.scheduledDate) private var allInstances: [MoleculeInstance]
    @Query(sort: \MoleculeTemplate.title) private var templates: [MoleculeTemplate]
    
    // For manual drag operations in DayView
    @Environment(\.modelContext) private var modelContext
    @State private var draggingInstance: MoleculeInstance?
    @State private var dragOffset: CGSize = .zero
    @State private var instanceToDelete: MoleculeInstance?
    @State private var showingDeleteConfirmation = false
    
    // Long press to create new habit
    @State private var showingNewHabitSheet = false
    @State private var longPressTime: Date = Date()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 0. App Branding Header
                AppHeaderView {
                    withAnimation {
                        viewModel.currentDate = Date()
                    }
                }
                
                // 1. Navigation Header
                CalendarHeader(viewModel: viewModel)
                    .zIndex(2)
                
                // 2. Filter Bar (Dynamic)
                FilterBar(viewModel: viewModel, templates: templates)
                    .zIndex(1)
                
                // 3. Main Content (TabView)
                TabView(selection: $viewModel.viewMode) {
                    DayView(
                        viewModel: viewModel,
                        instances: viewModel.filteredInstances(from: allInstances),
                        draggingInstance: $draggingInstance,
                        dragOffset: $dragOffset,
                        onDrop: dropInstance,
                        onLongPress: { time in
                            longPressTime = time
                            showingNewHabitSheet = true
                        }
                    )
                    .tag(CalendarViewMode.day)
                    
                    WeekView(
                        viewModel: viewModel,
                        allInstances: allInstances // Pass all, view filters
                    )
                    .tag(CalendarViewMode.week)
                    
                    MonthView(
                        viewModel: viewModel,
                        allInstances: allInstances
                    )
                    .tag(CalendarViewMode.month)
                    
                    MoleculeListView(viewModel: viewModel)
                        .tag(CalendarViewMode.list)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Disable swipe to avoid conflict with drag or Calendar nav? 
                // Using page style allows swiping between modes which might be nice or confusing. 
                // User asked for "Switch statement on View Picker", implying explicit switch.
                // Standard TabView with page style gives transitions.
                // But let's use a standard switch if preferred for strict mode control.
            }
            .navigationBarHidden(true)
            .sheet(item: $viewModel.selectedInstance) { instance in
                NavigationStack {
                    MoleculeInstanceDetailView(instance: instance)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingNewHabitSheet) {
                NavigationStack {
                    NewHabitFromLongPressView(prefilledTime: longPressTime)
                }
            }
            .alert("Delete Instance?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { instanceToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let instance = instanceToDelete {
                        deleteInstance(instance)
                    }
                    instanceToDelete = nil
                }
            } message: {
                Text("This will permanently remove this scheduled instance.")
            }
        }
    }
    
    // MARK: - Delete Action
    
    private func deleteInstance(_ instance: MoleculeInstance) {
        NotificationManager.shared.cancelNotification(for: instance)
        modelContext.delete(instance)
        try? modelContext.save()
    }
    
    private func requestDelete(_ instance: MoleculeInstance) {
        instanceToDelete = instance
        showingDeleteConfirmation = true
    }
    
    private func toggleComplete(_ instance: MoleculeInstance) {
        instance.toggleComplete()
        if instance.isCompleted {
            NotificationManager.shared.cancelNotification(for: instance)
        } else {
            Task {
                await NotificationManager.shared.scheduleNotifications(for: instance)
            }
        }
        try? modelContext.save()
    }
    
    // MARK: - Drag & Drop Logic (Day View)
    
    private func dropInstance(_ instance: MoleculeInstance, translation: CGSize) {
        let hourHeight: CGFloat = 80
        let startHour: Int = 5
        let endHour: Int = 24
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: instance.effectiveTime)
        let minute = calendar.component(.minute, from: instance.effectiveTime)
        
        let normalizedHour = Double(hour) - Double(startHour)
        let normalizedMinute = Double(minute) / 60.0
        let currentY = (normalizedHour + normalizedMinute) * Double(hourHeight)
        
        let dropY = currentY + translation.height
        
        var timeInHours = (dropY / hourHeight) + CGFloat(startHour)
        
        // Clamp
        if timeInHours < CGFloat(startHour) { timeInHours = CGFloat(startHour) }
        if timeInHours > CGFloat(endHour) { timeInHours = CGFloat(endHour) }
        
        // Snap to 15 mins
        let snappedTime = (round(timeInHours * 4) / 4)
        
        let newHour = Int(snappedTime)
        let newMinute = Int((snappedTime.truncatingRemainder(dividingBy: 1) * 60))
        
        // Update Instance
        var components = calendar.dateComponents([.year, .month, .day], from: viewModel.currentDate)
        components.hour = newHour
        components.minute = newMinute
        
        if let newDate = calendar.date(from: components) {
            // History Tracking: Preserve original date if not already set
            if instance.originalScheduledDate == nil {
                instance.originalScheduledDate = instance.scheduledDate
            }
            
            if instance.parentTemplate != nil {
                instance.makeException(time: newDate)
            } else {
                instance.scheduledDate = newDate
                instance.updatedAt = Date()
            }
            try? modelContext.save()
            
            Task {
                await NotificationManager.shared.scheduleNotifications(for: instance)
            }
        }
    }
}

// MARK: - Subviews

/// A branded header component for the app
struct AppHeaderView: View {
    var onTodayTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Logo
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Caption
                Text("Protocol - Build Habits")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Today Button
                Button(action: onTodayTapped) {
                    Text("Today")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct CalendarHeader: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    withAnimation { viewModel.moveDate(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Text(viewModel.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                
                Spacer()
                
                Button {
                    withAnimation { viewModel.moveDate(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)
            
            Picker("View Mode", selection: $viewModel.viewMode) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }
}

struct FilterBar: View {
    @ObservedObject var viewModel: CalendarViewModel
    let templates: [MoleculeTemplate]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" Option
                filterButton(for: .all)
                
                // "Uncategorized" Option
                filterButton(for: .uncategorized)
                
                // Dynamic Compound Options
                ForEach(uniqueCompounds, id: \.self) { compound in
                    filterButton(for: .compound(compound))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    private var uniqueCompounds: [String] {
        Array(Set(templates.compactMap { $0.compound })).sorted()
    }
    
    private func filterButton(for filter: FilterOption) -> some View {
        Button {
            withAnimation { viewModel.selectedFilter = filter }
        } label: {
            Text(filter.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(viewModel.selectedFilter == filter ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                )
                .foregroundStyle(viewModel.selectedFilter == filter ? .white : .primary)
        }
    }
}

// MARK: - View Modes

struct DayView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let instances: [MoleculeInstance]
    @Binding var draggingInstance: MoleculeInstance?
    @Binding var dragOffset: CGSize
    let onDrop: (MoleculeInstance, CGSize) -> Void
    let onLongPress: (Date) -> Void
    
    // Constants
    private let hourHeight: CGFloat = 80
    private let startHour: Int = 0
    private let endHour: Int = 23
    
    // MARK: - Computed Properties
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(viewModel.currentDate)
    }
    
    private var currentTimeYPosition: CGFloat {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let normalizedHour = Double(hour) - Double(startHour)
        let normalizedMinute = Double(minute) / 60.0
        return (normalizedHour + normalizedMinute) * Double(hourHeight) + 20
    }
    
    /// All-day instances sorted alphabetically
    private var allDayInstances: [MoleculeInstance] {
        instances.filter { $0.isAllDay }
            .sorted { $0.displayTitle < $1.displayTitle }
    }
    
    /// Timed instances (non all-day)
    private var timedInstances: [MoleculeInstance] {
        instances.filter { !$0.isAllDay }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Section A: All-Day Dock (max 30% height)
                if !allDayInstances.isEmpty {
                    AllDayDockView(
                        instances: allDayInstances,
                        viewModel: viewModel
                    )
                    .frame(maxHeight: geometry.size.height * 0.3)
                    
                    Divider()
                }
                
                // Section B: Timeline
                timelineView
            }
        }
    }
    
    // MARK: - Timeline View (extracted for clarity)
    
    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Grid Lines
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(startHour...endHour, id: \.self) { hour in
                            HStack {
                                Text(formatHour(hour))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 45, alignment: .trailing)
                                    .offset(y: -6)
                                
                                Rectangle()
                                    .fill(Color(uiColor: .secondarySystemBackground))
                                    .frame(height: 1)
                            }
                            .frame(height: hourHeight, alignment: .top)
                            .id(hour) // ID for ScrollViewReader
                        }
                    }
                    .padding(.top, 20)
                    
                    // Now Indicator Line (only show for today)
                    if isToday {
                        NowIndicatorLine()
                            .offset(y: currentTimeYPosition)
                    }
                    
                    // Only show timed instances in timeline
                    ForEach(timedInstances) { instance in
                        DraggableMoleculeBlock(
                            instance: instance,
                            position: calculatePosition(for: instance),
                            height: calculateHeight(for: instance),
                            isDragging: draggingInstance == instance,
                            dragOffset: dragOffset,
                            onDragStart: { draggingInstance = instance },
                            onDragChanged: { dragOffset = $0 },
                            onDragEnded: { translation in
                                onDrop(instance, translation)
                                draggingInstance = nil
                                dragOffset = .zero
                            },
                            onTap: {
                                viewModel.selectedInstance = instance
                            },
                            onComplete: {
                                instance.toggleComplete()
                                if instance.isCompleted {
                                    NotificationManager.shared.cancelNotification(for: instance)
                                }
                            },
                            onDelete: {
                                NotificationManager.shared.cancelNotification(for: instance)
                            }
                        )
                    }
                }
                .padding(.bottom, 50)
                // Long Press Gesture for Creating New Habit
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    // This is required but we use the coordinate version below
                } onPressingChanged: { _ in }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onEnded { value in
                            switch value {
                            case .second(true, let drag):
                                if let location = drag?.location {
                                    let calculatedTime = calculateTimeFromY(location.y)
                                    // Haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    onLongPress(calculatedTime)
                                }
                            default:
                                break
                            }
                        }
                )
            }
            .onAppear {
                scrollToNow(proxy: proxy)
            }
            .onChange(of: viewModel.currentDate) { _, _ in
                scrollToNow(proxy: proxy)
            }
        }
    }
    
    private func scrollToNow(proxy: ScrollViewProxy) {
        if isToday {
            let currentHour = Calendar.current.component(.hour, from: Date())
            // Ensure scroll happens after view is laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(currentHour, anchor: .center)
                }
            }
        }
    }

    
    private func formatHour(_ hour: Int) -> String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(hour12) \(period)"
    }
    
    private func calculatePosition(for instance: MoleculeInstance) -> CGPoint {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: instance.effectiveTime)
        let minute = calendar.component(.minute, from: instance.effectiveTime)
        
        let normalizedHour = Double(hour) - Double(startHour)
        let normalizedMinute = Double(minute) / 60.0
        
        if normalizedHour < 0 { return CGPoint(x: 0, y: -50) }
        
        let y = (normalizedHour + normalizedMinute) * Double(hourHeight)
        return CGPoint(x: 0, y: y)
    }
    
    private func calculateHeight(for instance: MoleculeInstance) -> CGFloat {
        return (45.0 / 60.0) * hourHeight
    }
    
    /// Converts Y coordinate to a Date snapped to 15-minute intervals
    private func calculateTimeFromY(_ y: CGFloat) -> Date {
        // Account for top padding (20)
        let adjustedY = y - 20
        
        // Calculate raw time in hours
        var timeInHours = (adjustedY / hourHeight) + CGFloat(startHour)
        
        // Clamp to valid range
        timeInHours = max(CGFloat(startHour), min(timeInHours, CGFloat(endHour + 1)))
        
        // Snap to 15-minute intervals
        let snappedTime = round(timeInHours * 4) / 4
        
        let hour = Int(snappedTime)
        let minute = Int((snappedTime.truncatingRemainder(dividingBy: 1)) * 60)
        
        // Build date using current date + calculated time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: viewModel.currentDate)
        components.hour = hour
        components.minute = minute
        
        return calendar.date(from: components) ?? Date()
    }
}

/// Red "Now" indicator line for current time in Day View
struct NowIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .padding(.leading, 42)
    }
}

// MARK: - All-Day Components

/// Dock view for all-day molecules at the top of DayView
struct AllDayDockView: View {
    let instances: [MoleculeInstance]
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack {
                    Text("All Day")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(instances.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                
                // Banners
                ForEach(instances) { instance in
                    AllDayBanner(instance: instance)
                        .onTapGesture {
                            viewModel.selectedInstance = instance
                        }
                        .contextMenu {
                            Button {
                                instance.toggleComplete()
                                if instance.isCompleted {
                                    NotificationManager.shared.cancelNotification(for: instance)
                                }
                                try? modelContext.save()
                            } label: {
                                Label(
                                    instance.isCompleted ? "Mark Incomplete" : "Mark Complete",
                                    systemImage: instance.isCompleted ? "xmark.circle" : "checkmark.circle"
                                )
                            }
                            
                            Button {
                                viewModel.selectedInstance = instance
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                NotificationManager.shared.cancelNotification(for: instance)
                                modelContext.delete(instance)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

/// Banner-style display for a single all-day molecule
struct AllDayBanner: View {
    let instance: MoleculeInstance
    
    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(instance.isCompleted ? Color.green : Color.accentColor)
                .frame(width: 8, height: 8)
            
            // Title
            Text(instance.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .strikethrough(instance.isCompleted)
                .foregroundStyle(instance.isCompleted ? .secondary : .primary)
            
            Spacer()
            
            // Completion indicator
            if instance.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct MonthView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let allInstances: [MoleculeInstance]
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                // Days of week header
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                
                // Days grid
                ForEach(viewModel.currentDate.calendarGridDays, id: \.self) { date in
                    MonthDayCell(
                        date: date,
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: viewModel.currentDate, toGranularity: .month),
                        instances: instancesFor(date: date)
                    )
                    .onTapGesture {
                        viewModel.currentDate = date
                        viewModel.viewMode = .day
                    }
                }
            }
            .padding()
        }
    }
    
    private func instancesFor(date: Date) -> [MoleculeInstance] {
        allInstances.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) && viewModel.matchesFilter($0)
        }
    }
}

struct MonthDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let instances: [MoleculeInstance]
    
    var body: some View {
        VStack(spacing: 4) {
            Text(date.formatted(.dateTime.day()))
                .font(.callout)
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    Calendar.current.isDateInToday(date) ? Circle().fill(Color.red) : nil
                )
                .foregroundStyle(Calendar.current.isDateInToday(date) ? .white : (isCurrentMonth ? .primary : .secondary))
            
            HStack(spacing: 3) {
                ForEach(instances.prefix(4)) { instance in
                    Circle()
                        .fill(colorFor(instance))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(height: 50)
        .background(Color(uiColor: .systemBackground))
    }
    
    private func colorFor(_ instance: MoleculeInstance) -> Color {
        if instance.isCompleted { return .green }
        if instance.isPast { return .red }
        return .gray
    }
}

struct WeekView: View {
    @ObservedObject var viewModel: CalendarViewModel
    let allInstances: [MoleculeInstance]
    @Environment(\.modelContext) private var modelContext
    
    private var daysOfWeek: [Date] {
        let start = viewModel.currentDate.startOfWeek
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(daysOfWeek, id: \.self) { date in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(date.formatted(.dateTime.weekday(.wide).day()))
                            .font(.headline)
                            .foregroundStyle(Calendar.current.isDateInToday(date) ? .red : .primary)
                        
                        let dayInstances = instancesFor(date: date)
                        if dayInstances.isEmpty {
                            Text("No tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dayInstances) { instance in
                                MoleculeBlockView(instance: instance)
                                    .onTapGesture {
                                        viewModel.selectedInstance = instance
                                    }
                                    .contextMenu {
                                        Button {
                                            instance.toggleComplete()
                                            if instance.isCompleted {
                                                NotificationManager.shared.cancelNotification(for: instance)
                                            }
                                            try? modelContext.save()
                                        } label: {
                                            Label(
                                                instance.isCompleted ? "Mark Incomplete" : "Mark Complete",
                                                systemImage: instance.isCompleted ? "xmark.circle" : "checkmark.circle"
                                            )
                                        }
                                        
                                        Button {
                                            viewModel.selectedInstance = instance
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            NotificationManager.shared.cancelNotification(for: instance)
                                            modelContext.delete(instance)
                                            try? modelContext.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.leading)
                }
            }
            .padding(.vertical)
        }
    }
    
    private func instancesFor(date: Date) -> [MoleculeInstance] {
        allInstances.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) && viewModel.matchesFilter($0)
        }
        .sorted { $0.scheduledDate < $1.scheduledDate }
    }
}

// MARK: - Reused Components

struct DraggableMoleculeBlock: View {
    let instance: MoleculeInstance
    let position: CGPoint
    let height: CGFloat
    let isDragging: Bool
    let dragOffset: CGSize
    
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onTap: () -> Void
    var onComplete: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        MoleculeBlockView(instance: instance)
            .onTapGesture {
                onTap()
            }
            .contextMenu {
                // Complete/Incomplete Toggle
                Button {
                    onComplete?()
                } label: {
                    Label(
                        instance.isCompleted ? "Mark Incomplete" : "Mark Complete",
                        systemImage: instance.isCompleted ? "xmark.circle" : "checkmark.circle"
                    )
                }
                
                // Edit Option
                Button {
                    onTap()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Divider()
                
                // Delete Option
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.leading, 50)
            .padding(.trailing, 8)
            .offset(y: 20 + position.y)
            .offset(y: isDragging ? dragOffset.height : 0)
            .zIndex(isDragging ? 100 : 1)
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture())
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            break
                        case .second(true, let drag):
                            if !isDragging { onDragStart() }
                            if let translation = drag?.translation { onDragChanged(translation) }
                        default: break
                        }
                    }
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let translation = drag?.translation { onDragEnded(translation) }
                        default: break
                        }
                    }
            )
    }
}

// MARK: - Extensions (for filtering arrays in ViewModel logic used here)
extension CalendarViewModel {
    func filteredInstances(from instances: [MoleculeInstance]) -> [MoleculeInstance] {
        instances.filter { shouldShow(instance: $0) }
    }
}

// MARK: - New Habit From Long Press
struct NewHabitFromLongPressView: View {
    let prefilledTime: Date
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var selectedTime: Date
    @State private var recurrenceFreq: RecurrenceFrequency = .daily
    @State private var isAllDay: Bool = false
    
    init(prefilledTime: Date) {
        self.prefilledTime = prefilledTime
        _selectedTime = State(initialValue: prefilledTime)
    }
    
    var body: some View {
        Form {
            Section("Habit Details") {
                TextField("Habit Name", text: $title)
                
                Toggle("All Day", isOn: $isAllDay)
                
                if !isAllDay {
                    DatePicker("Start Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                }
                
                Picker("Repeat", selection: $recurrenceFreq) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
            }
            
            if !isAllDay {
                Section {
                    Text("Time: \(selectedTime.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Long press detected at this time. You can adjust it above.")
                }
            }
        }
        .navigationTitle("New Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createHabit()
                }
                .disabled(title.isEmpty)
            }
        }
    }
    
    private func createHabit() {
        let template = MoleculeTemplate(
            title: title,
            baseTime: selectedTime,
            recurrenceFreq: recurrenceFreq,
            isAllDay: isAllDay
        )
        
        modelContext.insert(template)
        
        // Generate initial instances (30 days by default)
        let targetDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let instances = template.generateInstances(until: targetDate, in: modelContext)
        for instance in instances {
            modelContext.insert(instance)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [MoleculeInstance.self, MoleculeTemplate.self, AtomInstance.self, AtomTemplate.self, WorkoutSet.self], inMemory: true)
}

