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

    private var settings = VoiceFlowSettings.defaults
    /// Created per dictation so it always uses the current settings and vocabulary.
    private var speechEngine: AppleSpeechEngine?
    private var sharedStoreClient: SharedStoreClient?
    private var vocabularyStore: VocabularyStore?
    private var historyStore: DictationHistoryStore?
    private var editWatchStore: KeyboardEditWatchStore?
    /// Vocabulary loaded at dictation start; applied to the result before review.
    private var vocabulary: [VocabularyEntry] = []
    private var currentRecord: DictationRecord?
    private var editWatch: KeyboardEditWatch?
    /// One-off message in the idle state, e.g. after learning from an edit.
    private var notice: String?
    private var pendingInsert: PendingInsert?
    private var shellState: KeyboardShellState = .compact(hasPendingInsert: false) {
        didSet { render() }
    }
    private var recordingStartDate: Date?
    private var elapsedTimer: Timer?
    /// Last dictated or pending text; the clipboard fallback copies this.
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

        sharedStoreClient = try? SharedStoreClient()
        vocabularyStore = try? VocabularyStore.appGroup()
        historyStore = try? DictationHistoryStore.appGroup()
        editWatchStore = try? KeyboardEditWatchStore.appGroup()
        settings = (try? SettingsStore.appGroup())?.load() ?? .defaults
        editWatch = try? editWatchStore?.current()
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
        if speechEngine?.isRecording != true {
            settings = (try? SettingsStore.appGroup())?.load() ?? settings
        }
        refreshPendingInsert()
        learnFromPostEdit()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The keyboard must release the audio session before dismissal. Finish instead of
        // cancelling so the dictated text is waiting in Review when the keyboard returns.
        if case .recording = shellState {
            stopRecording()
        }
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
        if case .compact = shellState, let notice {
            detailLabel.text = notice
        } else {
            detailLabel.text = viewModel.detail
        }
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
            showStoreUnavailableIfIdle()
            return
        }

        do {
            pendingInsert = try sharedStoreClient.pendingInsertForKeyboard()
        } catch {
            pendingInsert = nil
            showStoreUnavailableIfIdle()
            return
        }

        if case .compact = shellState {
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    /// Store errors must not tear down an active dictation; only the idle UI reflects them.
    private func showStoreUnavailableIfIdle() {
        if case .compact = shellState {
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
        }
    }

    private func startElapsedTimer() {
        recordingStartDate = Date()
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickElapsedTime()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func tickElapsedTime() {
        switch shellState {
        case .recording(_, let partialText):
            shellState = .recording(elapsedSeconds: elapsedSeconds, partialText: partialText)
        case .transcribing:
            shellState = .transcribing(elapsedSeconds: elapsedSeconds)
        default:
            stopElapsedTimer()
        }
    }

    private var elapsedSeconds: Int {
        guard let recordingStartDate else { return 0 }
        return max(0, Int(Date().timeIntervalSince(recordingStartDate)))
    }

    // MARK: - Actions

    @objc private func primaryActionTapped() {
        notice = nil
        switch shellState {
        case .compact, .dictationUnavailable:
            startDictation()

        case .recording:
            stopRecording()

        case .transcribing:
            break

        case .reviewing(let text, _):
            if let inserted = insert(text) {
                didInsertDictation(inserted)
                latestReviewText = ""
                shellState = .compact(hasPendingInsert: pendingInsert != nil)
            }

        case .pending(let text):
            guard let pendingInsert else {
                shellState = .compact(hasPendingInsert: false)
                return
            }

            if insert(text) != nil {
                consume(pendingInsert)
                latestReviewText = ""
                shellState = .compact(hasPendingInsert: self.pendingInsert != nil)
            }

        case .insertUnavailable:
            if !latestReviewText.isEmpty {
                UIPasteboard.general.string = latestReviewText
            }
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    @objc private func secondaryActionTapped() {
        notice = nil
        switch shellState {
        case .compact:
            if let pendingInsert {
                latestReviewText = pendingInsert.text
                shellState = .pending(preview: pendingInsert.text)
            }

        case .pending:
            if let pendingInsert {
                guard consume(pendingInsert) else { return }
            }
            latestReviewText = ""
            shellState = .compact(hasPendingInsert: false)

        case .recording, .transcribing:
            stopElapsedTimer()
            speechEngine?.cancel()
            shellState = .compact(hasPendingInsert: pendingInsert != nil)

        case .reviewing, .insertUnavailable, .dictationUnavailable:
            stopElapsedTimer()
            shellState = .compact(hasPendingInsert: pendingInsert != nil)
        }
    }

    // MARK: - Dictation

    private func startDictation() {
        guard hasFullAccess else {
            shellState = .insertUnavailable(reason: .openAccessRequired)
            return
        }

        levelMeter.progress = 0
        startElapsedTimer()
        shellState = .recording(elapsedSeconds: 0)

        vocabulary = (try? vocabularyStore?.entries()) ?? []
        let engine = AppleSpeechEngine(settings: settings)
        engine.delegate = self
        engine.contextualStrings = VocabularyCorrector.recognitionHints(from: vocabulary)
        speechEngine = engine

        let locale = AppleSpeechEngine.resolvedLocale(for: settings)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start(locale: locale)
                // The user may have cancelled while permissions were being requested.
                guard case .recording = self.shellState else {
                    engine.cancel()
                    return
                }
            } catch {
                guard case .recording = self.shellState else { return }
                self.showDictationError(error)
            }
        }
    }

    private func stopRecording() {
        shellState = .transcribing(elapsedSeconds: elapsedSeconds)

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let engine = self.speechEngine else { return }
                let result = try await engine.stop()
                guard case .transcribing = self.shellState else { return }
                self.showReview(
                    text: result.text,
                    localeIdentifier: result.localeIdentifier,
                    durationMs: result.durationMs,
                    error: .recognitionFailed("No speech recognized")
                )
            } catch SpeechEngineError.cancelled {
                return
            } catch {
                guard case .transcribing = self.shellState else { return }
                self.showDictationError(error)
            }
        }
    }

    private func showReview(text: String, localeIdentifier: String? = nil, durationMs: Int? = nil, error: SpeechEngineError) {
        stopElapsedTimer()

        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            shellState = .dictationUnavailable(error: error)
            return
        }

        let corrected = VocabularyCorrector.apply(vocabulary, to: raw)
        try? vocabularyStore?.recordUse(of: corrected.appliedEntryIDs)
        let record = DictationRecord(
            sourceLocale: localeIdentifier ?? AppleSpeechEngine.resolvedLocale(for: settings).identifier,
            rawText: raw,
            processedText: corrected.text,
            correctionLevel: settings.correctionLevel,
            durationMs: durationMs ?? elapsedSeconds * 1_000,
            wordCount: corrected.text.split(whereSeparator: \.isWhitespace).count,
            state: .readyForReview
        )
        currentRecord = record
        try? historyStore?.upsert(record)

        latestReviewText = corrected.text
        shellState = .reviewing(preview: corrected.text, elapsedSeconds: elapsedSeconds)
    }

    // MARK: - Learning

    private func didInsertDictation(_ insertedText: String) {
        guard var record = currentRecord else { return }
        record.state = .inserted
        record.insertedAt = Date()
        try? historyStore?.upsert(record)
        currentRecord = nil

        guard settings.learnFromKeyboardEdits else { return }
        let watch = KeyboardEditWatch(
            dictationID: record.id,
            insertedText: insertedText.trimmingCharacters(in: .whitespacesAndNewlines),
            insertedAt: Date()
        )
        editWatch = watch
        try? editWatchStore?.set(watch)
    }

    /// When the keyboard comes back after the user edited our insertion with another keyboard,
    /// compare the edit with what we inserted and store new vocabulary suggestions.
    /// Only the inserted text and its edited counterpart are used; nothing else is kept.
    private func learnFromPostEdit() {
        guard let watch = editWatch else { return }
        guard settings.learnFromKeyboardEdits, !watch.isExpired(at: Date()) else {
            clearEditWatch()
            return
        }

        let proxy = textDocumentProxy
        let context = (proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? "")
        guard let edited = VocabularyLearner.editedSegment(inserted: watch.insertedText, context: context) else {
            return // Unchanged so far, or a different field: keep watching until it expires.
        }

        clearEditWatch()
        let candidates = VocabularyLearner.candidates(raw: watch.insertedText, corrected: edited)

        if var record = (try? historyStore?.records())?.first(where: { $0.id == watch.dictationID }) {
            record.editedText = edited
            try? historyStore?.upsert(record)
        }

        guard let suggestions = try? vocabularyStore?.addSuggestions(candidates, source: .keyboardEdit), !suggestions.isEmpty else {
            return
        }
        notice = suggestions.count == 1
            ? "Learned 1 new word. Review it in the VoiceFlow app."
            : "Learned \(suggestions.count) new words. Review them in the VoiceFlow app."
        render()
    }

    private func clearEditWatch() {
        editWatch = nil
        try? editWatchStore?.set(nil)
    }

    private func showDictationError(_ error: Error) {
        stopElapsedTimer()
        shellState = .dictationUnavailable(error: (error as? SpeechEngineError) ?? .recognitionFailed(error.localizedDescription))
    }

    // MARK: - Insert

    /// Inserts `text` with one `insertText` call (single undo step). Falls back to the
    /// clipboard if the host silently drops the text. Returns the inserted text, or `nil`.
    private func insert(_ text: String) -> String? {
        let proxy = textDocumentProxy
        let beforeInput = proxy.documentContextBeforeInput
        let planned = InsertContextPlanner.plan(
            text: text,
            context: InsertContext(beforeInput: beforeInput, afterInput: proxy.documentContextAfterInput)
        )

        guard !planned.text.isEmpty else { return nil }

        proxy.insertText(planned.text)

        switch InsertVerifier.verify(
            beforeInsert: beforeInput,
            afterInsert: proxy.documentContextBeforeInput,
            insertedText: planned.text
        ) {
        case .inserted, .unverifiable:
            return planned.text
        case .rejected:
            UIPasteboard.general.string = text
            latestReviewText = text
            shellState = .insertUnavailable(reason: .unknown)
            return nil
        }
    }

    @discardableResult
    private func consume(_ pendingInsert: PendingInsert) -> Bool {
        do {
            try sharedStoreClient?.consumePendingInsert(generation: pendingInsert.generation)
            self.pendingInsert = nil
            return true
        } catch {
            shellState = .insertUnavailable(reason: .sharedStoreUnavailable)
            return false
        }
    }
}

extension KeyboardViewController: SpeechEngineDelegate {
    func speechEngine(_ engine: SpeechEngine, didUpdatePartialText text: String) {
        guard case .recording(let elapsedSeconds, _) = shellState else { return }
        latestReviewText = text
        shellState = .recording(elapsedSeconds: elapsedSeconds, partialText: text)
    }

    func speechEngine(_ engine: SpeechEngine, didUpdateInputLevel level: Float) {
        levelMeter.progress = level
    }

    func speechEngine(_ engine: SpeechEngine, didEndUnexpectedly error: SpeechEngineError, partialText: String) {
        switch shellState {
        case .recording, .transcribing:
            // Never drop recognized text: let the user decide to insert or cancel.
            showReview(text: partialText, error: error)
        default:
            break
        }
    }
}
