public enum EngineLimits {
    /// Shortest clip handed to an engine, in seconds. Matches the FluidAudio ASR minimum (0.3 s);
    /// Apple Speech hangs on empty clips and returns nothing useful below this length.
    public static let minimumClipDuration = 0.3

    /// RMS below this is treated as silence (synthesized test fixture with the voice Anna at 0.02 gain: 0.0023;
    /// white noise of +-0.002: 0.0012).
    public static let silenceRMS: Float = 0.002
    /// Peak below this is treated as silence (synthesized test fixture with the voice Anna at 0.02 gain: 0.016;
    /// white noise of +-0.002: 0.002).
    public static let silencePeak: Float = 0.01

    /// True for digital silence and very low noise, which Whisper would turn into invented text.
    public static func isSilent(_ clip: AudioClip) -> Bool {
        guard !clip.samples.isEmpty else { return true }
        var sumSquares: Float = 0
        var peak: Float = 0
        for sample in clip.samples {
            sumSquares += sample * sample
            peak = max(peak, abs(sample))
        }
        let rms = (sumSquares / Float(clip.samples.count)).squareRoot()
        return rms < silenceRMS || peak < silencePeak
    }
}
