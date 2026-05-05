//
//  KeyboardViewController.swift
//  VoiceFlowKeyboard
//
//  Created by Stephan Reiter on 2026-04-28.
//

import UIKit
import VoiceFlowShared

final class KeyboardViewController: UIInputViewController {

    @IBOutlet var nextKeyboardButton: UIButton!
    private let defaultSettings = VoiceFlowSettings.defaults
    private let recordingSpike = KeyboardRecordingSpike()
    private let spikeStackView = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let transcriptLabel = UILabel()
    private let metricsLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private let speechButton = UIButton(type: .system)
    private let openAppButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        
        // Add custom view sizing constraints here
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Perform custom UI setup here
        self.nextKeyboardButton = UIButton(type: .system)
        _ = defaultSettings
        recordingSpike.delegate = self
        
        self.nextKeyboardButton.setTitle(NSLocalizedString("Next Keyboard", comment: "Title for 'Next Keyboard' button"), for: [])
        self.nextKeyboardButton.sizeToFit()
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        
        self.view.addSubview(self.nextKeyboardButton)
        
        self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.nextKeyboardButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        configureSpikeUI()
    }
    
    override func viewWillLayoutSubviews() {
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents. Perform any preparation here.
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents, the document context has been updated.
        
        var textColor: UIColor
        let proxy = self.textDocumentProxy
        if proxy.keyboardAppearance == UIKeyboardAppearance.dark {
            textColor = UIColor.white
        } else {
            textColor = UIColor.black
        }
        self.nextKeyboardButton.setTitleColor(textColor, for: [])
    }

    private func configureSpikeUI() {
        view.backgroundColor = .systemBackground

        spikeStackView.axis = .vertical
        spikeStackView.alignment = .fill
        spikeStackView.spacing = 8
        spikeStackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "VoiceFlow Phase 0 Spike"

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.numberOfLines = 2
        
        let fullAccessStatus = hasFullAccess ? "Full Access: ON" : "Full Access: OFF"
        statusLabel.text = "\(fullAccessStatus)\nEnable Full Access to test Deep Link."

        transcriptLabel.font = .preferredFont(forTextStyle: .body)
        transcriptLabel.numberOfLines = 3
        transcriptLabel.text = "In-keyboard recording is the secondary path. Opening the App is the primary MVP path."

        metricsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        metricsLabel.numberOfLines = 5
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.text = "App Group ID: group.com.voiceflow.shared\nURL: voiceflow://"

        recordButton.setTitle("Local Record", for: .normal)
        recordButton.addTarget(self, action: #selector(toggleSpikeRecording), for: .touchUpInside)

        openAppButton.setTitle("🎤 Open VoiceFlow", for: .normal)
        openAppButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        openAppButton.addTarget(self, action: #selector(openMainApp), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelSpikeRecording), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [recordButton, openAppButton, cancelButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fillProportionally
        buttonRow.spacing = 8

        spikeStackView.addArrangedSubview(titleLabel)
        spikeStackView.addArrangedSubview(statusLabel)
        spikeStackView.addArrangedSubview(transcriptLabel)
        spikeStackView.addArrangedSubview(metricsLabel)
        spikeStackView.addArrangedSubview(buttonRow)
        view.addSubview(spikeStackView)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
            spikeStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            spikeStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            spikeStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            spikeStackView.bottomAnchor.constraint(lessThanOrEqualTo: nextKeyboardButton.topAnchor, constant: -12)
        ])

        keyboardRecordingSpikeDidUpdate(recordingSpike.currentSnapshot())
    }

    @objc private func openMainApp() {
        let url = URL(string: "voiceflow://record")!
        
        // Extension context open URL hack
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.perform(#selector(UIApplication.open(_:options:completionHandler:)), with: url, with: nil, with: nil)
                return
            }
            responder = responder?.next
        }
        
        // Fallback using extensionContext (requires Full Access usually)
        extensionContext?.open(url, completionHandler: { success in
            print("Deep link success: \(success)")
        })
    }

    @objc private func toggleSpikeRecording() {
        if recordingSpike.isRecording {
            recordingSpike.stop()
        } else {
            Task { @MainActor in
                await recordingSpike.start(localeIdentifier: "en-US")
            }
        }
    }

    @objc private func attachSpikeSpeech() {
        Task { @MainActor in
            await recordingSpike.attachSpeech(localeIdentifier: "en-US")
        }
    }

    @objc private func cancelSpikeRecording() {
        recordingSpike.cancel()
    }

    private func format(milliseconds: Double?) -> String {
        guard let milliseconds else { return "n/a" }
        return String(format: "%.0f ms", milliseconds)
    }
}

extension KeyboardViewController: KeyboardRecordingSpikeDelegate {
    func keyboardRecordingSpikeDidUpdate(_ snapshot: KeyboardRecordingSpikeSnapshot) {
        statusLabel.text = snapshot.status
        transcriptLabel.text = snapshot.transcript.isEmpty ? "Listening..." : snapshot.transcript
        metricsLabel.text = """
        peak rss: \(String(format: "%.1f MB", snapshot.peakResidentMemoryMB))
        tap -> engine: \(format(milliseconds: snapshot.tapToEngineStartMS))
        tap -> first buffer: \(format(milliseconds: snapshot.tapToFirstAudioBufferMS))
        stop -> final: \(format(milliseconds: snapshot.stopToFinalResultMS))
        """
        recordButton.setTitle(snapshot.isRecording ? "Stop Recording" : "Start Spike Recording", for: .normal)
    }
}
