//
//  Lockscreen_WidgetsLiveActivity.swift
//  Lockscreen Widgets
//
//  Created by Marco Carandente on 8.5.2024.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Lockscreen_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Lockscreen_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Lockscreen_WidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Lockscreen_WidgetsAttributes {
    fileprivate static var preview: Lockscreen_WidgetsAttributes {
        Lockscreen_WidgetsAttributes(name: "World")
    }
}

extension Lockscreen_WidgetsAttributes.ContentState {
    fileprivate static var smiley: Lockscreen_WidgetsAttributes.ContentState {
        Lockscreen_WidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Lockscreen_WidgetsAttributes.ContentState {
         Lockscreen_WidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Lockscreen_WidgetsAttributes.preview) {
   Lockscreen_WidgetsLiveActivity()
} contentStates: {
    Lockscreen_WidgetsAttributes.ContentState.smiley
    Lockscreen_WidgetsAttributes.ContentState.starEyes
}
