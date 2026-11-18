import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class AudioRecorderManager: NSObject {
    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var hasRecordedMemo = false
    private(set) var permissionDenied = false
    private(set) var recordedAudioData: Data?
    var errorMessage: String?

    @ObservationIgnored private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var currentRecordingURL: URL?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        observeAudioInterruptions()
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @ObservationIgnored private var isHoldActive = false

    /// Called on every touch event of the hold-to-record gesture; only the first call of a hold starts recording.
    /// Permission is asynchronous, so the hold may already be released (e.g. the user lifted their finger to tap
    /// "Allow" on the system prompt) by the time it resolves — in that case recording is NOT started, otherwise
    /// it would run forever with no gesture left to stop it.
    func beginHoldToRecord() {
        guard !isHoldActive, !isRecording else { return }
        isHoldActive = true
        Task {
            let granted = await requestMicrophonePermission()
            guard granted else {
                isHoldActive = false
                permissionDenied = true
                errorMessage = String(localized: "Microphone access is required to dictate defect findings.")
                return
            }
            permissionDenied = false
            guard isHoldActive, !isRecording else { return }
            startRecording()
        }
    }

    func endHoldToRecord() {
        isHoldActive = false
        if isRecording {
            stopRecording()
        }
    }

    func requestPermissionAndStartRecording() {
        beginHoldToRecord()
    }

    func startRecording() {
        stopPlayback()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            errorMessage = String(localized: "Audio session error: \(error.localizedDescription)")
            return
        }

        // Re-recording without "Re-record" first: drop the previous temp file so memos don't leak in tmp/.
        if let previousURL = currentRecordingURL {
            try? FileManager.default.removeItem(at: previousURL)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("defect_memo_\(UUID().uuidString).m4a")
        currentRecordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            if recorder.record() {
                audioRecorder = recorder
                isRecording = true
                errorMessage = nil
            } else {
                errorMessage = String(localized: "Unable to start voice recording.")
            }
        } catch {
            errorMessage = String(localized: "Recorder setup failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        isHoldActive = false
        guard isRecording, let recorder = audioRecorder else { return }
        recorder.stop()
        isRecording = false
        audioRecorder = nil

        if let url = currentRecordingURL, let data = try? Data(contentsOf: url), !data.isEmpty {
            recordedAudioData = data
            hasRecordedMemo = true
        }
        deactivateSession()
    }

    func clearMemo() {
        stopPlayback()
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        recordedAudioData = nil
        hasRecordedMemo = false
    }

    func togglePlayback(data: Data? = nil) {
        if isPlaying {
            stopPlayback()
            return
        }

        guard let audioData = data ?? recordedAudioData else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.prepareToPlay()
            if player.play() {
                audioPlayer = player
                isPlaying = true
            }
        } catch {
            errorMessage = String(localized: "Playback failed: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        deactivateSession()
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard
                let userInfo = notification.userInfo,
                let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    if self.isRecording {
                        self.stopRecording()
                    }
                    if self.isPlaying {
                        self.stopPlayback()
                    }
                }
            }
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.isRecording = false
                self.errorMessage = String(localized: "Recording ended unexpectedly.")
            }
        }
    }
}

extension AudioRecorderManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.deactivateSession()
        }
    }
}
