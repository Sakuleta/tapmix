import Foundation

/// Records the post-processing stereo output of one tap as 16-bit PCM WAV.
/// `write` only appends to a preallocated ring buffer; file I/O happens on a
/// utility queue.
final class TapRecorder {
    private let fileHandle: FileHandle
    private let sampleRate: Double
    private let capacityFrames: Int
    private let buffer: UnsafeMutablePointer<Float>
    private let queue = DispatchQueue(label: "com.mardinli.tapmix.recorder", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var writeIndex = 0
    private var readIndex = 0
    private var framesWritten: UInt32 = 0
    private(set) var isActive = true

    init(url: URL, sampleRate: Double) throws {
        self.sampleRate = max(sampleRate, 8_000)
        capacityFrames = max(1_024, Int(self.sampleRate * 4))
        buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacityFrames * 2)
        buffer.initialize(repeating: 0, count: capacityFrames * 2)

        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        guard manager.createFile(atPath: url.path, contents: nil) else {
            buffer.deinitialize(count: capacityFrames * 2)
            buffer.deallocate()
            throw CocoaError(.fileWriteUnknown)
        }
        fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.write(Self.header(sampleRate: self.sampleRate, dataSize: 0))

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.1, repeating: 0.1)
        source.setEventHandler { [weak self] in
            self?.drain()
        }
        source.resume()
        timer = source
    }

    deinit {
        stop()
        buffer.deinitialize(count: capacityFrames * 2)
        buffer.deallocate()
    }

    /// Realtime-safe append. Drops frames if the writer falls more than four
    /// seconds behind.
    @inline(__always)
    func write(left: Float, right: Float) {
        guard isActive else { return }
        let next = (writeIndex + 1) % capacityFrames
        guard next != readIndex else { return }

        let base = writeIndex * 2
        buffer[base] = left
        buffer[base + 1] = right
        writeIndex = next
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        timer?.cancel()
        timer = nil
        queue.sync { drain() }

        let dataSize = framesWritten * 4
        patchHeader(dataSize: dataSize)
        try? fileHandle.close()
    }

    private func drain() {
        var data = Data()
        data.reserveCapacity(4_096)

        while readIndex != writeIndex {
            let base = readIndex * 2
            append(buffer[base], to: &data)
            append(buffer[base + 1], to: &data)
            readIndex = (readIndex + 1) % capacityFrames
        }

        if !data.isEmpty {
            fileHandle.write(data)
            framesWritten += UInt32(data.count / 4)
        }
    }

    @inline(__always)
    private func append(_ sample: Float, to data: inout Data) {
        let clamped = min(max(sample, -1), 1)
        var value = Int16(clamped * 32_767).littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func patchHeader(dataSize: UInt32) {
        var riffSize = (36 + dataSize).littleEndian
        var size = dataSize.littleEndian
        try? fileHandle.seek(toOffset: 4)
        fileHandle.write(Data(bytes: &riffSize, count: 4))
        try? fileHandle.seek(toOffset: 40)
        fileHandle.write(Data(bytes: &size, count: 4))
    }

    private static func header(sampleRate: Double, dataSize: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data) // PCM
        append(UInt16(2), to: &data) // stereo
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 4), to: &data)
        append(UInt16(4), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize, to: &data)
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
