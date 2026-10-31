/// Collects dictation results: final text in arrival order, volatile text keyed by range start.
struct DictationSegments {
    private var finalText = ""
    private var volatile: [Double: String] = [:]

    mutating func addFinal(_ text: String) {
        finalText += text
    }

    /// A later volatile result for the same start replaces the earlier one.
    mutating func addVolatile(_ text: String, start: Double) {
        volatile[start] = text
    }

    var text: String {
        finalText + volatile.sorted { $0.key < $1.key }.map(\.value).joined()
    }
}
