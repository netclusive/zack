/// The last moments of audio from a warm input. Memory only, continuously overwritten; it becomes audio of a
/// recording only when one starts, and is never recognised, logged or stored on its own.
struct PreRoll: Sendable {
    let capacity: Int
    let sampleRate: Double
    private(set) var samples: [Float] = []

    init(duration: Duration, sampleRate: Double = 16_000) {
        capacity = max(0, Int((duration / .seconds(1) * sampleRate).rounded()))
        self.sampleRate = sampleRate
    }

    /// Keeps only the newest `capacity` samples.
    mutating func append(_ chunk: [Float]) {
        guard capacity > 0 else { return }
        if chunk.count >= capacity {
            samples = Array(chunk.suffix(capacity))
            return
        }
        samples.append(contentsOf: chunk)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    /// Frees the storage too, so no audio stays allocated after a release.
    mutating func removeAll() {
        samples = []
    }

    var duration: Duration { .seconds(Double(samples.count) / sampleRate) }
}
