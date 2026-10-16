# isochron_flutter

The native macOS desktop studio for **Isochron**, built with Flutter and `macos_ui`.

Provides a professional forced alignment studio interface featuring:
- **Project & Collection Organization:** Auto-pairs bulk audio and text files into tracks.
- **Worker Isolate Architecture:** Runs long-running neural ONNX model inference without dropping UI frames.
- **Model Status Panel:** Built-in model download, verification, cancellation, and deletion.
- **Pro Waveform Editor:** Smooth trackpad horizontal panning, exponential pinch-to-zoom, active boundary highlight, and ghost markers.
- **Listen-and-Nudge Keyboard Shortcuts:** Fast auditioning and boundary shifting with instant auto-replay.
- **Quality Badges:** Confidence percentages and color-coded diagnostic flags (`omitted`, `no pause`, `poor match`, `long`, `short`).
- **"Keep My Edits" Safety:** Re-aligning locks reviewed boundaries as hard constraints and automatically writes `.bak` backup files.
- **Exporting:** Single-track phrase timing text export and collection-wide CSV export.

---

## Getting Started

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

## Documentation

- [📘 **Complete Studio Tutorial**](../docs/tutorial.md)
- [🔬 **Technical Details & Alignment Theory**](../docs/technical_details.md)
- [🏠 **Main Repository README**](../README.md)

---

## License

Dedicated to the public domain under the Creative Commons Zero (CC0 1.0 Universal) license.
