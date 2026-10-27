import CoreAudio
import Foundation

protocol TapControlling: AnyObject {
    var processObjectID: AudioObjectID { get }
    var bundleID: String { get }
    var createdAt: Date { get }
    var callbackCount: UInt64 { get }
    func start() throws
    func stop()
    func setGain(_ gain: Float)
    func setEQ(_ settings: EQSettings)
    func setNightMode(_ enabled: Bool)
    /// Returns the peak since the previous call and resets it.
    func takePeakLevel() -> Float
}
