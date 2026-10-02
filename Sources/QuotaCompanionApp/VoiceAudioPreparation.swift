@preconcurrency import AVFoundation
import AppKit
import Combine

struct PreparedVoiceAudio: Sendable {
    let url: URL
    let duration: Double
    let bytes: Int
    let audibleSeconds: Double
}
enum VoiceAudioPreparation {
    static func validate(duration: Double, bytes: Int, provider: APIProvider) throws {
        guard duration.isFinite, duration >= (provider == .bailian ? 3 : 10), duration <= (provider == .bailian ? 60 : 300) else { throw VoiceCloneError.duration }
        guard bytes > 0, bytes <= (provider == .bailian ? 10 : 20) * 1024 * 1024 else { throw VoiceCloneError.tooLarge }
    }
    static func prepare(source: URL, destination: URL, provider: APIProvider) throws -> PreparedVoiceAudio {
        guard ["wav", "mp3", "m4a"].contains(source.pathExtension.lowercased()) else { throw VoiceCloneError.invalidAudio }
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= (provider == .bailian ? 10 : 20) * 1024 * 1024 else { throw VoiceCloneError.tooLarge }
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch { throw VoiceCloneError.invalidAudio }
        let duration = Double(input.length) / input.processingFormat.sampleRate
        try validate(duration: duration, bytes: bytes, provider: provider)
        guard input.processingFormat.channelCount <= 2,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw VoiceCloneError.invalidAudio }
        let output = try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        var readError: Error?, audibleFrames = 0, maxContinuous = 0, continuous = 0
        while true {
            try Task.checkCancellation()
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { count, inputStatus in
                do {
                    let remaining = input.length - input.framePosition
                    guard remaining > 0 else { inputStatus.pointee = .endOfStream; return nil }
                    try input.read(into: buffer, frameCount: min(count, buffer.frameCapacity, AVAudioFrameCount(min(remaining, Int64(UInt32.max)))))
                    inputStatus.pointee = buffer.frameLength == 0 ? .endOfStream : .haveData
                    return buffer.frameLength == 0 ? nil : buffer
                } catch { readError = error; inputStatus.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            if let error { throw error }
            if let channel = converted.floatChannelData?[0] {
                // 20 ms RMS windows detect silence, not identity, speech or background noise.
                for start in stride(from: 0, to: Int(converted.frameLength), by: 480) {
                    let end = min(Int(converted.frameLength), start + 480)
                    let energy = (start..<end).reduce(0.0) { $0 + Double(channel[$1] * channel[$1]) } / Double(end-start)
                    if energy > 0.00001 { audibleFrames += end-start; continuous += end-start; maxContinuous = max(maxContinuous, continuous) }
                    else { continuous = 0 }
                }
            }
            if converted.frameLength > 0 { try output.write(from: converted) }
            if status == .endOfStream { break }
            if status == .error { throw VoiceCloneError.invalidAudio }
        }
        let audibleSeconds = Double(audibleFrames) / 24000
        guard audibleSeconds >= 3 else { throw VoiceCloneError.silent }
        let outputBytes = Int(output.length) * 2 + 44
        try validate(duration: duration, bytes: outputBytes, provider: provider)
        return .init(url: destination, duration: duration, bytes: outputBytes, audibleSeconds: audibleSeconds)
    }
}

/// Session operations are serialized away from the UI thread.
private final class VoiceCaptureHardware: @unchecked Sendable {
    let session = AVCaptureSession()
    let output = AVCaptureAudioFileOutput()
    let queue = DispatchQueue(label: "dev.quota-companion.voice-recording")
    func stop() { queue.async { self.output.stopRecording(); self.session.stopRunning() } }
}
@MainActor final class VoiceRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    struct Input: Identifiable { let id: String; let name: String }
    @Published private(set) var inputs: [Input] = []
    @Published var inputID = ""
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var finishing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var level: Double = 0
    @Published var error: String?
    var completed: ((URL) -> Void)?
    private var hardware: VoiceCaptureHardware?
    private var timer: Timer?
    private var generation = UUID()
    private var recordingURL: URL?
    private var player: AVAudioPlayer?
    var permissionForTesting: (@Sendable () async -> Bool)?
    override init() { super.init(); refreshInputs() }
    func refreshInputs() {
        inputs = AVCaptureDevice.devices(for: .audio).map { Input(id: $0.uniqueID, name: $0.localizedName) }
        if !inputs.contains(where: { $0.id == inputID }) { inputID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? inputs.first?.id ?? "" }
    }
    func start(url: URL, copy: Copybook) {
        guard !recording, !starting, !finishing else { return }
        player?.stop(); starting = true; error = nil
        let token = UUID(); generation = token
        Task { [weak self] in
            guard let self else { return }
            let allowed: Bool
            if let permissionForTesting { allowed = await permissionForTesting() }
            else {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: allowed = true
                case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
                default: allowed = false
                }
            }
            guard generation == token else { return }
            guard allowed else { starting = false; error = VoiceCloneError.microphone.message(copy); return }
            guard let device = AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == inputID }) else { starting = false; error = VoiceCloneError.device.message(copy); return }
            let box = VoiceCaptureHardware(); hardware = box; recordingURL = url
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard box.session.canAddInput(input), box.session.canAddOutput(box.output) else { throw VoiceCloneError.device }
                box.session.addInput(input); box.session.addOutput(box.output)
                elapsed = 0; level = 0; recording = true; starting = false
                box.queue.async { [weak self] in
                    box.session.startRunning()
                    guard let self else { box.stop(); return }
                    box.output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
                }
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.elapsed += 0.1
                        let power = box.output.connections.flatMap(\.audioChannels).map(\.averagePowerLevel).max() ?? -80
                        self.level = max(0, min(1, (Double(power)+60)/60))
                        if !device.isConnected { self.error = VoiceCloneError.device.message(copy); self.stop() }
                        else if self.elapsed >= 60 { self.stop() }
                    }
                }
            } catch { starting = false; recording = false; self.error = VoiceCloneError.device.message(copy) }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; if recording { finishing = true }; hardware?.stop(); recording = false; level = 0 }
    func cancel() { generation = UUID(); recordingURL = nil; completed = nil; stop(); starting = false; finishing = false; player?.stop(); player = nil }
    func play(_ url: URL) throws { player?.stop(); let value = try AVAudioPlayer(contentsOf: url); guard value.play() else { throw CloudSpeechError.audio }; player = value }
    func stopPlayback() { player?.stop() }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self, recordingURL == outputFileURL else { return }
            stop(); hardware = nil; finishing = false
            if failed { self.error = VoiceCloneError.device.message(Copybook(language: .system)) }
            else { completed?(outputFileURL) }
        }
    }
}
