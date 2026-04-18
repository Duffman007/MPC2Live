# MPC2Live

A native macOS app that converts **Akai MPC Sample** projects (`.xpj`) into **Ableton Live Sets** (`.als`).

![macOS](https://img.shields.io/badge/macOS-11.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-Beta%200.10-red)

---

## What it does

Drop an `.xpj` project file exported from an Akai MPC Sample onto the window. MPC2Live converts it to an Ableton Live Set in the same folder — ready to open in Live.

**What gets converted:**

| MPC Sample | Ableton Live |
|---|---|
| Drum tracks | Drum Rack (one per track) |
| Pads + samples | Drum Rack slots with Simpler |
| Sequences | MIDI clips in the Session View |
| Sample references | Linked to your original files |
| Master bus compressor | Compressor2 on the main track |

---

## Getting started

1. On your MPC Sample, save your project. The `.xpj` file will be in the project folder on your SD card or internal storage.
2. Copy the project folder to your Mac (via USB, Wi-Fi, or SD card reader).
3. Drag the `.xpj` file onto the MPC2Live window — or click **Browse** to locate it.
4. The converted `.als` appears in the same folder as your `.xpj`.
5. Open the `.als` in Ableton Live.

> **Tips**
> - Make sure sample files are accessible on your Mac at the same relative path.
> - If samples show as missing in Live, use **Collect All and Save** to locate them.
> - Best results with Ableton Live 11 or later.

---

## Requirements

- macOS 11.0 Big Sur or later
- Ableton Live 11+ (to open the converted `.als`)
- Projects exported from an **Akai MPC Sample** (`.xpj` format)

---

## Building from source

1. Clone the repo
2. Open `MPC2Live.xcodeproj` in Xcode 15+
3. Set your Development Team in the project settings
4. Build & run (`⌘R`)

No external dependencies — pure AppKit, no package manager required.

---

## Project structure

```
MPC2Live/
├── Sources/
│   ├── main.swift              # Entry point
│   ├── AppDelegate.swift
│   ├── MainWindow.swift
│   ├── DropViewController.swift  # Main UI controller
│   ├── DropZoneView.swift        # Drag-and-drop zone + pad grid
│   ├── MPCParser.swift           # .xpj file parser
│   ├── MPCProject.swift          # MPC project model
│   ├── Converter.swift           # Conversion pipeline
│   ├── ALSWriter.swift           # .als file writer
│   ├── ALSConverter.swift
│   ├── ALSDrumRack.swift
│   ├── ALSSimpler.swift
│   ├── ALSMIDIClip.swift
│   ├── ALSNoteMap.swift
│   ├── ALSTemplate.swift
│   ├── ReferenceTemplates.swift
│   ├── UpdateChecker.swift
│   ├── WAVInfo.swift
│   └── Panels.swift
└── Resources/
    ├── Info.plist
    ├── MPC2Live.entitlements
    ├── appIcon.icns
    ├── version.txt
    └── changelog.txt
```

---

## License

MIT — see [LICENSE](LICENSE).
