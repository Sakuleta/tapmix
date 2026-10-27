import CoreAudio
import Foundation
import Synchronization

/// Records the post-processing stereo output of one tap as 16-bit PCM WAV.
/// `write` only appends to a preallocated ring buffer; file I/O happens on a
/// utility queue. Indices cross the realtime boundary as atomics: the writer
/// releases frames with the write index, the drainer acknowledges with the read
/// index.
final class TapRecorder {
    private let fileHandle: FileHandle
    private let sampleRate: Double
    private let capacityFrames: Int
    private let buffer: UnsafeMutablePointer<Float>
    private let queue = DispatchQueue(label: "com.mardinli.tapmix.recorder", qos: .utility)
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let active = Atomic<Bool>(true)
    private let maxFrames: UInt32
    private var timer: DispatchSourceTimer?
    private var framesWritten: UInt32 = 0
    private var fileClosed = false

    var isActive: Bool { active.load(ordering: .acquiring) }

    /// `maxFrames` is a test seam; the default keeps the 32-bit WAV data chunk
    /// inside `UInt32` (about 6.2 hours of stereo at 48 kHz).
    init(
        url: URL,
        sampleRate: Double,
        maxFrames: UInt32 = UInt32.max / 4
    ) throws {
        self.sampleRate = max(sampleRate, 8_000)
        self.maxFrames = max(maxFrames, 1)
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

        let write = writeIndex.load(ordering: .relaxed)
        let next = (write + 1) % capacityFrames
        guard next != readIndex.load(ordering: .acquiring) else { return }

        buffer[write * 2] = left
        buffer[write * 2 + 1] = right
        writeIndex.store(next, ordering: .releasing)
    }

    /// Realtime-safe append of one rendered buffer, planar or interleaved.
    /// Channels past the first two are ignored.
    @inline(__always)
    func write(bufferList: UnsafeMutablePointer<AudioBufferList>) {
        guard isActive else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

        var leftBase: UnsafeMutablePointer<Float>?
        var rightBase: UnsafeMutablePointer<Float>?
        var leftStride = 1
        var rightStride = 1
        var globalChannel = 0
        var frames = capacityFrames

        for buffer in buffers {
            let channels = max(1, Int(buffer.mNumberChannels))
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                if globalChannel == 0 {
                    leftBase = data
                    leftStride = channels
                }
                if globalChannel <= 1, globalChannel + channels > 1 {
                    rightBase = data.advanced(by: 1 - globalChannel)
                    rightStride = channels
                }
            }
            globalChannel += channels
        }

        guard let leftBase, frames > 0 else { return }

        var write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        for frame in 0 ..< frames {
            let next = (write + 1) % capacityFrames
            guard next != read else { break }

            let left = leftBase[frame * leftStride]
            let right = rightBase?[frame * rightStride] ?? left
            buffer[write * 2] = left
            buffer[write * 2 + 1] = right
            write = next
        }
        writeIndex.store(write, ordering: .releasing)
    }

    func stop() {
        guard active.exchange(false, ordering: .acquiringAndReleasing) else { return }
        queue.sync {
            timer?.cancel()
            timer = nil
            drain()
            finish()
        }
    }

    private func drain() {
        guard !fileClosed else { return }

        var read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read != write else { return }

        let remaining = framesWritten < maxFrames ? maxFrames - framesWritten : 0
        guard remaining > 0 else {
            finish()
            return
        }

        var data = Data()
        data.reserveCapacity(4_096)
        var frames: UInt32 = 0

        while read != write, frames < remaining {
            let base = read * 2
            append(buffer[base], to: &data)
            append(buffer[base + 1], to: &data)
            read = (read + 1) % capacityFrames
            frames += 1
        }
        readIndex.store(read, ordering: .releasing)

        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            // A full disk must not take the app down mid-recording.
            finish()
            return
        }

        framesWritten += frames
        if framesWritten >= maxFrames {
            finish()
        }
    }

    /// Closes the file exactly once, from the recorder queue.
    private func finish() {
        guard !fileClosed else { return }
        fileClosed = true
        timer?.cancel()
        timer = nil
        active.store(false, ordering: .releasing)
        patchHeader(dataSize: framesWritten * 4)
        try? fileHandle.close()
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
