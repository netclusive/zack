# Development

Building Zack from source, the quality gate, releases and the benchmark tool `zack-bench`. For installing and using
the app, see the [README](../README.md).

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
builds a debug app with a "Debug" menu of test tools (paste test, context reading). `--static-only` runs the secret
scan, lint and version checks alone, `--skip-static` the tests and builds; `scripts/release.sh` checks the security
advisories in between and stops if a pinned package lies in an affected range or a range cannot be read.

Logic belongs in the package targets, where `swift test` covers it; `App/Zack` keeps only the SwiftUI views and the
wiring, and has no test target of its own.

Latency: `scripts/latency.sh --record 30m` records the app's signposts while you dictate and then reports p50 and
p95 (stop early with Ctrl-C). The system log keeps them for a few minutes only, so `--last` suits short checks.

## Releases

`scripts/release.sh` builds, notarizes and publishes a release; output goes to `.build/zack-release/<version>/`.

- `--publish`: the real release. It builds, notarizes, signs with the EdDSA key from the keychain, writes
  `appcast.xml`, pushes `main` and the tag, and creates the GitHub release. It asks nothing on the way.
- No option: prints the usage only.
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
is completed on the next run. If `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN` or `HUGGINGFACEHUB_API_TOKEN` is set,
FluidAudio also sends it to Hugging Face as a token.
