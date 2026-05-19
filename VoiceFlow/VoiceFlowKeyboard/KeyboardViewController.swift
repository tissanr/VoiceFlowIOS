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
    private var sharedStoreClient: SharedStoreClient?
    private var pendingInsert: PendingInsert?
    private var shellState: KeyboardShellState = .compact(hasPendingInsert: false) {
        didSet { render() }
    }
    private var recordingStartDate: Date?
    private var elapsedTimer: Timer?
    private var latestReviewText = ""

    private let rootStackView = UIStackView()
    private let headerStackView = UIStackView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let accessBadgeLabel = UILabel()
    private let previewLabel = UILabel()
    private let levelMeter = UIProgressView(progressViewStyle: .bar)
    private let timerLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        _ = defaultSettings
        recordingSpike.delegate = self
        sharedStoreClient = try? SharedStoreClient()
        configureUI()
        if sharedStoreClient == nil {
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
        } else {
            refreshPendingInsert()
        }
        render()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        recordingSpike.recordLifecycleEvent("keyboard view appeared")
        refreshPendingInsert()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recordingSpike.recordLifecycleEvent("keyboard view disappearing")
        stopElapsedTimer()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        updateColors()
        refreshPendingInsert()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        nextKeyboardButton = UIButton(type: .system)
        if let image = UIImage(systemName: "globe") {
            nextKeyboardButton.setImage(image, for: .normal)
        } else {
            nextKeyboardButton.setTitle("Next", for: .normal)
        }
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.accessibilityLabel = "Next Keyboard"
        nextKeyboardButton.accessibilityHint = "Switches to the next keyboard."
        view.addSubview(nextKeyboardButton)

        rootStackView.axis = .vertical
        rootStackView.alignment = .fill
        rootStackView.spacing = 10
        rootStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStackView)

        headerStackView.axis = .horizontal
        headerStackView.alignment = .firstBaseline
        headerStackView.spacing = 8

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        accessBadgeLabel.font = .preferredFont(forTextStyle: .caption1)
        accessBadgeLabel.adjustsFontForContentSizeCategory = true
        accessBadgeLabel.textAlignment = .right
        accessBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        headerStackView.addArrangedSubview(titleLabel)
        headerStackView.addArrangedSubview(UIView())
        headerStackView.addArrangedSubview(accessBadgeLabel)

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 2

        previewLabel.font = .preferredFont(forTextStyle: .body)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.numberOfLines = 3
        previewLabel.layer.cornerRadius = 8
        previewLabel.layer.masksToBounds = true

        levelMeter.progress = 0.18

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        timerLabel.textAlignment = .center
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let meterRow = UIStackView(arrangedSubviews: [levelMeter, timerLabel])
        meterRow.axis = .horizontal
        meterRow.alignment = .center
        meterRow.spacing = 10
        meterRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

        primaryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        primaryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        primaryButton.addTarget(self, action: #selector(primaryActionTapped), for: .touchUpInside)
        primaryButton.accessibilityHint = "Performs the main VoiceFlow keyboard action."

        secondaryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        secondaryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        secondaryButton.addTarget(self, action: #selector(secondaryActionTapped), for: .touchUpInside)
        secondaryButton.accessibilityHint = "Performs the secondary VoiceFlow keyboard action."

        let buttonRow = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .fill
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 8

        rootStackView.addArrangedSubview(headerStackView)
        rootStackView.addArrangedSubview(detailLabel)
        rootStackView.addArrangedSubview(previewLabel)
        rootStackView.addArrangedSubview(meterRow)
        rootStackView.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            nextKeyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextKeyboardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            rootStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            rootStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            rootStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            rootStackView.bottomAnchor.constraint(lessThanOrEqualTo: nextKeyboardButton.topAnchor, constant: -8),

            primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            secondaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        updateColors()
    }

    private func render() {
        guard isViewLoaded else { return }

        let viewModel = KeyboardShellViewModel(state: shellState)
        titleLabel.text = viewModel.title
        detailLabel.text = viewModel.detail
        accessBadgeLabel.text = hasFullAccess ? "Full Access" : "Handoff Mode"
        previewLabel.text = viewModel.preview
        previewLabel.isHidden = viewModel.preview == nil
        levelMeter.isHidden = !viewModel.showsLevelMeter
        timerLabel.isHidden = viewModel.timerText == nil
        timerLabel.text = viewModel.timerText
        primaryButton.setTitle(viewModel.primaryActionTitle, for: .normal)
        primaryButton.isEnabled = viewModel.primaryActionEnabled
        secondaryButton.setTitle(viewModel.secondaryActionTitle, for: .normal)
        secondaryButton.isHidden = viewModel.secondaryActionTitle == nil
        primaryButton.accessibilityLabel = viewModel.primaryActionTitle
        secondaryButton.accessibilityLabel = viewModel.secondaryActionTitle

        updateColors()
    }

    private func updateColors() {
        let isDark = textDocumentProxy.keyboardAppearance == .dark
        let foregroundColor: UIColor = isDark ? .white : .label
        let secondaryColor: UIColor = isDark ? .lightGray : .secondaryLabel
        let fillColor: UIColor = isDark ? .secondarySystemBackground : .tertiarySystemFill

        titleLabel.textColor = foregroundColor
        detailLabel.textColor = secondaryColor
        accessBadgeLabel.textColor = secondaryColor
        timerLabel.textColor = secondaryColor
        previewLabel.textColor = foregroundColor
        previewLabel.backgroundColor = fillColor
        nextKeyboardButton.tintColor = foregroundColor
        primaryButton.tintColor = .systemBlue
        secondaryButton.tintColor = secondaryColor
    }

    private func refreshPendingInsert() {
        guard let sharedStoreClient else {
            pendingInsert = nil
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
            return
        }

        do {
            pendingInsert = try sharedStoreClient.pendingInsertForKeyboard()
        } catch {
            pendingInsert = nil
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
            return
        }

        if case .compact = shellState {
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    private func startElapsedTimer() {
        recordingStartDate = Date()
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickElapsedTime()
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartDate = nil
    }

    private func tickElapsedTime() {
        guard let recordingStartDate else { return }
        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(recordingStartDate)))

        switch shellState {
        case .recording:
            shellState = .recording(elapsedSeconds: elapsedSeconds)
        case .transcribing:
            shellState = .transcribing(elapsedSeconds: elapsedSeconds)
        case .reviewing(let preview, _):
            shellState = .reviewing(preview: preview, elapsedSeconds: elapsedSeconds)
        default:
            stopElapsedTimer()
        }
    }

    @objc private func primaryActionTapped() {
        switch shellState {
        case .compact:
            guard hasFullAccess else {
                shellState = .insertUnavailable(reason: .openAccessRequired)
                return
            }
            startElapsedTimer()
            shellState = .recording(elapsedSeconds: 0)

        case .recording:
            shellState = .transcribing(elapsedSeconds: elapsedSeconds)

        case .transcribing:
            latestReviewText = pendingInsert?.text ?? "Preview text will appear here after transcription."
            shellState = .reviewing(preview: latestReviewText, elapsedSeconds: elapsedSeconds)

        case .reviewing(let preview, _):
            stopElapsedTimer()
            latestReviewText = preview
            shellState = .pending(preview: preview)

        case .pending(let preview):
            latestReviewText = preview
            shellState = .compact(hasPendingInsert: pendingInsert != nil)

        case .insertUnavailable:
            if !latestReviewText.isEmpty {
                UIPasteboard.general.string = latestReviewText
            }
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    @objc private func secondaryActionTapped() {
        switch shellState {
        case .compact:
            if let pendingInsert {
                latestReviewText = pendingInsert.text
                shellState = .pending(preview: pendingInsert.text)
            }

        case .pending:
            guard discardPendingInsert() else { return }
            pendingInsert = nil
            latestReviewText = ""
            shellState = .compact(hasPendingInsert: false)

        case .recording, .transcribing, .reviewing, .insertUnavailable:
            stopElapsedTimer()
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    private var elapsedSeconds: Int {
        guard let recordingStartDate else { return 0 }
        return max(0, Int(Date().timeIntervalSince(recordingStartDate)))
    }

    private func discardPendingInsert() -> Bool {
        guard let pendingInsert else { return true }

        do {
            try sharedStoreClient?.consumePendingInsert(generation: pendingInsert.generation)
            return true
        } catch {
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
            return false
        }
    }
}

extension KeyboardViewController: KeyboardRecordingSpikeDelegate {
    func keyboardRecordingSpikeDidUpdate(_ snapshot: KeyboardRecordingSpikeSnapshot) {
        levelMeter.progress = snapshot.isRecording ? 0.72 : 0.18

        guard !snapshot.transcript.isEmpty else { return }
        latestReviewText = snapshot.transcript

        if case .recording = shellState {
            shellState = .reviewing(preview: snapshot.transcript, elapsedSeconds: elapsedSeconds)
        }
    }
}
