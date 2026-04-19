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

        // Expand Scenes to cover all sequences (template has 8; MPC projects can have more)
        xml = ALSWriter.expandScenes(xml, to: project.sequences.count)

        // Inject master bus compressor if the XPJ had one
        if let compState = project.masterCompressor {
            xml = ALSWriter.injectMasterCompressor(xml, state: compState)
        }

        // Per-scene BPM: only applies when the project uses per-sequence tempo.
        // Global-BPM projects already have the correct tempo set by setBPM above;
        // touching individual scenes would add coloured arrows in Ableton's session
        // view without any benefit — so we skip scene-level tempo for those projects.
        let totalScenes = max(8, project.sequences.count)
        if !project.masterTempoEnabled {
            let sceneTempos = project.sequences.map { (name: $0.name, bpm: $0.bpm) }
            xml = ALSWriter.setSceneBPMs(xml, sequences: sceneTempos, masterBPM: project.bpm,
                                         totalScenes: totalScenes)
        }

        // ── Choke group pool for 16-Levels Filter/Tune tracks ────────────────────────────
        // Collect choke groups already in use by regular pads (mute groups 1–16).
        // Then build a pool descending from 16, skipping occupied slots, so we avoid
        // stepping on groups the user deliberately set up.
        let usedChokeGroups = Set(
            (project.drumTrack?.pads ?? [])
                .map { min($0.muteGroup, 16) }
                .filter { $0 > 0 }
        )
        var chokePool = Array((1...16).reversed().filter { !usedChokeGroups.contains($0) })

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
                // Read WAV from sourceDir using the pad's own original filename.
                // Using samplesDir/canonicalFile here would give the wrong ATEM data when
                // two pads share the same base sample but have different manual chop positions
                // (MPC saves them as "Sample.wav" and "Sample001.wav" with different atem chunks).
                let wavURL   = sourceDir.appendingPathComponent(pad.sampleFile)
                let wavInfo  = WAVInfo.read(from: wavURL)
                let hasAtemSlices = wavInfo?.sliceStarts.isEmpty == false
                let isChop   = pad.isChopMode || (hasAtemSlices && loadedPadsInBank.count == 1)
                guard isChop else { continue }
                let padName  = padLabel(pad) + " Chop"   // e.g. "A01 Chop"
                let colour2  = trackColours[trackCounter % trackColours.count]
                let block2   = buildChopTrack(project: project, pad: pad,
                                              trackName: padName, colour: colour2,
                                              bankIndex: bank.bankIndex,
                                              noteToBankIndex: bank.noteToBankIndex,
                                              trackIndex: trackCounter,
                                              samplesURL: samplesDir,
                                              sourceDir: sourceDir,
                                              fileToCanonical: fileToCanonical)
                trackBlocks.append(block2)
                trackCounter += 1
            }

            // For each note-mode pad in this bank, add a Simpler MIDI track
            for pad in bank.pads where pad.isNoteMode {
                let padName      = padLabel(pad) + " Tune"   // e.g. "H01 Tune"
                let tuneChoke    = chokePool.isEmpty ? 0 : chokePool.removeFirst()
                let colour2  = trackColours[trackCounter % trackColours.count]
                let block2   = buildNoteModeTrack(project: project, pad: pad,
                                                  trackName: padName, colour: colour2,
                                                  chokeGroup: tuneChoke,
                                                  bankIndex: bank.bankIndex,
                                                  noteToBankIndex: bank.noteToBankIndex,
                                                  trackIndex: trackCounter,
                                                  samplesURL: samplesDir,
                                                  fileToCanonical: fileToCanonical)
                trackBlocks.append(block2)
                trackCounter += 1
            }

            // For each filter-mode pad in this bank, add a Drum Rack MIDI track where
            // each unique filter cutoff value gets its own Simpler slot.
            for pad in bank.pads where pad.isFilterMode {
                let padName      = padLabel(pad) + " Filter"
                let filterChoke  = chokePool.isEmpty ? 0 : chokePool.removeFirst()
                let colour2  = trackColours[trackCounter % trackColours.count]
                let block2   = buildFilterModeTrack(project: project, pad: pad,
                                                    trackName: padName, colour: colour2,
                                                    chokeGroup: filterChoke,
                                                    bankIndex: bank.bankIndex,
                                                    trackIndex: trackCounter,
                                                    samplesURL: samplesDir,
                                                    sourceDir: sourceDir,
                                                    fileToCanonical: fileToCanonical)
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

        // Expand ClipSlots before anything else so all sequences have a slot
        trackXML = expandClipSlots(trackXML, to: project.sequences.count)

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

        // Build one MIDI clip per sequence, inject into consecutive ClipSlots.
        // Tune-mode events (tuningModifier != nil) are excluded here — they route to the
        // pad's own Simpler track. Velocity-mode events for note-mode pads DO appear here.
        // The per-sequence hasNoteEvents check filters out sequences with only tune events
        // so we never produce spurious empty clips for tune-only sequences.
        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"
        var searchFrom = trackXML.startIndex
        for seq in project.sequences {
            // Only count events that will actually appear in the drum rack clip:
            // — belongs to this bank AND is not a 16 Levels Tune or Filter event
            // (filter events are routed to their own filter-mode drum rack tracks)
            let hasNoteEvents = seq.events.contains {
                guard bank.noteToBankIndex[$0.midiNote] == bank.bankIndex else { return false }
                return $0.tuningModifier == nil && $0.filterModifier == nil
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
        samplesURL: URL,
        sourceDir: URL,
        fileToCanonical: [String: String] = [:]
    ) -> String {
        guard let blankXML = try? ALSWriter.loadBlankTemplate(),
              var trackXML = extractFirstMidiTrack(from: blankXML) else { return "" }

        // Expand ClipSlots before anything else so all sequences have a slot
        trackXML = expandClipSlots(trackXML, to: project.sequences.count)

        // Track name — set both EffectiveName and UserName.
        // Without UserName, Ableton auto-names the track from the instrument ("Simpler").
        if let r = trackXML.range(of: "Value=\"1-MIDI\"") {
            trackXML = trackXML.replacingCharacters(in: r, with: "Value=\"\(xmlEscape(trackName))\"")
        }
        if let r = trackXML.range(of: "<UserName Value=\"\" />") {
            trackXML = trackXML.replacingCharacters(in: r,
                with: "<UserName Value=\"\(xmlEscape(trackName))\" />")
        }

        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />")

        // Use canonical filename so the ALS RelativePath points to the file that was copied.
        let canonicalFile = fileToCanonical[pad.sampleFile] ?? pad.sampleFile
        // Read ATEM slice data from the pad's OWN source file, not the canonical copy.
        // Two pads can share the same audio content (deduped to one canonical WAV) but have
        // different manual chop positions stored in each file's atem chunk — e.g. "Beat.wav"
        // and "Beat001.wav". Reading from sourceDir/originalFile gives the correct slices
        // for each pad independently.
        let sourceWavURL    = sourceDir.appendingPathComponent(pad.sampleFile)
        let chopWavInfo     = WAVInfo.read(from: sourceWavURL)
        let chopSliceStarts = chopWavInfo?.sliceStarts ?? []
        // Inject Simpler in Slice mode
        let chopSampleRate = chopWavInfo?.sampleRate ?? 44100
        let simplerXML = ALSSimpler.buildSlice(pad: pad, samplesURL: samplesURL,
                                               sliceStarts: chopSliceStarts,
                                               sampleRate: chopSampleRate,
                                               canonicalFile: canonicalFile)
        let dcTarget = "<DeviceChain>\n\t\t\t\t\t\t<Devices />\n\t\t\t\t\t\t<SignalModulations />\n\t\t\t\t\t</DeviceChain>"
        trackXML = trackXML.replacingOccurrences(of: dcTarget, with: simplerXML)

        // Remap all IDs AFTER Simpler injection so the Simpler's hardcoded IDs
        // (25107-25297) get uniquified per-track alongside the template IDs.
        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        // Set MidiTrack Id explicitly (overrides whatever remapTrackIds assigned)
        let trackId = 100 + trackIndex
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")

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
        chokeGroup: Int = 0,
        bankIndex: Int,
        noteToBankIndex: [Int: Int],
        trackIndex: Int,
        samplesURL: URL,
        fileToCanonical: [String: String] = [:]
    ) -> String {
        guard let blankXML = try? ALSWriter.loadBlankTemplate(),
              var trackXML = extractFirstMidiTrack(from: blankXML) else { return "" }

        // Expand ClipSlots before anything else so all sequences have a slot
        trackXML = expandClipSlots(trackXML, to: project.sequences.count)

        // Track name — set both EffectiveName and UserName.
        // Without UserName, Ableton auto-names the track from the instrument ("Simpler").
        if let r = trackXML.range(of: "Value=\"1-MIDI\"") {
            trackXML = trackXML.replacingCharacters(in: r, with: "Value=\"\(xmlEscape(trackName))\"")
        }
        if let r = trackXML.range(of: "<UserName Value=\"\" />") {
            trackXML = trackXML.replacingCharacters(in: r,
                with: "<UserName Value=\"\(xmlEscape(trackName))\" />")
        }

        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />")

        // Replace the inner DeviceChain block with the Simpler device chain.
        // Use canonical filename so the sample path matches what was actually copied.
        let canonicalFile = fileToCanonical[pad.sampleFile] ?? pad.sampleFile
        let simplerXML = ALSSimpler.build(pad: pad, samplesURL: samplesURL,
                                          canonicalFile: canonicalFile)
        let dcTarget = "<DeviceChain>\n\t\t\t\t\t\t<Devices />\n\t\t\t\t\t\t<SignalModulations />\n\t\t\t\t\t</DeviceChain>"
        trackXML = trackXML.replacingOccurrences(of: dcTarget, with: simplerXML)

        // Tune-mode Simpler: set to 1 voice so each new note cuts the previous one.
        // A Simpler on a plain MIDI track has no BranchInfo/ChokeGroup, so NumVoices=1
        // is the equivalent mechanism. Only applied when a choke group was available.
        if chokeGroup > 0 {
            trackXML = trackXML.replacingOccurrences(
                of: "<NumVoices Value=\"2\" />",
                with: "<NumVoices Value=\"1\" />")
        }

        // Remap all IDs AFTER Simpler injection so the Simpler's hardcoded IDs
        // (25107-25297) get uniquified per-track alongside the template IDs.
        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        // Set MidiTrack Id explicitly (overrides whatever remapTrackIds assigned)
        let trackId = 100 + trackIndex
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")


        // Inject one clip per sequence — only for sequences where this pad has
        // actual 16 Levels Tune events (tuningModifier != nil). Velocity-mode sequences
        // for this pad stay in the drum rack track, not here.
        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"
        var searchFrom2 = trackXML.startIndex
        for seq in project.sequences {
            let hasTuneEvents = seq.events.contains(where: {
                $0.midiNote == pad.midiNote && $0.tuningModifier != nil
            })
            if hasTuneEvents {
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

    // MARK: - Filter mode (16 Levels Filter) track builder

    /// Build a MIDI track with a Drum Rack for a filter-mode pad.
    /// Each unique filterModifier value across all sequences gets its own Simpler slot
    /// (padInBank 0, 1, 2 …) with the pad's sample and the corresponding filter cutoff.
    /// MIDI clips trigger slots via note 36+padInBank, matching the standard drum-rack convention.
    private static func buildFilterModeTrack(
        project: MPCProject,
        pad: MPCPad,
        trackName: String,
        colour: Int,
        chokeGroup: Int = 0,
        bankIndex: Int,
        trackIndex: Int,
        samplesURL: URL,
        sourceDir: URL,
        fileToCanonical: [String: String] = [:]
    ) -> String {
        guard let blankXML = try? ALSWriter.loadBlankTemplate(),
              var trackXML = extractFirstMidiTrack(from: blankXML) else { return "" }

        trackXML = expandClipSlots(trackXML, to: project.sequences.count)

        // Track name — set both EffectiveName and UserName.
        // Without UserName, Ableton auto-names the track from the instrument ("Drum Rack").
        if let r = trackXML.range(of: "Value=\"1-MIDI\"") {
            trackXML = trackXML.replacingCharacters(in: r, with: "Value=\"\(xmlEscape(trackName))\"")
        }
        if let r = trackXML.range(of: "<UserName Value=\"\" />") {
            trackXML = trackXML.replacingCharacters(in: r,
                with: "<UserName Value=\"\(xmlEscape(trackName))\" />")
        }
        // Colour
        trackXML = trackXML.replacingOccurrences(
            of: "<Color Value=\"15\" />",
            with: "<Color Value=\"\(colour)\" />")

        // ── Fixed 16-slot cutoff ladder ──────────────────────────────────────────────────
        // MPC 16 Levels Filter always uses the same 16 absolute cutoff values regardless
        // of the pad's base filterCutoff or filter type:  (8k - 1) / 127  for k = 1…16
        // i.e. 7/127, 15/127, 23/127, … 127/127 (step = 8/127 ≈ 0.063).
        // We pre-populate all 16 slots so the rack is complete even if only some were
        // played during recording, preserving the filter type (LPF / HPF / BPF etc.)
        // from the original pad across every slot.
        let sortedValues: [Double] = (1...16).map { k in (Double(8 * k - 1)) / 127.0 }
        // No valueToIndex dict needed — buildFilterMode now computes slot index analytically.

        // ── Build fake pads: same sample, different filterCutoff, sequential padIndex ──
        // sampleFile set to the canonical filename so ALSDrumRack resolves the path correctly.
        let canonicalFile = fileToCanonical[pad.sampleFile] ?? pad.sampleFile
        var filterPads: [MPCPad] = []
        for (i, cutoff) in sortedValues.enumerated() {
            // Ensure a filter is active: if the pad had filterType=0 (off), use Classic (29 = LP24)
            let fType = pad.filterType == 0 ? 29 : pad.filterType
            filterPads.append(MPCPad(
                padIndex:            i,
                midiNote:            36 + i,       // placeholder — drum rack uses padInBank only
                sampleFile:          canonicalFile,
                sampleName:          pad.sampleName,
                coarseTune:          pad.coarseTune,
                fineTune:            pad.fineTune,
                volume:              pad.volume,
                pan:                 pad.pan,
                sliceInfoStart:      pad.sliceInfoStart,
                sliceInfoEnd:        pad.sliceInfoEnd,
                sliceInfoLoopStart:  pad.sliceInfoLoopStart,
                oneShot:             pad.oneShot,
                reverse:             pad.reverse,
                isNoteMode:          false,
                rootNote:            pad.rootNote,
                isChopMode:          false,
                chopRegions:         0,
                chopMode:            0,
                sliceStarts:         [],
                loadImpl:            pad.loadImpl,
                warpEnable:          pad.warpEnable,
                nativeBPM:           pad.nativeBPM,
                isGateMode:          pad.isGateMode,
                layerLoop:           pad.layerLoop,
                muteGroup:           chokeGroup,   // all 16 slots share the same group → choke each other
                monophonic:          pad.monophonic,
                ampAttack:           pad.ampAttack,
                ampDecay:            pad.ampDecay,
                ampRelease:          pad.ampRelease,
                layerOffset:         pad.layerOffset,
                filterType:          fType,
                filterCutoff:        cutoff,
                filterResonance:     pad.filterResonance,
                muted:               false,
                automationEvents:    [],
                isFilterMode:        false
            ))
        }

        // ── Build drum rack with the filter-variant pads (bankIndex 0 → notes 36+) ──
        let drumRack = ALSDrumRack.build(
            pads: filterPads,
            bankIndex: 0,
            projectSamplesURL: samplesURL,
            sourceDataURL: sourceDir,
            fileToCanonical: fileToCanonical,
            trackIndex: trackIndex)

        trackXML = trackXML.replacingOccurrences(
            of: "<Devices />",
            with: "<Devices>\n\(drumRack)\n\t\t\t\t\t\t</Devices>")

        // Remap IDs after drum rack injection
        trackXML = remapTrackIds(trackXML, trackIndex: trackIndex)

        let trackId = 100 + trackIndex
        trackXML = replace(trackXML,
            pattern: #"<MidiTrack Id="\d+""#,
            with: "<MidiTrack Id=\"\(trackId)\"")

        // ── One clip per sequence that has filter events for this pad ──
        let slotTarget = "<ClipSlot>\n\t\t\t\t\t\t\t\t\t<Value />\n\t\t\t\t\t\t\t\t</ClipSlot>"
        var searchFrom = trackXML.startIndex
        for seq in project.sequences {
            let hasEvents = seq.events.contains {
                $0.midiNote == pad.midiNote && $0.filterModifier != nil
            }
            if hasEvents {
                let clipXML = ALSMIDIClip.buildFilterMode(
                    clipName:    seq.name,
                    sequence:    seq,
                    pad:         pad,
                    ppq:         project.timeSignature.pulsesPerBeat,
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

    /// Expand ALL ClipSlotList sections of a MidiTrack to hold `count` slots.
    /// The blank template has 8 slots (Ids 0–7); this appends blank slots for Ids 8+.
    /// A MidiTrack has two ClipSlotLists (main sequencer + freeze sequencer) — both
    /// must have the same slot count as the Scene count or Live rejects the file with
    /// "Slot count mismatch". No-op if `count` ≤ 8.
    private static func expandClipSlots(_ xml: String, to count: Int) -> String {
        guard count > 8 else { return xml }

        // Build blank slot entries for Ids 8..<count
        let t7 = String(repeating: "\t", count: 7)
        let t8 = String(repeating: "\t", count: 8)
        let t9 = String(repeating: "\t", count: 9)
        var extra = ""
        for i in 8..<count {
            extra += "\n\(t7)<ClipSlot Id=\"\(i)\">"
            extra += "\n\(t8)<LomId Value=\"0\" />"
            extra += "\n\(t8)<ClipSlot>"
            extra += "\n\(t9)<Value />"
            extra += "\n\(t8)</ClipSlot>"
            extra += "\n\(t8)<HasStop Value=\"true\" />"
            extra += "\n\(t8)<NeedRefreeze Value=\"true\" />"
            extra += "\n\(t7)</ClipSlot>"
        }
        // Replace ALL </ClipSlotList> occurrences — both MainSequencer and FreezeSequencer
        // lists must have the same count as the Scene count.
        // Match the full indented line so the close tag stays properly indented after.
        let closeTag = "\n\t\t\t\t\t\t</ClipSlotList>"
        return xml.replacingOccurrences(of: closeTag, with: extra + closeTag)
    }

    /// Remap every Id="N" in a track copy to a fresh unique range.
    /// Each track gets a block of 2000 IDs starting at 200_000 + trackIndex*2000.
    /// This prevents collisions when multiple tracks are copied from the same blank template,
    /// and is large enough to cover both the MidiTrack template (~160 IDs) and the
    /// Simpler template (~191 IDs) when Simpler is injected before remapping.
    private static func remapTrackIds(_ xml: String, trackIndex: Int) -> String {
        let base    = 200_000 + trackIndex * 2_000
        var counter = base
        var seen    = [String: String]()

        // Two-pass: first build the mapping, then rebuild the string
        let pattern = try! NSRegularExpression(pattern: #" Id="(\d+)""#)
        let ns      = xml as NSString
        let nsRange = NSRange(location: 0, length: ns.length)
        let matches = pattern.matches(in: xml, range: nsRange)

        // Pass 1: assign new IDs in document order.
        // Only remap MIDI template IDs (12–29_999). Drum rack branch IDs (≥30_000)
        // and filter device IDs (≥400_000) are already unique per-trackIndex from
        // ALSDrumRack's own remapNumericIds — remapping them here overflows the
        // 2000-ID block and causes "non-unique Pointee IDs" in Ableton.
        for m in matches {
            guard let r = Range(m.range(at: 1), in: xml) else { continue }
            let old = String(xml[r])
            guard let oldInt = Int(old), oldInt >= 12, oldInt < 30_000 else { continue }
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
