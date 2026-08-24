//
//  TimelineDataStore.swift
//  Life2Gpx
//
//  Created by Antigravity on 2026-08-23.
//

import Foundation
import CoreGPX
import CoreLocation
import SwiftUI

@MainActor
final class TimelineDataStore: ObservableObject {
    static let shared = TimelineDataStore()

    @Published private(set) var timelines: [String: [TimelineObject]] = [:]
    @Published private(set) var loadingDates: Set<String> = []
    @Published private(set) var updateSequence: Int = 0

    private var inFlightTasks: [String: Task<[TimelineObject], Never>] = [:]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    func dayKey(for date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    func timeline(for date: Date) -> [TimelineObject]? {
        let key = dayKey(for: date)
        return timelines[key]
    }

    func getTimeline(for date: Date) -> [TimelineObject] {
        let key = dayKey(for: date)
        return timelines[key] ?? []
    }

    func isLoaded(for date: Date) -> Bool {
        let key = dayKey(for: date)
        return timelines[key] != nil
    }

    func isLoading(for date: Date) -> Bool {
        let key = dayKey(for: date)
        return loadingDates.contains(key)
    }

    func loadTimeline(for date: Date, forceRefresh: Bool = false, priority: TaskPriority = .userInitiated, completion: (([TimelineObject]) -> Void)? = nil) {
        let key = dayKey(for: date)

        if !forceRefresh, let cached = timelines[key] {
            LogManager.shared.logData(
                context: "TimelineDataStore",
                content: "Timeline cache hit for \(key) (\(cached.count) objects)",
                verbosity: 5
            )
            completion?(cached)
            return
        }

        if let existingTask = inFlightTasks[key] {
            LogManager.shared.logData(
                context: "TimelineDataStore",
                content: "Timeline load already in flight for \(key). Awaiting existing task.",
                verbosity: 5
            )
            Task(priority: priority) { @MainActor in
                let objects = await existingTask.value
                completion?(objects)
            }
            return
        }

        loadingDates.insert(key)
        LogManager.shared.logData(
            context: "TimelineDataStore",
            content: "Starting timeline load for \(key) (forceRefresh=\(forceRefresh), priority=\(priority))",
            verbosity: 4
        )

        let task = Task<[TimelineObject], Never>(priority: priority) { @MainActor in
            await withCheckedContinuation { continuation in
                loadTimelineForDate(date) { objects in
                    continuation.resume(returning: objects)
                }
            }
        }
        inFlightTasks[key] = task

        Task(priority: priority) { @MainActor in
            let objects = await task.value
            self.timelines[key] = objects
            self.loadingDates.remove(key)
            self.inFlightTasks.removeValue(forKey: key)
            self.updateSequence &+= 1
            LogManager.shared.logData(
                context: "TimelineDataStore",
                content: "Finished timeline load for \(key): \(objects.count) objects cached.",
                verbosity: 4
            )
            completion?(objects)
        }
    }

    func maintainThreeDayBuffer(for date: Date, minDate: Date? = nil, maxDate: Date? = nil) {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        let normalizedMin = minDate.map { calendar.startOfDay(for: $0) }
        let normalizedMax = maxDate.map { calendar.startOfDay(for: $0) }

        var validKeys: Set<String> = [dayKey(for: normalized)]

        // Ensure current day is loaded
        let currentKey = dayKey(for: normalized)
        if timelines[currentKey] == nil && !loadingDates.contains(currentKey) && inFlightTasks[currentKey] == nil {
            loadTimeline(for: normalized, forceRefresh: false, priority: .userInitiated)
        }

        // Preload yesterday
        if let prevDate = calendar.date(byAdding: .day, value: -1, to: normalized) {
            let normalizedPrev = calendar.startOfDay(for: prevDate)
            let shouldSkipPrev: Bool
            if let normalizedMin = normalizedMin, normalizedMin < normalized {
                shouldSkipPrev = normalizedPrev < normalizedMin
            } else {
                // If minDate is uninitialized or equal to date, do not block preloading yesterday
                shouldSkipPrev = false
            }

            if !shouldSkipPrev {
                let prevKey = dayKey(for: normalizedPrev)
                validKeys.insert(prevKey)
                if timelines[prevKey] == nil && !loadingDates.contains(prevKey) && inFlightTasks[prevKey] == nil {
                    loadTimeline(for: normalizedPrev, forceRefresh: false, priority: .userInitiated)
                }
            }
        }

        // Preload tomorrow
        if let nextDate = calendar.date(byAdding: .day, value: 1, to: normalized) {
            let normalizedNext = calendar.startOfDay(for: nextDate)
            let shouldSkipNext: Bool
            if let normalizedMax = normalizedMax, normalizedMax > normalized {
                shouldSkipNext = normalizedNext > normalizedMax
            } else if let normalizedMax = normalizedMax, normalizedMax == normalized && normalized >= calendar.startOfDay(for: Date()) {
                // If maxDate is today, tomorrow has no data
                shouldSkipNext = true
            } else {
                shouldSkipNext = false
            }

            if !shouldSkipNext {
                let nextKey = dayKey(for: normalizedNext)
                validKeys.insert(nextKey)
                if timelines[nextKey] == nil && !loadingDates.contains(nextKey) && inFlightTasks[nextKey] == nil {
                    loadTimeline(for: normalizedNext, forceRefresh: false, priority: .userInitiated)
                }
            }
        }

        // Unload any cached days outside the 3-day window
        let keysToPurge = timelines.keys.filter { !validKeys.contains($0) }
        for key in keysToPurge {
            timelines.removeValue(forKey: key)
            inFlightTasks[key]?.cancel()
            inFlightTasks.removeValue(forKey: key)
            loadingDates.remove(key)
        }
    }

    func preloadSurroundingDays(for date: Date, minDate: Date? = nil, maxDate: Date? = nil, range: Int = 1) {
        maintainThreeDayBuffer(for: date, minDate: minDate, maxDate: maxDate)
    }

    func update(for date: Date, objects: [TimelineObject]) {
        let key = dayKey(for: date)
        timelines[key] = objects
        updateSequence &+= 1
        LogManager.shared.logData(
            context: "TimelineDataStore",
            content: "Updated cached timeline for \(key) (\(objects.count) objects)",
            verbosity: 4
        )
    }

    func invalidate(for date: Date) {
        let key = dayKey(for: date)
        timelines.removeValue(forKey: key)
        inFlightTasks[key]?.cancel()
        inFlightTasks.removeValue(forKey: key)
        loadingDates.remove(key)
        updateSequence &+= 1
        LogManager.shared.logData(
            context: "TimelineDataStore",
            content: "Invalidated cache for \(key)",
            verbosity: 4
        )
    }

    func invalidateAll() {
        timelines.removeAll()
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
        loadingDates.removeAll()
        updateSequence &+= 1
        LogManager.shared.logData(
            context: "TimelineDataStore",
            content: "Invalidated all cached timelines",
            verbosity: 4
        )
    }
}
