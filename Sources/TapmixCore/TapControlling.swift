import CoreAudio
import Foundation

protocol TapControlling: AnyObject {
    var processObjectID: AudioObjectID { get }
    var bundleID: String { get }
    var createdAt: Date { get }
    var callbackCount: UInt64 { get }
    /// True while this tap is writing a WAV.
    var isRecording: Bool { get }
    func start() throws
    func stop()
    func setGain(_ gain: Float)
    func setEQ(_ settings: EQSettings)
    func setNightMode(_ enabled: Bool)
    func setBalance(_ balance: Float)
    func setMono(_ enabled: Bool)
    func setAudioUnit(_ selection: AudioUnitSelection?)
    func startRecording(to url: URL) throws
    func stopRecording()
    /// Returns the peak since the previous call and resets it.
    func takePeakLevel() -> Float
}
