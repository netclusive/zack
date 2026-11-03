# Zack

Local push-to-talk dictation for macOS. Everything runs on the Mac, no cloud. Dictation works in German or
English, one language per user ("Settings › General › Dictation language"). The interface is in German or English
and follows the macOS language; other languages get English.

Zack.app is a menu bar app: hold fn (or the right Option key), speak, release, and the text is inserted into the
active window. `zack-bench` compares recognition and cleanup engines on a test corpus.

## Install

Zack needs macOS 26 or later on Apple Silicon; AI cleanup needs Apple Intelligence turned on.

There is no ready-made build yet; until the first one appears on the
[releases page](https://github.com/netclusive/zack/releases), build Zack from source (see below).
With a release:

1. Download the latest `Zack-<version>.zip` from the releases page.
2. Open the ZIP and move `Zack.app` to the Applications folder, then start it.
3. Allow Microphone and Accessibility when asked.
4. "Settings › Setup" offers the speech model for download (about 600 MB, see below).

## Using Zack

### Dictation

- Hold the key ("Settings › General › Dictation key"), speak, release: Zack recognizes the speech, applies its text rules
  (dictionary, snippets) and inserts the result at the cursor. A short tap is ignored, and pressing another key
  while holding cancels, so shortcuts such as fn + arrow keep working.
- Language ("Settings › General › Dictation language"): Deutsch or English. On first start Zack follows the macOS language;
  an existing installation stays German. The text rules, AI cleanup, code mode and snippets follow the language,
  and a change applies from the next dictation.
- Esc while the pill shows "Recognizing…" or "Cleaning Up…" cancels: nothing is inserted, and the result is kept as
  the last dictation.
- Menu section "Last Dictation": "Insert" (⌃⌥V) inserts the last dictation again at the cursor, "Insert Without
  AI Cleanup" (⌃⌥O) replaces an AI-cleaned dictation with the rule text, "Copy" copies it. "Try Again" appears
  after a failed recognition. A shortcut another app already holds is marked "(Shortcut in Use)".
- AI cleanup ("Settings › General › AI cleanup of self-corrections"): if a dictation contains a
  self-correction such as "Montag, nein, Dienstag" or "Tuesday, no, Wednesday", Apple's on-device model smooths
  the sentence.
- Password fields: Zack does not dictate into them and shows a hint instead. While another app holds Secure Input,
  the menu shows "Secure Input Active"; dictation works, only canceling with another key does not.

### Settings and permissions

- The settings window ("Settings…" in the menu, ⌘,) has the panes General (language, key, microphone
  readiness, launch at login, AI cleanup), Dictionary, Snippets, Code Apps, Updates and Setup. If a
  permission or the speech model is missing, Zack opens it in Setup.
- Permissions: Microphone, and Accessibility for inserting with Cmd+V, for reading the text before the cursor and
  for canceling with another key. The key itself works without Accessibility; the text then stays on the
  clipboard.
- Model: Parakeet Ultra in `~/Library/Application Support/Zack/Models`. "Settings › Setup" moves a copy from
  zack-bench (`~/Library/Application Support/FluidAudio/Models`) or downloads it on click (about 600 MB from
  Hugging Face, USA; only the IP address is transmitted). The app never downloads on its own.

### Files

`vocabulary.txt`, `snippets.txt` and `code-apps.txt` live in `~/Library/Application Support/Zack` and are created
with examples in the dictation language; existing files stay as they are when the language changes. Lines
starting with `#` are ignored. Edit them in "Settings › Dictionary / Snippets / Code Apps" or in any text
editor: Zack changes only the lines you edit, keeps comments and lines it cannot read, and reloads a file changed
elsewhere.

- `vocabulary.txt`: one term per line, which Zack writes exactly as given and passes to the recognition as a hint;
  `wrong => right` replaces a spelling.
- `snippets.txt`: one snippet per line as `Name => Text`, `\n` for a line break; dictating "Baustein <Name>"
  (English: "snippet <name>") inserts the text. Known limits: a literal `\n` in snippet text becomes a line
  break, and spaces at the start and end of a field are dropped.
- `code-apps.txt`: the apps for code mode (bundle IDs, or prefixes ending in `*`). In these apps spoken file names
  ("readme punkt md", English "readme dot md") and case commands become code, and short commands get no trailing
  period. The menu switches the current app on or off, "Settings › Code Apps" adds apps; the file is read again
  for every dictation.

### Context

Zack reads the text before the cursor (needs Accessibility) to add a space and adapt capitalization: at most the
500 characters before the cursor, or the field text up to 100,000 characters if the app offers nothing narrower,
and keeps only the current line of it. It stays in memory only, is never logged and is dropped when the dictation
ends. Where an app does not expose it, Zack falls back to its last own dictation until the next key press, the
next click or an app switch.

### Microphone

- Readiness ("Settings › General › Keep microphone ready"): by default the microphone stays open for two minutes
  after a dictation, so the first words are not cut off; "Always" keeps it open, "Off" closes it after each
  dictation. While it is open, only the last half second is kept in memory, continuously overwritten, never
  recognized or stored, and macOS shows the orange microphone indicator.
- Choice (menu "Microphone: <device>"): "Same as macOS" follows the system input; picking a device applies to Zack only
  and leaves the macOS default untouched. If the chosen device is not connected, Zack uses the macOS default and
  switches back as soon as the device returns.

### Privacy

Audio and text stay in memory, the clipboard entry is marked transient and restored afterwards, and logs contain
durations, engines and error types only. AI cleanup uses Apple's on-device model only. Zack goes online only for
the model download you start and, in official builds, for the update check you allow (see below).

## Updates

Official builds update themselves through [Sparkle](https://sparkle-project.org). On the second launch Zack asks
whether it may check for updates; the prompt has a checkbox for automatic installing. After you agree, it checks
once a day. The switches are in "Settings › Updates", "Check for Updates…" is in the menu:

- "Check for Updates…" (menu) and "Check Now" (settings) check right away.
- "Automatically check for updates" turns the daily check on or off.
- "Automatically install updates" downloads in the background and installs when Zack quits.
- "Update to <version>…" appears when an update waits (with automatic installing off); a click shows the update
  and its changes.

Privacy: the update check runs only after your consent, once a day, and can be turned off in the settings. Feed and
downloads come from GitHub (GitHub Inc., USA). A request carries your IP address and the user agent
`Zack/<version> Sparkle/<version>`; Sparkle sends no system profile.

## Build from source

Requirements:

- Swift 6.2 or later
- Xcode 27 or later, XcodeGen 2.46 or later (`brew install xcodegen`) and an Apple Development certificate (a free
  Apple ID in Xcode is enough)
- gitleaks (`brew install gitleaks`): `./build.sh` starts with a secret scan and stops without it
- ShellCheck (`brew install shellcheck`): `./build.sh` lints the shell scripts with it
- a German system voice, preferably Anna: the tests synthesize their speech sample with it

Tested with Xcode 27.2 (swift-format 6.4.4), XcodeGen 2.46.0, gitleaks 8.30.1 and ShellCheck 0.11.0; other versions
may lint, format or scan differently, and `./build.sh` warns about them.

Builds you make yourself get no updates: feed URL and public key are empty in `App/Zack.xcconfig`, and only
`scripts/release.sh` sets them. "Settings › Updates" then shows "Updates are only available in official builds."

Build and install:

    cp App/Local.xcconfig.example App/Local.xcconfig   # then enter the team ID, see the comment in the file
    ./build.sh
    scripts/install-app.sh

`./build.sh` is the quality gate: secret scan, lint, tests, the release script's self-test and the builds. It
generates `App/Zack.xcodeproj` with XcodeGen (not tracked) and builds the release app; `scripts/build-app.sh Debug`
builds a debug app with a "Debug" menu of test tools (paste test, context reading).

Logic belongs in the package targets, where `swift test` covers it; `App/Zack` keeps only the SwiftUI views and the
wiring, and has no test target of its own.

Latency: `scripts/latency.sh --record 30m` records the app's signposts while you dictate and then reports p50 and
p95 (stop early with Ctrl-C). The system log keeps them for a few minutes only, so `--last` suits short checks.

## Releases

`scripts/release.sh` builds, notarizes and publishes a release; output goes to `.build/zack-release/<version>/`.

- No option: the real release. It builds, notarizes, signs with the EdDSA key from the keychain, writes
  `appcast.xml`, pushes `main` and the tag, and creates the GitHub release.
- `--dry-run`: everything except push and publication, notarization included.
- `--local`: Apple Development signing, no notarization, a test feed on 127.0.0.1:8000 and a test key from the
  keychain account `zack-test`.
- `--self-test` runs inside `./build.sh`.

Prerequisites:

- a Developer ID Application certificate in the keychain
- a notarytool keychain profile named `zack-notary`
- the EdDSA private key in the login keychain (created with Sparkle's `generate_keys`)
- `gh` logged in with write access to `netclusive/zack`
- `DEVELOPMENT_TEAM` and `ZACK_RELEASE_TEAM` in the ignored `App/Local.xcconfig`
- releases are made from `main` with an annotated tag `vX.Y.Z`

## Benchmark

Run from the repository root:

    swift run -c release zack-bench synth
    swift run -c release zack-bench record
    swift run -c release zack-bench run --transcriber parakeet-v3 --cleaner apple-fm
    swift run -c release zack-bench report

- `synth` creates synthetic recordings with a macOS voice (`--voice`, default `Anna`) in
  `bench/corpus/audio-synth`.
- `record` records the cases with the microphone in `bench/corpus/audio`. It skips existing recordings;
  `--all` records them again, `--id <case>` records one case.
- `mic-check` measures the start latency of the microphone, the time to the first audio and to the first
  non-silent audio, over `--repeat <n>` passes (default 5). `--device <name>` picks an input device instead of the
  macOS default.
- `run` transcribes every case that has a recording, applies the text rules and the cleaner, and writes a JSON
  result. `--transcriber` is one of `apple-speech`, `apple-dictation`, `parakeet-v3`, `parakeet-ultra`;
  `--cleaner` is `none` (default) or `apple-fm` (needs Apple Intelligence). `--repeat <n>` (default 5) processes
  the corpus in n passes, one case after the other per pass: quality is averaged per case over all passes, then
  over the cases, and latency percentiles use the timings of all passes (a later pass with a different result
  prints a warning; the raw text of every pass is stored in the result). Model loading and warm-up are not timed.
- `report` shows the newest run per engine combination and audio folder; `--all` shows every run. Each latency
  cell shows the number of timings behind it, e.g. `57 (n=220)`. `Fälle` is the number of cases without error,
  `Ø lang s` the mean recording length of the long cases, `instabil` the number of cases whose final text differs
  between passes (`-` with `--repeat 1`). `Fehler` is `X (+Y)`: X failed cases, Y failed later passes (omitted
  if 0). WER and correction matching ignore compound spelling (hyphen, space, closed).

Transcriber latency (`p50 Erk. ms`, `p95 Erk. ms`, `p95 ohne KI ms`, `p95 10 s ohne KI ms`) is taken from
`--cleaner none` runs. Runs with a cleaner are used for `p95 mit KI ms`. Within a run, "ohne/mit KI" splits the
timings per sample by whether the cleaner was called; `KI verworfen` is the rejected or timed-out share of cleaner
calls over all passes.

Common options: `--audio-dir <dir>` (default `bench/corpus/audio`, for `synth` `bench/corpus/audio-synth`),
`--results <dir>` (default `bench/results`), `--corpus <file>` (default `bench/corpus/cases.json`) and
`--id <case>` for `synth` and `record`. `zack-bench help` lists them.

`--language de|en` (for `synth`, `record` and `run`, default `de`) picks the language; `en` switches the defaults to
`bench/corpus/cases-en.json`, the voice `Samantha` and the audio folders `bench/corpus/audio-synth-en` (`synth`) and
`bench/corpus/audio-en` (`record`, `run`), and `run` uses the English rules and an English speech locale. Explicit
options win over these defaults.

Recordings and results contain voice and text and are not tracked by Git.

## Model downloads

In `zack-bench`, the first run of an engine downloads its model and needs network access; the app downloads only
on click in "Settings › Setup". Later runs work offline.

| Engine | Source | Stored in | Size |
|---|---|---|---|
| `apple-speech`, `apple-dictation` | macOS speech assets for German or English (`--language en`) | managed by macOS | not measured |
| `parakeet-v3` | Hugging Face, via FluidAudio | `~/Library/Application Support/Zack/Models` (earlier downloads in `~/Library/Application Support/FluidAudio/Models` keep working) | about 460 MB |
| `parakeet-ultra` | Hugging Face, via FluidAudio | `~/Library/Application Support/Zack/Models` (earlier downloads in `~/Library/Application Support/FluidAudio/Models` keep working) | about 600 MB |
| `apple-fm` | part of Apple Intelligence | managed by macOS | not measured |

Downloads fetch model files only; transcription and cleanup run on the Mac. An interrupted download
is completed on the next run.

## License

Apache License 2.0, see [LICENSE](LICENSE). The Zack name and logo and the netclusive name and brand are not
licensed under it.

## Publisher

netclusive GmbH. [Imprint](https://www.netclusive.de/impressum),
[privacy policy](https://www.netclusive.de/datenschutz). No guaranteed support.
