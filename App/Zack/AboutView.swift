import AppKit
import SwiftUI
import ZackCore

/// "Über Zack": version, attribution for the CC BY 4.0 model and the Whisper model, licenses of the bundled components.
struct AboutView: View {
    struct Component: Identifiable {
        let name: String
        let license: String
        /// License text in the app bundle (`Resources/Licenses`).
        let file: String
        var id: String { name }
    }

    /// Everything compiled into the app binary (FluidAudio's ThirdPartyLicenses, checked 2026-10-28) plus the embedded
    /// Sparkle framework (its LICENSE covers bsdiff, sais-lite, ed25519 and SUSignatureVerifier too). Parts of
    /// FluidAudio that it downloads at run time for speech output (Kokoro, Spanish and French lexicons) are not
    /// in the app and never fetched by Zack. Computed, so the names follow the interface language.
    static var components: [Component] {
        [
            Component(name: "FluidAudio", license: "Apache-2.0", file: "FluidAudio-LICENSE"),
            Component(name: "fastcluster (in FluidAudio)", license: "BSD-2-Clause", file: "fastcluster-LICENSE"),
            Component(name: "VBx (in FluidAudio)", license: "Apache-2.0", file: "vbx-LICENSE"),
            Component(
                name: String(localized: "Japanische Textaufbereitung (in FluidAudio)"),
                license: "Apache-2.0, MIT, BSD", file: "JapaneseG2P-LICENSE"),
            Component(name: "WhisperKit", license: "MIT", file: "WhisperKit-LICENSE"),
            Component(
                name: "swift-transformers (in WhisperKit)", license: "Apache-2.0", file: "swift-transformers-LICENSE"),
            Component(name: "Sparkle", license: "MIT, BSD, zlib", file: "Sparkle-LICENSE"),
            Component(name: "Lucide Icons", license: "ISC, MIT", file: "Lucide-LICENSE"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Zack-Logo")
            Text("Zack \(Zack.version)")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Lokales Diktat für macOS. Erkennung und Glättung laufen auf diesem Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Spracherkennung")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(
                "„Parakeet Ultra“ von Moondream (moondream/parakeet-ultra), aufbauend auf „Parakeet TDT 0.6B v3“ von NVIDIA (nvidia/parakeet-tdt-0.6b-v3), für Core ML umgewandelt von FluidInference (FluidInference/parakeet-ultra-coreml). Zack nutzt die Gewichte unverändert."
            )
            .fixedSize(horizontal: false, vertical: true)
            Link("Lizenz: CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
            Divider()
            Text("Fachbegriffe gegenprüfen")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(
                "„Whisper large-v3 turbo“ von OpenAI, für Core ML umgewandelt von Argmax (argmaxinc/whisperkit-coreml), mit dem Tokenizer aus openai/whisper-large-v3. Zack lädt das Modell erst, wenn „Fachbegriffe gegenprüfen“ eingeschaltet wird, und nutzt die Gewichte unverändert."
            )
            .fixedSize(horizontal: false, vertical: true)
            Link("Lizenz Core-ML-Modell: MIT", destination: URL(string: "https://opensource.org/license/mit")!)
            Link(
                "Lizenz Tokenizer: Apache 2.0",
                destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
            Divider()
            Text("Weitere Komponenten")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Self.components) { component in
                HStack(alignment: .firstTextBaseline) {
                    Text(component.name)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(component.license) { open(component.file) }
                        .fixedSize()
                        .accessibilityLabel("Lizenztext \(component.license) für \(component.name) öffnen")
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func open(_ file: String) {
        if let url = Bundle.main.url(forResource: file, withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
}
