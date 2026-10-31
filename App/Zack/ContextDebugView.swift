#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug view: shows what Accessibility reports about the focused field of the app that was in front.
    struct ContextDebugView: View {
        let lines: [String]

        private var text: String { lines.joined(separator: "\n") }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Alles kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(minWidth: 620, minHeight: 480)
        }
    }
#endif
