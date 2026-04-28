//
//  ContentView.swift
//  VoiceFlow
//
//  Created by Stephan Reiter on 2026-04-28.
//

import SwiftUI
import VoiceFlowShared

private let voiceFlowSharedLinkCheck = VoiceFlowSettings.defaults

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .accessibilityIdentifier(VoiceFlowConstants.appGroupIdentifier)
    }
}

#Preview {
    ContentView()
}
