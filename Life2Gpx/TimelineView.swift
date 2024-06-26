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

struct TimelineView: View {
    @Binding var timelineObjects: [TimelineObject]
    @Binding var selectedTimelineObjectID: UUID?

    var onRefresh: () -> Void
    var onSelectItem: (TimelineObject) -> Void
    
    var body: some View {
        List(timelineObjects) { item in
            
            HStack {
                
                VStack (alignment: .trailing ){
                    if let startDate = item.startDate {
                        Text("\(formatDateToHoursMinutes(startDate))")
                            .bold()
                    }
                    Text(item.duration)
                }
                .frame(minWidth:80, alignment: .trailing)
                HStack {
                    VStack(alignment: .center)
                    {
                        if (item.type == .waypoint){
                            
                            Image(systemName: "smallcircle.filled.circle")
                                .foregroundColor(.gray)
                        }
                        else
                        {
                            switch item.trackType
                            {
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
                
                VStack (alignment: .leading)
                {
                    if item.type == .waypoint
                    {
                        Text(item.name ?? "Unknown place")
                    }
                    else
                    {
                        Text(item.trackType?.capitalized ?? "Movement")
                    }
                    HStack{
                        if item.meters > 0 {
                            if item.meters < 1000{
                                Text("\(item.meters) m")
                                    .font(.footnote)
                            }
                            else{
                                Text("\(item.meters/1000) km")
                                    .font(.footnote)
                            }
                        }
                        if item.steps > 0{
                            Text("\(item.steps) steps")
                                .font(.footnote)
                        }
                        if item.averageSpeed > 0 {
                            Text("\(String(format: "%.1f", item.averageSpeed)) km/h")
                                .font(.footnote)
                        }
                    }.frame(minWidth: 80, alignment: .leading)
                    if item.numberOfPoints == 1 {
                        Text("\(item.numberOfPoints) point")
                            .font(.footnote)
                    }
                    else if item.numberOfPoints > 1 {
                        Text("\(item.numberOfPoints) points")
                            .font(.footnote)
                    }
                }
            }
            //.listRowSeparator(.hidden) //an option for the future?
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            
            .alignmentGuide(.listRowSeparatorLeading)
            { viewDimensions in viewDimensions[.leading] }
            //.background(item.id == selectedTimelineObjectID ? Color.blue.opacity(0.3) : Color.clear)
                .onTapGesture {
                    withAnimation {
                        onSelectItem(item)
                    }
                }
            
                .listRowBackground(item.id == selectedTimelineObjectID ? Color.blue.opacity(0.3) : Color.clear)
            
        }
        .refreshable { 
            onRefresh()
        }
        .listStyle(PlainListStyle())
    }
}
