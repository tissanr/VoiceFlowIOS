//
//  ContentView.swift
//  VoiceFlow
//
//  Created by Stephan Reiter on 2026-04-28.
//

import SwiftUI
import VoiceFlowShared

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            DictationView()
                .tabItem { Label("Dictate", systemImage: "mic") }
                .tag(AppTab.dictate)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)
            VocabularyView()
                .tabItem { Label("Words", systemImage: "text.book.closed") }
                .badge(model.suggestions.count)
                .tag(AppTab.words)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .accessibilityIdentifier(VoiceFlowConstants.appGroupIdentifier)
        .onOpenURL { url in
            model.lastOpenedURL = url
            model.selectedTab = .dictate
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
