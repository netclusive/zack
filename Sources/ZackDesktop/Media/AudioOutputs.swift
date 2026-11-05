/// The processes that output audio.
public protocol AudioOutputs: Sendable {
    /// Bundle IDs of the processes that output audio right now; empty if they cannot be read.
    func playingBundleIDs() -> Set<String>
}
