import Accessibility
import SwiftUI
import ZackCore
import ZackDesktop

/// Bar under a line editor: add and remove, notes about the file, and the way to edit it by hand.
struct EditorFooter: View {
    let onAdd: () -> Void
    let onRemove: () -> Void
    let canRemove: Bool
    let unreadableCount: Int
    let notice: String?
    let openFile: () -> Void
    /// Help text and accessibility label of "+".
    var addLabel = String(localized: "Eintrag hinzufügen")

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 2) {
                iconButton("lucide-plus", label: addLabel, action: onAdd)
                iconButton("lucide-minus", label: String(localized: "Eintrag entfernen"), action: onRemove)
                    .disabled(!canRemove)
            }
            VStack(alignment: .leading, spacing: 4) {
                if unreadableCount > 0 {
                    Text(EditorText.unreadableLines(unreadableCount))
                        .foregroundStyle(.secondary)
                }
                if let notice {
                    Label {
                        Text(notice)
                    } icon: {
                        StatusIcon(name: "lucide-circle-alert", tone: .yellow)
                    }
                }
            }
            // No fixedSize: under a list it raises the pane's height above the window's.
            .font(.callout)
            Spacer(minLength: 0)
            Button("In Texteditor öffnen", action: openFile)
        }
        .onChange(of: notice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
    }

    private func iconButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image)
                .renderingMode(.template)
                .resizable()
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Validation problems in red under an editor; VoiceOver announces them when they appear or change.
struct ProblemList: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(messages, id: \.self) { Text($0) }
        }
        .font(.callout)
        .foregroundStyle(Brand.problem)
        .onChange(of: messages, initial: true) { _, messages in
            if !messages.isEmpty { AccessibilityNotification.Announcement(messages.joined(separator: " ")).post() }
        }
    }

    /// "Field: problem" lines, each once, in the order of the issues.
    static func messages(for issues: [EntryIssue], label: (EntryField) -> String) -> [String] {
        var seen: Set<String> = []
        return issues.map { "\(label($0.field)): \($0.problem.message)" }.filter { seen.insert($0).inserted }
    }
}

/// Locked editor: the file cannot be read, so the pane never writes it. Without user files there is nothing to open.
struct UnreadableFileNote: View {
    let openFile: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Label {
                Text(EditorText.unreadableFile)
            } icon: {
                StatusIcon(name: "lucide-circle-alert", tone: .yellow)
            }
            if let openFile {
                Button("In Texteditor öffnen", action: openFile)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
