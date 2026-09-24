# AsmrAiPlayer

[中文说明](README.md)

A beautiful and modern [ASMR.ONE](https://asmr.one) client application built with Flutter.

## Project Overview

AsmrAiPlayer is designed to provide a smooth and enjoyable ASMR listening experience with beautiful animations and a modern user interface.

## Features

- Stable background playback
- Beautiful animations and clean UI design
- Subtitle/lyric display with VTT/LRC import support
- Playlist management
- Multi-dimensional browsing: tags, circles, voice actors
- Favorites collection
- Android 13+ notification permission support
- Floating lyric overlay (Android)
- **Windows desktop support**: full desktop experience — background playback, local download, offline playback; Release ships as `AsmrAiPlayer.exe` (distribute the whole `Release\` folder including `data\` and DLLs)
- Comprehensive settings system
- Smart caching (images, subtitles, audio files)
- Unified cache management

## Project Vision (AI-Enhanced Playback · Planned TODO)

The following capabilities are **project vision, not yet implemented**, and will be delivered incrementally via the [TODO docs](docs/todos/):

- 🗣️ **Simultaneous interpretation**: live transcription of Japanese audio with overlaid target-language (e.g. Chinese) subtitles during playback
- 🌍 **Translation**: Japanese → Chinese subtitle translation; a combined “translate + play” entry next to list play buttons
- 🎤 **Recognition**: ASR subtitle generation; smart left/right ear detection (filename `left`/`right` → acoustic waveform → manual fallback), plus dual-ear alternate mode with “other-ear translation” overlay
- 🎛️ Toggle translation on/off and switch ear direction at any time while playing

## Requirements

- Flutter 3.27.0+
- Dart SDK >=3.2.3 <4.0.0
- Android: minSdk 21 / targetSdk 33
- Java 17
- Windows: x64, Visual Studio 2022 (Desktop development with C++ + Windows SDK)

## Getting Started

```bash
git clone https://github.com/pmsleepcheck/AsmrAiPlayer.git
cd AsmrAiPlayer
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run

# Windows Release (output: build\windows\x64\runner\Release\AsmrAiPlayer.exe)
flutter build windows --release
```

## Project Structure

```
lib/
├── core/                 # Core functionality (audio, subtitle, theme, cache, platform)
├── data/                 # Data layer (API, models, repositories)
├── presentation/         # Presentation layer (ViewModels)
├── screens/              # Full-page screens
├── widgets/              # Reusable UI components
└── common/               # Common utilities and constants
```

## Development Guidelines

- [Development Guidelines](docs/guidelines_en.md)

## Contributing

Please read our [Development Guidelines](docs/guidelines_en.md) before making a contribution.

## License

This project is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License (CC BY-NC-SA) - see the [LICENSE](LICENSE) file for details.

- All modifications, new code, and documentation contributed by this repository (AsmrAiPlayer) on top of the upstream project are released under the same [CC BY-NC-SA](LICENSE): share and remix non-commercially, with attribution and **ShareAlike** (derivative works must use the identical license).
- **Attribution chain**: AsmrAiPlayer → upstream [Xuro](https://github.com/WuMe-sicx/Xuro) ([WuMe-sicx](https://github.com/WuMe-sicx)) → original project [Yuro](https://github.com/asmroneapp/Yuro) ([asmroneapp](https://github.com/asmroneapp)). Keep the full attribution chain and license links when redistributing or deriving.
- Planned AI-enhanced playback vision items (simultaneous interpretation / translation / recognition) are TODOs; their future implementations will also be covered by this license.

Original author: [asmroneapp](https://github.com/asmroneapp) | Original repo: [Yuro](https://github.com/asmroneapp/Yuro)

This license allows others to remix, tweak, and build upon your work non-commercially, as long as they credit you and license their new creations under the identical terms.
