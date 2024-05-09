//
//  Lockscreen_Widgets.swift
//  Lockscreen Widgets
//
//  Created by Marco Carandente on 8.5.2024.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    let userDefaults = UserDefaults(suiteName: "group.DeltaCygniLabs.Life2Gpx")
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lastUpdateTimestamp: userDefaults?.object(forKey: "lastUpdateTimestamp") as? Date, lastUpdateType: userDefaults?.string(forKey: "lastUpdateType"))

    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), lastUpdateTimestamp: userDefaults?.object(forKey: "lastUpdateTimestamp") as? Date, lastUpdateType: userDefaults?.string(forKey: "lastUpdateType"))
           completion(entry)
    }
    
    
     func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
         let currentDate = Date()
         let refreshDate = Calendar.current.date(byAdding: .minute, value: 3, to: currentDate)!
         let entry = SimpleEntry(date: currentDate, lastUpdateTimestamp: userDefaults?.object(forKey: "lastUpdateTimestamp") as? Date, lastUpdateType: userDefaults?.string(forKey: "lastUpdateType"))

         let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
         completion(timeline)
     }

}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let lastUpdateTimestamp: Date?
    let lastUpdateType: String?
}

struct Lockscreen_WidgetsEntryView : View {
    @Environment(\.widgetFamily) var widgetFamily
    var entry: Provider.Entry
    
    var body: some View {
        switch widgetFamily
        {
        case .accessoryRectangular:
            VStack {
               if let timestamp = entry.lastUpdateTimestamp {
                   if let lastUpdateType = entry.lastUpdateType{
                       Text("\(lastUpdateType)")
                           .font(.caption)
                   }
                   Text("\(timestamp, formatter: dateFormatter)")
                       .font(.caption)
               } else {
                   Text("Last update not available")
               }
           }
        default:
            Text("Not implemented")
        }
    }
}
struct Lockscreen_Widgets: Widget {
    let kind: String = "Lockscreen_Widgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Lockscreen_WidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.accessoryRectangular])
    }
}
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

#Preview(as: .accessoryRectangular) {
    Lockscreen_Widgets()
} timeline: {
    SimpleEntry(date: .now, lastUpdateTimestamp: .now, lastUpdateType: "Cycling")
}
