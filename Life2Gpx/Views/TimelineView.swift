//
//  TimelineView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 25.4.2024.
//

import SwiftUI
import MapKit
import CoreGPX
import Foundation

private enum TimelineDisplayItem: Identifiable {
    case single(TimelineObject)
    case groupHeader(id: UUID, items: [TimelineObject], isExpanded: Bool)
    case groupChild(TimelineObject)

    var id: String {
        switch self {
        case .single(let obj): return "s-\(obj.id.uuidString)"
        case .groupHeader(let id, _, _): return "g-\(id.uuidString)"
        case .groupChild(let obj): return "c-\(obj.id.uuidString)"
        }
    }
}

struct TimelineView: View {
    @Binding var timelineObjects: [TimelineObject]
    @Binding var selectedTimelineObjectID: UUID?
    @State private var editingTimelineObject: TimelineObject?
    @State private var showingEditSheet = false
    @State private var expandedGroupIDs: Set<UUID> = []

    var groupingMinutes: Double
    var onRefresh: () -> Void
    var onSelectItem: (TimelineObject) -> Void
    var onSelectGroup: (([TimelineObject]) -> Void)?
    var selectedDate: Date
    var onEditVisit: ((TimelineObject, Place?) -> Void)?
    var onRecenter: () -> Void

    private var displayItems: [TimelineDisplayItem] {
        guard groupingMinutes > 0 else {
            return timelineObjects.map { .single($0) }
        }

        var result: [TimelineDisplayItem] = []
        var pendingGroup: [TimelineObject] = []

        func flushGroup() {
            guard !pendingGroup.isEmpty else { return }
            if pendingGroup.count == 1 {
                result.append(.single(pendingGroup[0]))
            } else {
                let groupID = pendingGroup[0].id
                let isExpanded = expandedGroupIDs.contains(groupID)
                result.append(.groupHeader(id: groupID, items: pendingGroup, isExpanded: isExpanded))
                if isExpanded {
                    for item in pendingGroup {
                        result.append(.groupChild(item))
                    }
                }
            }
            pendingGroup = []
        }

        for item in timelineObjects {
            if item.durationInMinutes >= groupingMinutes {
                flushGroup()
                result.append(.single(item))
            } else {
                pendingGroup.append(item)
            }
        }
        flushGroup()

        return result
    }
    
    var body: some View {
        List(displayItems) { displayItem in
            switch displayItem {
            case .single(let item):
                itemRow(item: item, showEdit: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation { onSelectItem(item) }
                    }
                    .listRowBackground(item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color.clear)

            case .groupHeader(let groupID, let items, let isExpanded):
                groupHeaderRow(groupID: groupID, items: items, isExpanded: isExpanded)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation {
                            onSelectGroup?(items)
                        }
                    }
                    .listRowBackground(
                        items.contains(where: { $0.selected }) ? Color.blue.opacity(0.3) : Color.clear
                    )

            case .groupChild(let item):
                itemRow(item: item, showEdit: true)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation { onSelectItem(item) }
                    }
                    .listRowBackground(item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color(.secondarySystemBackground))
            }
        }
        .refreshable {
            onRefresh()
        }
        .listStyle(PlainListStyle())
        .sheet(isPresented: $showingEditSheet, content: {
            if let timelineObject = editingTimelineObject {
                if timelineObject.type == .waypoint {
                    EditVisitView(
                        timelineObject: timelineObject,
                        fileDate: selectedDate,
                        onSave: { place in
                            onEditVisit?(timelineObject, place)
                        }
                    )
                } else {
                    EditTrackView(
                        timelineObject: timelineObject,
                        fileDate: selectedDate,
                        onSaveChanges: {
                            onRefresh()
                            onRecenter()
                        }
                    )
                }
            }
        })
        .onChange(of: showingEditSheet) { newValue in
            if !newValue {
                editingTimelineObject = nil
            }
        }
        .onChange(of: groupingMinutes) {
            expandedGroupIDs.removeAll()
        }
    }

    // MARK: - Item Row

    @ViewBuilder
    private func itemRow(item: TimelineObject, showEdit: Bool) -> some View {
        HStack {
            VStack(alignment: .trailing) {
                if let startDate = item.startDate {
                    Text("\(formatDateToHoursMinutes(startDate))")
                        .bold()
                }
                Text(item.duration)
            }
            .frame(minWidth: 80, alignment: .trailing)

            HStack {
                VStack(alignment: .center) {
                    if item.type == .waypoint {
                        PlaceIconView(icon: item.customIcon, fallbackColor: .gray)
                    } else {
                        switch item.trackType {
                        case "cycling":
                            Image(systemName: "figure.outdoor.cycle")
                                .foregroundColor(trackTypeColorMapping[item.trackType ?? "cycling"])
                        case "walking":
                            Image(systemName: "figure.walk")
                                .foregroundColor(trackTypeColorMapping[item.trackType ?? "walking"])
                        case "running":
                            Image(systemName: "figure.run")
                                .foregroundColor(trackTypeColorMapping[item.trackType ?? "running"])
                        case "automotive":
                            Image(systemName: "car.fill")
                                .foregroundColor(trackTypeColorMapping[item.trackType ?? "automotive"])
                        default:
                            Image(systemName: "arrow.down")
                                .foregroundColor(trackTypeColorMapping[item.trackType ?? "unknown"])
                        }
                    }
                }
                .frame(width: 35, alignment: .center)
            }

            VStack(alignment: .leading) {
                if item.type == .waypoint {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Unknown Place")
                            Group {
                                if item.meters > 0 || item.steps > 0 || item.averageSpeed > 0 {
                                    HStack {
                                        if item.meters > 0 {
                                            if item.meters < 1000 {
                                                Text("\(item.meters) m").font(.footnote)
                                            } else {
                                                Text("\(item.meters/1000) km").font(.footnote)
                                            }
                                        }
                                        if item.steps > 0 {
                                            Text("\(item.steps) steps").font(.footnote)
                                        }
                                        if item.averageSpeed > 0 {
                                            Text("\(String(format: "%.1f", item.averageSpeed)) km/h").font(.footnote)
                                        }
                                    }
                                } else {
                                    Color.clear.frame(height: 0)
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.trackType?.capitalized ?? "Movement")
                            if item.meters > 0 || item.steps > 0 || item.averageSpeed > 0 {
                                HStack {
                                    if item.meters > 0 {
                                        if item.meters < 1000 {
                                            Text("\(item.meters) m").font(.footnote)
                                        } else {
                                            Text("\(item.meters/1000) km").font(.footnote)
                                        }
                                    }
                                    if item.steps > 0 {
                                        Text("\(item.steps) steps").font(.footnote)
                                    }
                                    if item.averageSpeed > 0 {
                                        Text("\(String(format: "%.1f", item.averageSpeed)) km/h").font(.footnote)
                                    }
                                }
                            }
                        }
                    }
                }
                if item.numberOfPoints == 1 {
                    Text("\(item.numberOfPoints) point").font(.footnote)
                } else if item.numberOfPoints > 1 {
                    Text("\(item.numberOfPoints) points").font(.footnote)
                }
            }

            Spacer()

            if showEdit {
                if item.type == .waypoint && (item.id == selectedTimelineObjectID || item.name == nil || item.name == "Unknown Place" || item.name == "Unknown place") {
                    Button(action: {
                        editingTimelineObject = item
                        onSelectItem(item)
                        showingEditSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(item.id == selectedTimelineObjectID ? .black : .blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .contentShape(Rectangle())
                } else if item.type == .track && item.id == selectedTimelineObjectID {
                    Button(action: {
                        editingTimelineObject = item
                        showingEditSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.black)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Group Header Row

    @ViewBuilder
    private func groupHeaderRow(groupID: UUID, items: [TimelineObject], isExpanded: Bool) -> some View {
        HStack {
            VStack(alignment: .trailing) {
                if let startDate = items.first?.startDate {
                    Text("\(formatDateToHoursMinutes(startDate))")
                        .bold()
                }
                if let start = items.first?.startDate, let end = items.last?.endDate {
                    Text(calculateDuration(from: start, to: end))
                }
            }
            .frame(minWidth: 80, alignment: .trailing)

            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundColor(.secondary)
            }
            .frame(width: 35, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(groupSummary(items))
                Text("\(items.count) items")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                withAnimation {
                    if expandedGroupIDs.contains(groupID) {
                        expandedGroupIDs.remove(groupID)
                    } else {
                        expandedGroupIDs.insert(groupID)
                    }
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.blue)
                    .padding(.trailing, 4)
            }
            .buttonStyle(BorderlessButtonStyle())
            .contentShape(Rectangle())
        }
    }

    // MARK: - Helpers

    private func groupSummary(_ items: [TimelineObject]) -> String {
        let tracks = items.filter { $0.type == .track }.count
        let stops = items.filter { $0.type == .waypoint }.count
        var parts: [String] = []
        if tracks > 0 {
            parts.append("\(tracks) track\(tracks == 1 ? "" : "s")")
        }
        if stops > 0 {
            parts.append("\(stops) stop\(stops == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }
}
