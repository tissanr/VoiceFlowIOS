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
    @State private var lastOpenedURL: URL?

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text(lastOpenedURL.map { "Opened URL: \($0.absoluteString)" } ?? "No deep link received")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityIdentifier(VoiceFlowConstants.appGroupIdentifier)
        .onOpenURL { url in
            lastOpenedURL = url
        }
    }
}

#Preview {
    ContentView()
}
