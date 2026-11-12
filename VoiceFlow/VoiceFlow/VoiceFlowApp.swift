//
//  VoiceFlowApp.swift
//  VoiceFlow
//
//  Created by Stephan Reiter on 2026-04-28.
//

import SwiftUI

@main
struct VoiceFlowApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
