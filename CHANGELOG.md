# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- After you allow it, Zack checks once a day for a new version, offers it, and can install it automatically when it quits. Turn this on or off in the settings.
- A settings window (⌘,) collects all options: general, dictionary, snippets, code apps, updates and setup.
- Edit the dictionary, snippets and code apps right in Zack. The text files stay valid and editable, and comments in them are kept.

### Changed

- Zack is open source under the Apache License 2.0.
- The menu is shorter and shows only the status and everyday actions.
- "Regeltext statt KI-Fassung" is now "Ohne KI-Glättung einfügen".
- Setup is part of the settings window.

### Removed

- The benchmark no longer includes the GPU language model as an AI cleanup candidate.
- The benchmark no longer includes Whisper as a speech recognition candidate.

### Fixed

- If the dictionary, snippets or code apps file is a symbolic link, Zack now saves to the linked file and keeps the link.
- Zack reads dictionary, snippets and code apps files saved in UTF-16 with a byte order mark, and no longer shows garbage entries for a file it cannot read as text.

## [0.4.0] - 2026-10-30

### Added

- Code mode for editors and terminals: spoken file names and case commands become code, and short commands get no trailing period. Switch it per app in the menu.
- Zack does not dictate into password fields.
- Press Esc while Zack recognizes or cleans up to cancel the insert; the text stays available as the last dictation.
- ⌃⌥V inserts the last dictation again at the cursor.
- ⌃⌥O replaces an AI-cleaned dictation with the rule-based text within 10 seconds.
- The menu shows when another app has Secure Input turned on.

### Fixed

- Consecutive dictations no longer run together: Zack adds a space and adapts capitalisation to the text before the cursor.
- `scripts/latency.sh --record` without a duration records for 30 minutes instead of stopping with an error; a missing value for `--last` or `--input` is reported clearly.

## [0.3.0] - 2026-10-29

### Added

- Choose the microphone for Zack in the menu; the macOS default input stays unchanged. If it is not connected, Zack uses the macOS default until it is back.
- `zack-bench mic-check --device` measures a chosen microphone without changing the macOS default input.
- App icon: a wave-shaped Z, also shown in the About window.

### Changed

- The menu bar shows the Zack logo while ready.
- The indicator shows a blue-to-turquoise gradient while recording and processing, and turquoise once the text is inserted.

### Fixed

- The first indicator after launch appears as quickly as all later ones.

## [0.2.0] - 2026-10-29

### Added

- Menu bar app: hold fn or the right Option key, speak, release, and the text is inserted into the active window.
- Indicator at the bottom of the active screen with level, recording time and status.
- Setup window for microphone and Accessibility permissions, the speech model and Apple Intelligence.
- Dictionary and text snippets as plain text files, editable from the menu.
- Copy the last dictation again, and retry a failed recognition.
- Optional start at login.
- About window with the model attribution and licenses.
- Keep the microphone ready between dictations (off, for two minutes after a dictation, or always), so the first words are not cut off while it wakes up.
- `zack-bench mic-check` measures how quickly the microphone delivers sound after the start.

### Changed

- zack-bench stores newly downloaded Parakeet models with the other Zack models; earlier downloads keep working.
- Dictations too long for the on-device model skip the AI cleanup and keep the rule-based text.

### Fixed

- The bench no longer deletes a downloaded speech model when loading it fails.

## [0.1.0] - 2026-10-28

### Added

- Project skeleton with core library, tests and a local quality gate.
- On-device speech recognition with Apple Speech (transcription and dictation), Parakeet v3 and Ultra, and Whisper Large v3 Turbo.
- Rule-based text cleanup: filler words, preferred spellings and replacements, text snippets, a code mode for identifiers and file names, and spacing and capitalization that follow the text before the cursor.
- Optional on-device AI cleanup for self-corrections, with a time limit and a fallback to the rule-based result.
- Benchmark tool that compares engines on a fixed set of dictation cases, with synthetic or microphone recordings and a summary report.
- An open language model running on the Mac's GPU can be benchmarked as an alternative AI cleanup.
