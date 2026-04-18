// ALSConverter.swift
// Orchestrates the full MPC → ALS conversion.

import Foundation

enum ALSConverterError: Error, CustomStringConvertible {
    case noTracks
    case trackInjectionFailed
    case general(String)

    var description: String {
        switch self {
        case .noTracks:             return "No drum tracks found in project"
        case .trackInjectionFailed: return "Failed to inject tracks into ALS XML"
        case .general(let s):       return s
        }
    }
}

struct ALSConverter {

    static let trackColours = [20, 25, 13, 28, 9, 15, 26, 18]

    // MARK: - Public

    static func convert(project: MPCProject, inputURL: URL, outputURL: URL) throws {
        guard let drumTrack = project.drumTrack else {
            throw ALSConverterError.noTracks
        }
        let banks = drumTrack.banks()
        guard !banks.isEmpty else { throw ALSConverterError.noTracks }

        // Project folder structure
        let projectDir = ALSWriter.projectFolderURL(for: outputURL)
        let samplesDir = projectDir.appendingPathComponent("Samples/Imported")
        let xpjStem    = inputURL.deletingPathExtension().lastPathComponent
        let sourceDir  = inputURL.deletingLastPathComponent()
            .appendingPathComponent("\(xpjStem)_[ProjectData]")

        // Copy WAV files
        // loadImpl=0: full WAV is in [ProjectData] — copy directly
        // loadImpl=1: full WAV is also in [ProjectData] when project was saved correctly
        //             (MPC writes a ~10s stub if SD card had an error; nothing we can do)
        let fm = FileManager.default
        try fm.createDirectory(at: samplesDir, withIntermediateDirectories: true)

        // Deduplicate: MPC saves separate copies of the same sample (001, 002 suffixes).
        // Build size → first canonical filename map so duplicates copy from the first.
        // Name-based dedup: MPC appends 001/002/003 when the same sample is on multiple pads.
        // Strip the 3-digit suffix to find the base name, then confirm the base file exists.
        // e.g. "Kick001.wav" → try "Kick.wav" — only dedup if "Kick.wav" exists in [ProjectData].
        // This avoids false positives like "Kick808.wav" → "Kick.wav".
        var fileToCanonical: [String: String] = [:]
        for pad in drumTrack.pads where !pad.sampleFile.isEmpty {
            let sf = pad.sampleFile
            let canonical: String
            // Check if filename ends with exactly 3 digits before .wav (case-insensitive)
            let lower = sf.lowercased()
            if lower.hasSuffix(".wav") {
                let stem = String(sf.dropLast(4))     // remove ".wav"
                if stem.count >= 3 {
                    let last3 = String(stem.suffix(3))
                    if last3.allSatisfy({ $0.isNumber }) {
                        let baseStem = String(stem.dropLast(3))
                        let baseName = baseStem + ".wav"
                        if fm.fileExists(atPath: sourceDir.appendingPathComponent(baseName).path) {
                            canonical = baseName      // confirmed base exists → use it
                            fileToCanonical[sf] = canonical
                            continue
                        }
                    }
                }
            }
            fileToCanonical[sf] = sf  // no suffix or base not found → it IS canonical
        }

        // DEBUG: print dedup map
        for (k, v) in fileToCanonical.sorted(by: { $0.key < $1.key }) {
            fputs("  dedup: \(k) → \(v)\n", stderr)
        }

        for pad in drumTrack.pads {
            let src = sourceDir.appendingPathComponent(pad.sampleFile)
            let dst = samplesDir.appendingPathComponent(pad.sampleFile)
            guard fm.fileExists(atPath: src.path) else {
                fputs("Warning: sample not found: \(src.path)\n", stderr)
                continue
            }
            // For reversed pads: create a reversed WAV in Samples/Processed/Reverse/
            // Use canonical filename so duplicate reversed pads share one reversed file.
            if pad.reverse {
                let revDir      = samplesDir.deletingLastPathComponent()
                                            .appendingPathComponent("Processed/Reverse")
                let baseName    = fileToCanonical[pad.sampleFile] ?? pad.sampleFile
                let revName     = baseName.replacingOccurrences(of: ".wav", with: " R.wav",
                                                                options: [.caseInsensitive, .backwards])
                let revDst      = revDir.appendingPathComponent(revName)
                if !fm.fileExists(atPath: revDst.path) {
                    try fm.createDirectory(at: revDir, withIntermediateDirectories: true)
                    // Read from canonical source — robust against corrupt duplicate files
                    let canonSrc = sourceDir.appendingPathComponent(baseName)
                    let readSrc  = fm.fileExists(atPath: canonSrc.path) ? canonSrc : src
                    if let srcData = try? Data(contentsOf: readSrc) {
                        let reversed = reverseWAV(srcData)
                        try reversed.write(to: revDst)
                    }
                }
                continue
            }

            // Deduplicate: if this file is a duplicate, skip — ALS will point to canonical
            if let canonical = fileToCanonical[pad.sampleFile], canonical != pad.sampleFile {
                continue  // don't copy the duplicate; ALS RelativePath uses canonical name
            }

            guard !fm.fileExists(atPath: dst.path) else { continue }
            // Validate: check RIFF header to catch all-0xFF corrupt SD card writes
            if let srcData = try? Data(contentsOf: src, options: .mappedIfSafe) {
                let header = srcData.prefix(4)
                let isRiff = header == Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
                let isAllFF = header.allSatisfy { $0 == 0xFF }
                if !isRiff || isAllFF {
                    fputs("\nWARNING: \(pad.sampleFile) appears corrupt (not a valid WAV header).\n", stderr)
                    fputs("  Likely a failed SD card write. Replace with the original WAV file.\n\n", stderr)
                }
            }
            try fm.copyItem(at: src, to: dst)
        }

                // Load blank ALS and set BPM
        var xml = try ALSWriter.loadBlankTemplate()
        xml = ALSWriter.setBPM(xml, bpm: project.bpm)
        xml = ALSWriter.setNextPointeeId(xml)

        // Inject master bus compressor if the XPJ had one
        if project.hasMasterCompressor {
            xml = ALSWriter.injectMasterCompressor(xml)
        }

        // Set per-scene BPM for sequences that differ from master
        let sceneTempos = project.sequences.map { (name: $0.name, bpm: $0.bpm) }
        xml = ALSWriter.setSceneBPMs(xml, sequences: sceneTempos, masterBPM: project.bpm)

        // Build one MidiTrack per bank, plus Simpler tracks for note-mode pads
        var trackBlocks: [String] = []
        var trackCounter = 0
        for bank in banks {
            let name   = bank.name  // e.g. "Bank A", "Bank B"
            let colour = trackColours[trackCounter % trackColours.count]
            let block  = buildTrack(project: project, bank: bank,
                                    trackName: name, colour: colour,
                                    trackIndex: trackCounter, samplesURL: samplesDir,
                                    sourceDir: sourceDir, fileToCanonical: fileToCanonical)
            trackBlocks.append(block)
            trackCounter += 1

            // For each chop-mode pad in this bank, add a Simpler slice track.
            // Detection: sequence events flagged it (isChopMode) OR
            // WAV atem has slices AND this is the only loaded pad in the bank
            // (guard against stale atem data from a reused sample in a new project).
            let loadedPadsInBank = bank.pads.filter { !$0.sampleFile.isEmpty }
            for pad in bank.pads where !pad.sampleFile.isEmpty && !pad.isNoteMode {
                let wavURL   = samplesDir.appendingPathComponent(pad.sampleFile)
                let wavInfo  = WAVInfo.read(from: wavURL)
                let hasAtemSlices = wavInfo?.sliceStarts.isEmpty == false
                let isChop   = pad.isChopMode || (hasAtemSlices && loadedPadsInBank.count == 1)
                guard isChop else { continue }
                let padName  = padLabel(pad)
                let colour2  = trackColours[trackCounter % trackColours.count]
                let block2   = buildChopTrack(project: project, pad: pad,
                                              trackName: padName, colour: colour2,
                                              bankIndex: bank.bankIndex,
                                              noteToBankIndex: bank.noteToBankIndex,
                                              trackIndex: trackCounter,
                                              samplesURL: samplesDir)
                trackBlocks.append(block2)
                trackCounter += 1
            }

            // For each note-mode pad in this bank, add a Simpler MIDI track
            for pad in bank.pads where pad.isNoteMode {
                let padName  = padLabel(pad)   // e.g. "H01"
                let colour2  = trackColours[trackCounter % trackColours.count]
                let block2   = buildNoteModeTrack(project: project, pad: pad,
                                                  trackName: padName, colour: colour2,
                                                  bankIndex: bank.bankIndex,
                                                  noteToBankIndex: bank.noteToBankIndex,
                                                  trackIndex: trackCounter,
                                                  samplesURL: samplesDir)
                trackBlocks.append(block2)
                trackCounter += 1
            }
        }

        xml = injectTracks(into: xml, trackBlocks: trackBlocks)
        try ALSWriter.writeProject(xml: xml, to: outputURL)
    }

    // MARK: - Track builder

    private static func buildTrack(
        project: MPCProject, bank: MPCBank,
        trackName: String, colour: Int,
        trackIndex: Int, samplesURL: URL,
        sourceDir: URL, fileToCanonical: [String: String]
    ) -> String {
        guard let blankXML  = try? ALSWriter.loadBlankTemplate(),
              var trackXML  = extractFirstMidiTrack(from: blankXML) else { return "" }

        // Remap all internal IDs to unique values — prevents collisions across tracks
        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        let trackId = 100 + trackIndex

        // Track ID
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")

        // Track name (EffectiveName first occurrence)
        trackXML = trackXML.replacingOccurrences(
            of: "Value=\"1-MIDI\"",
            with: "Value=\"\(xmlEscape(trackName))\"",
            options: [], range: trackXML.range(of: "Value=\"1-MIDI\""))

        trackXML = trackXML.replacingOccurrences(
            of: "<UserName Value=\"\" />",
            with: "<UserName Value=\"\(xmlEscape(trackName))\" />",
            options: [], range: trackXML.range(of: "<UserName Value=\"\" />"))

        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />",
            options: [], range: trackXML.range(of: "<Color Value=\"15\" />"))

        // Drum rack
        let drumRack = ALSDrumRack.build(
            pads: bank.pads,
            bankIndex: bank.bankIndex,
            projectSamplesURL: samplesURL,
            sourceDataURL: sourceDir,
            fileToCanonical: fileToCanonical,
            trackIndex: trackIndex)

        trackXML = trackXML.replacingOccurrences(
            of: "<Devices />",
            with: "<Devices>\n\(drumRack)\n\t\t\t\t\t\t</Devices>")

        // Build one MIDI clip per sequence, inject into consecutive ClipSlots
        // Note-mode pads get NO clip in the drum track (they have their own Simpler track)
        // A bank is note/chop-only if all loaded pads are note-mode or chop-mode (no drum rack needed)
        let loadedPads = bank.pads.filter { !$0.sampleFile.isEmpty }
        let hasNoteModeOnly = bank.pads.allSatisfy { pad in
            if pad.sampleFile.isEmpty { return true }
            if pad.isNoteMode { return true }
            if pad.isChopMode { return true }
            // Fallback: atem slices + only pad in bank (stale atem guard)
            let wurl = samplesURL.appendingPathComponent(pad.sampleFile)
            return loadedPads.count == 1 && WAVInfo.read(from: wurl)?.sliceStarts.isEmpty == false
        }
        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"
        if !hasNoteModeOnly {
            // Inject clips into the correct slot index matching each sequence's position.
            // Empty sequences leave their slot empty (no clip injected).
            // We consume slotTarget occurrences one by one — for empty sequences we
            // advance past the slot without replacing it by doing a dummy search.
            var searchFrom = trackXML.startIndex
            for (seqIdx, seq) in project.sequences.enumerated() {
                let hasNoteEvents = seq.events.contains {
                    bank.noteToBankIndex[$0.midiNote] == bank.bankIndex
                }
                let hasAutoEvents = bank.pads.contains { pad in
                    pad.automationEvents.contains { $0.sequenceName == seq.name }
                }
                let hasEvents = hasNoteEvents || hasAutoEvents

                if hasEvents {
                    let clipEnvelopes = ALSDrumRack.buildClipEnvelopes(
                        pads: bank.pads,
                        trackIndex: trackIndex,
                        sequenceName: seq.name,
                        ppq: project.timeSignature.pulsesPerBeat)
                    let clipXML = ALSMIDIClip.build(
                        clipName: seq.name,
                        sequence: seq,
                        bankIndex: bank.bankIndex,
                        noteToPadInBank: bank.noteToPadInBank,
                        noteToBankIndex: bank.noteToBankIndex,
                        ppq: project.timeSignature.pulsesPerBeat,
                        beatsPerBar: project.timeSignature.beatsPerBar,
                        clipEnvelopes: clipEnvelopes)
                    let slotRepl = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value>\n\(clipXML)\t\t\t\t\t\t\t\t\t</Value>\n\t\t\t\t\t\t\t\t</ClipSlot>"
                    if let r = trackXML.range(of: slotTarget, range: searchFrom..<trackXML.endIndex) {
                        trackXML = trackXML.replacingCharacters(in: r, with: slotRepl)
                        // Advance past the replaced slot
                        searchFrom = trackXML.index(r.lowerBound, offsetBy: slotRepl.count,
                                                     limitedBy: trackXML.endIndex) ?? trackXML.endIndex
                    }
                } else {
                    // Advance past this empty slot without replacing it
                    if let r = trackXML.range(of: slotTarget, range: searchFrom..<trackXML.endIndex) {
                        searchFrom = r.upperBound
                    }
                }
            }
        }

        return stripSends(from: trackXML)
    }

    // MARK: - Note mode helpers

    /// Returns the pad label e.g. "H01" from padIndex 112
    private static func padLabel(_ pad: MPCPad) -> String {
        let bankLetter = String(UnicodeScalar(UInt32(65 + pad.padIndex / 16))!)
        let padNum     = String(format: "%02d", (pad.padIndex % 16) + 1)
        return "\(bankLetter)\(padNum)"
    }

    /// Build a plain MIDI track with a Simpler-style instrument for a note-mode pad.
    /// The track name is the pad label (e.g. "H01"), clips contain transposed MIDI notes.
    private static func buildChopTrack(
        project: MPCProject,
        pad: MPCPad,
        trackName: String,
        colour: Int,
        bankIndex: Int,
        noteToBankIndex: [Int: Int],
        trackIndex: Int,
        samplesURL: URL
    ) -> String {
        guard let blankXML = try? ALSWriter.loadBlankTemplate(),
              var trackXML = extractFirstMidiTrack(from: blankXML) else { return "" }

        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        let trackId = 100 + trackIndex
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")

        // Name
        if let r = trackXML.range(of: "Value=\"1-MIDI\"") {
            trackXML = trackXML.replacingCharacters(in: r, with: "Value=\"\(xmlEscape(trackName))\"")
        }

        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />")

        // Read WAV once here and pass sliceStarts directly to avoid double-read path issues
        let chopWavInfo = WAVInfo.read(from: samplesURL.appendingPathComponent(pad.sampleFile))
        let chopSliceStarts = chopWavInfo?.sliceStarts ?? []
        // Inject Simpler in Slice mode
        let chopSampleRate = chopWavInfo?.sampleRate ?? 44100
        let simplerXML = ALSSimpler.buildSlice(pad: pad, samplesURL: samplesURL,
                                               sliceStarts: chopSliceStarts,
                                               sampleRate: chopSampleRate)
        let dcTarget = "<DeviceChain>\n\t\t\t\t\t\t<Devices />\n\t\t\t\t\t\t<SignalModulations />\n\t\t\t\t\t</DeviceChain>"
        trackXML = trackXML.replacingOccurrences(of: dcTarget, with: simplerXML)

        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"

        // Inject chop clips slot-aware
        var searchFrom = trackXML.startIndex
        for seq in project.sequences {
            let hasEvents = seq.events.contains {
                $0.midiNote == pad.midiNote && $0.chopSlice != nil
            }
            if hasEvents {
                let clipXML = ALSMIDIClip.buildChop(
                    clipName: seq.name,
                    sequence: seq,
                    pad: pad,
                    ppq: project.timeSignature.pulsesPerBeat,
                    beatsPerBar: project.timeSignature.beatsPerBar)
                let slotRepl = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value>\n\(clipXML)\t\t\t\t\t\t\t\t\t</Value>\n\t\t\t\t\t\t\t\t</ClipSlot>"
                if let r = trackXML.range(of: slotTarget, range: searchFrom..<trackXML.endIndex) {
                    trackXML = trackXML.replacingCharacters(in: r, with: slotRepl)
                    searchFrom = trackXML.index(r.lowerBound, offsetBy: slotRepl.count,
                                                limitedBy: trackXML.endIndex) ?? trackXML.endIndex
                }
            } else {
                if let r = trackXML.range(of: slotTarget, range: searchFrom..<trackXML.endIndex) {
                    searchFrom = r.upperBound
                }
            }
        }
        return stripSends(from: trackXML)
    }

    private static func buildNoteModeTrack(
        project: MPCProject,
        pad: MPCPad,
        trackName: String,
        colour: Int,
        bankIndex: Int,
        noteToBankIndex: [Int: Int],
        trackIndex: Int,
        samplesURL: URL
    ) -> String {
        guard let blankXML = try? ALSWriter.loadBlankTemplate(),
              var trackXML = extractFirstMidiTrack(from: blankXML) else { return "" }

        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        let trackId = 100 + trackIndex
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")

        // Name
        if let r = trackXML.range(of: "Value=\"1-MIDI\"") {
            trackXML = trackXML.replacingCharacters(in: r, with: "Value=\"\(xmlEscape(trackName))\"")
        }
        
        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />")

        // Replace the inner DeviceChain block with the Simpler device chain
        let simplerXML = ALSSimpler.build(pad: pad, samplesURL: samplesURL)
        let dcTarget = "<DeviceChain>\n\t\t\t\t\t\t<Devices />\n\t\t\t\t\t\t<SignalModulations />\n\t\t\t\t\t</DeviceChain>"
        trackXML = trackXML.replacingOccurrences(of: dcTarget, with: simplerXML)

        // Inject one clip per sequence with note-mode transposed notes
        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"
        var searchFrom2 = trackXML.startIndex
        for seq in project.sequences {
            let hasEvents = seq.events.contains(where: { $0.midiNote == pad.midiNote })
            if hasEvents {
                let clipXML = ALSMIDIClip.buildNoteMode(
                    clipName: seq.name,
                    sequence: seq,
                    pad: pad,
                    ppq: project.timeSignature.pulsesPerBeat,
                    beatsPerBar: project.timeSignature.beatsPerBar)
                let slotRepl = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value>\n\(clipXML)\t\t\t\t\t\t\t\t\t</Value>\n\t\t\t\t\t\t\t\t</ClipSlot>"
                if let r = trackXML.range(of: slotTarget, range: searchFrom2..<trackXML.endIndex) {
                    trackXML = trackXML.replacingCharacters(in: r, with: slotRepl)
                    searchFrom2 = trackXML.index(r.lowerBound, offsetBy: slotRepl.count,
                                                  limitedBy: trackXML.endIndex) ?? trackXML.endIndex
                }
            } else {
                if let r = trackXML.range(of: slotTarget, range: searchFrom2..<trackXML.endIndex) {
                    searchFrom2 = r.upperBound
                }
            }
        }

        return stripSends(from: trackXML)
    }

    // MARK: - Inject tracks into <Tracks> block

    private static func injectTracks(into xml: String, trackBlocks: [String]) -> String {
        // Replace the entire <Tracks> block with only our MidiTracks — no ReturnTracks.
        // We also clear <SendsPre> (one entry per return track) to stay consistent.
        guard let tOpen  = xml.range(of: "<Tracks>"),
              let tClose = xml.range(of: "</Tracks>") else { return xml }

        let before  = xml[..<tOpen.upperBound]
        let after   = xml[tClose.lowerBound...]
        let content = trackBlocks.joined(separator: "\n\t\t\t")
        var result  = before + "\n\t\t\t" + content + "\n\t\t\t" + after

        // Strip <SendsPre> entries — one per return track; none = no return tracks
        result = result.replacingOccurrences(
            of: #"<SendsPre>[\s\S]*?</SendsPre>"#,
            with: "<SendsPre />",
            options: .regularExpression
        )

        return result
    }

    // Strip <Sends> block from a MidiTrack — called per track before injection
    private static func stripSends(from trackXML: String) -> String {
        trackXML.replacingOccurrences(
            of: #"<Sends>[\s\S]*?</Sends>"#,
            with: "<Sends />",
            options: .regularExpression
        )
    }

    // MARK: - Helpers

    private static func extractFirstMidiTrack(from xml: String) -> String? {
        guard let start = xml.range(of: "<MidiTrack Id=") else { return nil }
        var depth = 0
        var pos   = start.lowerBound
        while pos < xml.endIndex {
            if xml[pos...].hasPrefix("<MidiTrack") {
                depth += 1; pos = xml.index(pos, offsetBy: 10)
            } else if xml[pos...].hasPrefix("</MidiTrack") {
                depth -= 1
                if depth == 0 {
                    let end = xml.index(pos, offsetBy: "</MidiTrack>".count)
                    return String(xml[start.lowerBound..<end])
                }
                pos = xml.index(pos, offsetBy: 11)
            } else {
                pos = xml.index(after: pos)
            }
        }
        return nil
    }

    /// Remap every Id="N" in a track copy to a fresh unique range.
    /// Each track gets a block of 600 IDs starting at 50000 + trackIndex*600.
    /// This prevents collisions when multiple tracks are copied from the same blank template.
    private static func remapTrackIds(_ xml: String, trackIndex: Int) -> String {
        let base    = 200_000 + trackIndex * 600
        var counter = base
        var seen    = [String: String]()

        // Two-pass: first build the mapping, then rebuild the string
        let pattern = try! NSRegularExpression(pattern: #" Id="(\d+)""#)
        let ns      = xml as NSString
        let nsRange = NSRange(location: 0, length: ns.length)
        let matches = pattern.matches(in: xml, range: nsRange)

        // Pass 1: assign new IDs in document order
        // Only remap IDs >= 12 — IDs 0-7 repeat legitimately within a track
        // (LomId, ClipSlot indices etc.) and must be left unchanged.
        for m in matches {
            guard let r = Range(m.range(at: 1), in: xml) else { continue }
            let old = String(xml[r])
            guard let oldInt = Int(old), oldInt >= 12 else { continue }
            if seen[old] == nil { seen[old] = "\(counter)"; counter += 1 }
        }

        // Pass 2: rebuild string by walking matches and splicing in new values
        var result  = ""
        var lastEnd = xml.startIndex
        for m in matches {
            guard let full = Range(m.range(at: 0), in: xml),
                  let vr   = Range(m.range(at: 1), in: xml) else { continue }
            let old    = String(xml[vr])
            let newId  = seen[old] ?? old
            // Append everything up to the Id value, then the new value
            result += xml[lastEnd..<vr.lowerBound]
            result += newId
            lastEnd = vr.upperBound
        }
        result += xml[lastEnd...]
        return result
    }

    private static func replace(_ s: String, pattern: String, with replacement: String) -> String {
        (try? NSRegularExpression(pattern: pattern))
            .map { $0.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: replacement) } ?? s
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
    // MARK: - WAV utilities

    /// Reverse audio sample frames in a WAV, preserving all non-data chunks.
    private static func reverseWAV(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        guard bytes.count > 12,
              bytes[0...3].elementsEqual([0x52,0x49,0x46,0x46]),
              bytes[8...11].elementsEqual([0x57,0x41,0x56,0x45])
        else { return data }

        var pos = 12; var dataStart = -1; var dataSize = 0
        var channels = 1; var bitsPerSample = 16

        while pos + 8 <= bytes.count {
            let tag  = Array(bytes[pos..<pos+4])
            let size = Int(UInt32(bytes[pos+4]) | UInt32(bytes[pos+5])<<8
                         | UInt32(bytes[pos+6])<<16 | UInt32(bytes[pos+7])<<24)
            pos += 8
            if tag == [0x66,0x6d,0x74,0x20] { // fmt
                channels      = Int(UInt16(bytes[pos+2]) | UInt16(bytes[pos+3])<<8)
                bitsPerSample = Int(UInt16(bytes[pos+14]) | UInt16(bytes[pos+15])<<8)
            } else if tag == [0x64,0x61,0x74,0x61] { // data
                dataStart = pos; dataSize = size; break
            }
            if size > bytes.count { break }
            pos += size + (size & 1)
        }
        guard dataStart >= 0 else { return data }

        let frameBytes = channels * (bitsPerSample / 8)
        let frameCount = dataSize / frameBytes
        var frames = Array(bytes[dataStart..<dataStart + frameCount * frameBytes])
        for i in 0..<(frameCount / 2) {
            let j = frameCount - 1 - i
            let a = i * frameBytes, b = j * frameBytes
            for k in 0..<frameBytes { frames.swapAt(a + k, b + k) }
        }
        bytes.replaceSubrange(dataStart..<dataStart + frameCount * frameBytes, with: frames)
        return Data(bytes)
    }

}
