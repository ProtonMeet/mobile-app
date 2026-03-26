//
//  CallActivityWidgetBundle.swift
//  CallActivityWidget
//
//  Created by Yanfeng Zhang on 11/10/25.
//

import WidgetKit
import SwiftUI

@main
struct CallActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        CallActivityWidget()
        CallActivityWidgetControl()
//        CallActivityWidgetLiveActivity()
    }
}
