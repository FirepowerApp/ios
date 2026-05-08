//
//  FirepowerActivityKitLiveActivity.swift
//  FirepowerActivityKit
//
//  Created by Blake Nelson on 5/6/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FirepowerActivityKitAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FirepowerActivityKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FirepowerActivityKitAttributes.self) { context in
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

extension FirepowerActivityKitAttributes {
    fileprivate static var preview: FirepowerActivityKitAttributes {
        FirepowerActivityKitAttributes(name: "World")
    }
}

extension FirepowerActivityKitAttributes.ContentState {
    fileprivate static var smiley: FirepowerActivityKitAttributes.ContentState {
        FirepowerActivityKitAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FirepowerActivityKitAttributes.ContentState {
         FirepowerActivityKitAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FirepowerActivityKitAttributes.preview) {
   FirepowerActivityKitLiveActivity()
} contentStates: {
    FirepowerActivityKitAttributes.ContentState.smiley
    FirepowerActivityKitAttributes.ContentState.starEyes
}
