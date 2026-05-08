//
//  FirepowerActivityKitBundle.swift
//  FirepowerActivityKit
//
//  Created by Blake Nelson on 5/6/26.
//

import WidgetKit
import SwiftUI

@main
struct FirepowerActivityKitBundle: WidgetBundle {
    var body: some Widget {
        FirepowerActivityKit()
        FirepowerActivityKitControl()
        FirepowerWidget()
//        FirepowerActivityKitLiveActivity()
    }
}
