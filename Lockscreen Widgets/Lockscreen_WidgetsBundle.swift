//
//  Lockscreen_WidgetsBundle.swift
//  Lockscreen Widgets
//
//  Created by Marco Carandente on 8.5.2024.
//

import WidgetKit
import SwiftUI

@main
struct Lockscreen_WidgetsBundle: WidgetBundle {
    var body: some Widget {
        Lockscreen_Widgets()
        Lockscreen_WidgetsLiveActivity()
    }
}
