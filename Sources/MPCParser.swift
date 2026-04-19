// MPCParser.swift
// Parses Akai MPC firmware 3.x .xpj project files into MPCProject.
//
// FILE FORMAT
// .xpj = 5-line ASCII header + gzip-compressed JSON
//   Line 1: "ACVS"
//   Line 2: version string (e.g. "1.2.1.2")
//   Line 3: "SerialisableProjectData"
//   Line 4: "json"
//   Line 5: "Linux"
//   Remainder: gzip data (magic bytes 0x1f 0x8b)
//
// We locate the gzip magic bytes, strip the header, then decompress.
// The JSON root is { "data": { ... } }.

import Foundation

enum MPCParserError: Error, CustomStringConvertible {
    case cannotReadFile(String)
    case decompressionFailed
    case jsonNotFound
    case jsonParseFailed(String)
    case missingField(String)
    case noSequences

    var description: String {
        switch self {
        case .cannotReadFile(let p):  return "Cannot read file: \(p)"
        case .decompressionFailed:    return "Failed to decompress .xpj (bad gzip?)"
        case .jsonNotFound:           return "No JSON object found in .xpj"
        case .jsonParseFailed(let m): return "JSON parse error: \(m)"
        case .missingField(let f):    return "Missing expected field: \(f)"
        case .noSequences:            return "Project contains no sequences"
        }
    }
}

struct MPCParser {

    // MARK: - Public

    static func parse(url: URL) throws -> MPCProject {
        let raw = try readAndDecompress(url: url)

        // Locate JSON payload (skip any remaining header text before '{')
        guard let jsonStart = raw.range(of: "{") else {
            throw MPCParserError.jsonNotFound
        }
        let jsonString = String(raw[jsonStart.lowerBound...])

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw MPCParserError.jsonParseFailed("UTF-8 conversion failed")
        }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw MPCParserError.jsonParseFailed("Root is not an object")
            }
            root = obj
        } catch {
            throw MPCParserError.jsonParseFailed(error.localizedDescription)
        }

        guard let data = root["data"] as? [String: Any] else {
            throw MPCParserError.missingField("data")
        }

        let name      = url.deletingPathExtension().lastPathComponent
        let bpm       = extractBPM(from: data)
        let masterTempoEnabled = data["masterTempoEnabled"] as? Bool ?? false
        let sequences = try parseAllSequences(from: data, masterBPM: bpm,
                                              masterTempoEnabled: masterTempoEnabled)
        let drumTrack = parseDrumTrack(from: data)
        let ts        = parseTimeSig(from: data)
        let masterCompressor = parseMasterCompressor(from: data)

        return MPCProject(
            name: name,
            bpm: bpm,
            masterTempoEnabled: masterTempoEnabled,
            timeSignature: ts,
            lengthBars: extractLengthBars(from: data),
            drumTrack: drumTrack,
            sequences: sequences,
            masterCompressor: masterCompressor
        )
    }

    // MARK: - File reading

    private static func readAndDecompress(url: URL) throws -> String {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw MPCParserError.cannotReadFile(url.path)
        }

        let bytes = [UInt8](fileData)

        // .xpj has an ACVS text header before the gzip stream.
        // Scan up to 512 bytes for gzip magic 0x1f 0x8b.
        var gzipOffset: Int? = nil
        for i in 0..<min(512, bytes.count - 1) {
            if bytes[i] == 0x1f && bytes[i + 1] == 0x8b {
                gzipOffset = i
                break
            }
        }

        if let offset = gzipOffset {
            // Found gzip stream — decompress from offset
            let compressed = fileData.subdata(in: offset..<fileData.count)
            do {
                return try ALSWriter.gunzip(compressed)
            } catch {
                throw MPCParserError.decompressionFailed
            }
        } else {
            // No gzip magic — try treating the whole file as plain UTF-8 JSON
            if let text = String(data: fileData, encoding: .utf8) { return text }
            throw MPCParserError.decompressionFailed
        }
    }

    // MARK: - Sequence parsing

    private static func parseAllSequences(from data: [String: Any], masterBPM: Double,
                                              masterTempoEnabled: Bool = false) throws -> [MPCSequence] {
        guard let rawSeqs = data["sequences"] as? [[String: Any]], !rawSeqs.isEmpty else {
            throw MPCParserError.noSequences
        }

        // Sort by key so sequences appear in the right order
        let sorted = rawSeqs.sorted { ($0["key"] as? Int ?? 0) < ($1["key"] as? Int ?? 0) }

        return sorted.compactMap { raw in
            guard let value = raw["value"] as? [String: Any] else { return nil }
            let seqName    = value["name"] as? String ?? "Sequence 01"
            // If masterTempoEnabled, global tempo overrides sequence-level tempo
            let seqBpm     = masterTempoEnabled ? masterBPM
                           : (value["bpm"] as? Double ?? masterBPM)
            let lengthBars = value["lengthBars"] as? Int ?? 1
            let ppb        = parsePulsesPerBeat(from: value)
            let totalPulses = lengthBars * 4 * ppb

            guard let clipMaps = value["trackClipMaps"] as? [[[String: Any]]],
                  let firstRow = clipMaps.first,
                  let firstClip = firstRow.first,
                  let clipValue = firstClip["value"] as? [String: Any],
                  let trackName = firstClip["key"] as? String else {
                return MPCSequence(name: seqName, trackName: "", events: [], lengthPulses: totalPulses, bpm: seqBpm)
            }
            let events = parseEvents(from: clipValue)
            return MPCSequence(name: seqName, trackName: trackName,
                               events: events, lengthPulses: totalPulses, bpm: seqBpm)
        }
    }

    private static func parseEvents(from clipValue: [String: Any]) -> [MPCNoteEvent] {
        guard let eventList = clipValue["eventList"] as? [String: Any],
              let rawEvents = eventList["events"] as? [[String: Any]] else { return [] }

        var result: [MPCNoteEvent] = []
        for ev in rawEvents {
            guard let type = ev["type"] as? Int, type == 3,
                  let noteData = ev["note"] as? [String: Any],
                  let note     = noteData["note"] as? Int,
                  let velocity = noteData["velocity"] as? Double,
                  let length   = noteData["length"] as? Int,
                  let time     = ev["time"] as? Int,
                  !(ev["muted"] as? Bool ?? false) else { continue }

            // Read tuning modifier (slot 0) — set in 16 Levels Tune mode
            let tuning: Double?
            if let active = noteData["modifierActiveState0"] as? Bool, active,
               let val    = noteData["modifierValue0"]       as? Double {
                tuning = val
            } else {
                tuning = nil
            }
            // Read chop slice (slot 15) — set in Chop mode
            let chopSlice: Int?
            if let active = noteData["modifierActiveState15"] as? Bool, active,
               let val    = noteData["modifierValue15"]       as? Double {
                chopSlice = Int((val * 127.0).rounded())
            } else {
                chopSlice = nil
            }
            // Read filter cutoff modifier (slot 2) — set in 16 Levels Filter mode
            // The value is already an absolute normalised cutoff (0-1); use directly.
            let filterMod: Double?
            if let active = noteData["modifierActiveState2"] as? Bool, active,
               let val    = noteData["modifierValue2"]       as? Double {
                filterMod = val
            } else {
                filterMod = nil
            }
            result.append(MPCNoteEvent(timePulses: time, midiNote: note,
                                       velocity: velocity, lengthPulses: length,
                                       tuningModifier: tuning, chopSlice: chopSlice,
                                       filterModifier: filterMod))
        }
        return result.sorted { $0.timePulses < $1.timePulses }
    }

    // MARK: - Drum track parsing

    private static func parseDrumTrack(from data: [String: Any]) -> MPCDrumTrack? {
        guard let tracks = data["tracks"] as? [[String: Any]] else { return nil }

        for track in tracks {
            guard let program = track["program"] as? [String: Any],
                  let drum = program["drum"] as? [String: Any],
                  let instruments = drum["instruments"] as? [[String: Any]] else { continue }

            let name    = track["name"] as? String ?? "Drum 001"
            let vol     = track["volume"] as? Double ?? 1.0
            let pan     = track["pan"]    as? Double ?? 0.5
            let samples = track["samples"] as? [[String: Any]] ?? []

            let noteForPad = (program["padNoteMap"] as? [String: Any])?["noteForPad"]
                as? [String: Int] ?? [:]

            // Build set of MIDI notes that are note-mode (modifier0), chop-mode (modifier15),
            // or filter-mode (modifier2 = 16 Levels Filter)
            var noteModeNotes   = Set<Int>()
            var chopModeNotes   = Set<Int>()
            var filterModeNotes = Set<Int>()
            if let sequences = data["sequences"] as? [[String: Any]] {
                for seq in sequences {
                    if let seqVal = seq["value"] as? [String: Any],
                       let clipMaps = seqVal["trackClipMaps"] as? [[[String: Any]]] {
                        for row in clipMaps {
                            for clip in row {
                                if let clipVal = clip["value"] as? [String: Any],
                                   let evList = clipVal["eventList"] as? [String: Any],
                                   let events = evList["events"] as? [[String: Any]] {
                                    for ev in events {
                                        if let t = ev["type"] as? Int, t == 3,
                                           let n = ev["note"] as? [String: Any],
                                           let pitch = n["note"] as? Int {
                                            // Slot 0 active = 16 Levels Tune
                                            if let active = n["modifierActiveState0"] as? Bool, active {
                                                noteModeNotes.insert(pitch)
                                            }
                                            // Slot 2 active = 16 Levels Filter
                                            if let active = n["modifierActiveState2"] as? Bool, active {
                                                filterModeNotes.insert(pitch)
                                            }
                                            // Slot 15 active = Chop mode
                                            if let active = n["modifierActiveState15"] as? Bool, active {
                                                chopModeNotes.insert(pitch)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // rootNote from track.samples metadata (matched by filename)
            let trackSamples = track["samples"] as? [[String: Any]] ?? []

    
        // ── Build note→automation-events map from all sequences (type=2 events) ────
        var noteAutoEvents: [Int: [MPCAutomationEvent]] = [:]
        let sequences = data["sequences"] as? [[String: Any]] ?? []
        for seqEntry in sequences {
            guard let seqVal = seqEntry["value"] as? [String: Any],
                  let clipMaps = seqVal["trackClipMaps"] as? [[[String: Any]]] else { continue }
            for row in clipMaps {
                for clip in row {
                    guard let clipVal = clip["value"] as? [String: Any],
                          let evtList = clipVal["eventList"] as? [String: Any],
                          let events  = evtList["events"]   as? [[String: Any]] else { continue }
                    for evt in events {
                        guard let typeVal = evt["type"] as? Int, typeVal == 2,
                              let auto = evt["automation"] as? [String: Any],
                              let note  = auto["note"]      as? Int,
                              let param = auto["parameter"] as? Int,
                              let val   = auto["value"]     as? Double,
                              let time  = evt["time"]       as? Int else { continue }
                        let seqName = seqVal["name"] as? String ?? ""
                        noteAutoEvents[note, default: []].append(
                            MPCAutomationEvent(sequenceName: seqName, time: time,
                                               parameter: param, value: val))
                    }
                }
            }
        }
        // Sort events by time within each note
        for key in noteAutoEvents.keys {
            noteAutoEvents[key]?.sort { $0.time < $1.time }
        }

        var pads: [MPCPad] = []
            for (padIdx, inst) in instruments.enumerated() {
                guard let layers = inst["layersv"] as? [[String: Any]],
                      let layer  = layers.first,
                      let sf     = layer["sampleFile"] as? String,
                      !sf.isEmpty else { continue }

                let midiNote   = noteForPad["value\(padIdx)"] ?? (36 + padIdx)
                let sampleName = layer["sampleName"] as? String ?? sf
                // loadImpl: 0=project-embedded, 1=load from device library
                let loadImpl   = (samples.first { ($0["path"] as? String)?.hasSuffix(sf) == true })?["loadImpl"] as? Int ?? 0
                let layerVol   = (layer["volume"] as? [String: Any])?["gainCoefficient"] as? Double ?? 1.0
                let layerPan   = layer["pan"]    as? Double ?? 0.5
                let coarse     = layer["coarseTune"] as? Int ?? 0
                let fine       = layer["fineTune"]   as? Int ?? 0
                let warpEn     = inst["warpEnable"]  as? Bool ?? false
                let nativeBPM  = inst["tempo"]       as? Double ?? 0.0
                let direction  = layer["direction"]  as? Int  ?? 0
                let trigMode   = inst["triggerMode"] as? Int  ?? 0
                let muteGroup  = inst["whichMuteGroup"] as? Int ?? 0
                let monophonic = inst["monophonic"]  as? Bool ?? true
                let layerLoop  = layer["loop"]       as? Bool ?? false
                let layerOffset = layer["offset"]    as? Int  ?? 0

                // Amplitude envelope from synthSection.ampEnvelope
                let ampAttack: Double = {
                    if let ss  = inst["synthSection"] as? [String: Any],
                       let env = ss["ampEnvelope"]    as? [String: Any],
                       let v   = (env["Attack"]       as? [String: Any])?["value0"] as? Double {
                        return v
                    }
                    return 0.015748
                }()
                let ampDecay: Double = {
                    if let ss  = inst["synthSection"] as? [String: Any],
                       let env = ss["ampEnvelope"]    as? [String: Any],
                       let v   = (env["Decay"]        as? [String: Any])?["value0"] as? Double {
                        return v
                    }
                    return 0.047244
                }()
                let ampRelease: Double = {
                    if let ss  = inst["synthSection"] as? [String: Any],
                       let env = ss["ampEnvelope"]    as? [String: Any],
                       let v   = (env["Release"]      as? [String: Any])?["value0"] as? Double {
                        return v
                    }
                    return 0.0
                }()

                // Filter from synthSection.filterData.value0
                let filterData = (inst["synthSection"] as? [String: Any]).flatMap {
                    ($0["filterData"] as? [String: Any])?["value0"] as? [String: Any]
                }
                let filterType       = filterData?["filterType"]      as? Int    ?? 29
                let filterCutoff     = filterData?["filterCutoff"]    as? Double ?? 1.0
                let filterResonance  = filterData?["filterResonance"] as? Double ?? 0.0

                // sliceInfo: actual sample boundaries set in the MPC sample editor
                let sliceInfo      = layer["sliceInfo"] as? [String: Any] ?? [:]
                let sliceInfoStart = sliceInfo["Start"]     as? Int ?? 0
                let sliceInfoEnd   = sliceInfo["End"]       as? Int ?? 0
                let sliceInfoLoop  = sliceInfo["LoopStart"] as? Int ?? 0

                // mixable: pad strip volume and pan
                let mixable   = inst["mixable"] as? [String: Any] ?? [:]
                let padVolume = mixable["volume"] as? Double ?? 0.7079457640647888
                let padPan    = mixable["pan"]    as? Double ?? 0.5
                let padMuted  = mixable["mute"]   as? Bool   ?? false

                let triggerMode = inst["triggerMode"] as? Int ?? 1
                // OneShot from synthSection.ampEnvelope.OneShot.value0
                let synthOneShot: Bool = {
                    if let ss  = inst["synthSection"] as? [String: Any],
                       let env = ss["ampEnvelope"]    as? [String: Any],
                       let os  = env["OneShot"]       as? [String: Any],
                       let v   = os["value0"]         as? Bool {
                        return v
                    }
                    return false
                }()
                let isNoteMode   = noteModeNotes.contains(midiNote)
                let isChopMode   = chopModeNotes.contains(midiNote)
                // Filter mode: note has 16 Levels Filter events. Note mode takes priority
                // (if the same note has both, note-mode routing is used instead).
                let isFilterMode = filterModeNotes.contains(midiNote) && !noteModeNotes.contains(midiNote)
                let chopRegions = (inst["chopProperties"] as? [String: Any])?["chopRegions"] as? Int ?? 16
                let chopMode    = (inst["chopProperties"] as? [String: Any])?["chopMode"]    as? Int ?? 0

                // rootNote from sample metadata
                let rootNote: Int
                if let meta = trackSamples.first(where: {
                    ($0["path"] as? String) == sf
                })?["metadata"] as? [String: Any],
                   let rn = meta["rootNote"] as? Int {
                    rootNote = rn
                } else {
                    rootNote = 60
                }
                pads.append(MPCPad(
                    padIndex: padIdx, midiNote: midiNote,
                    sampleFile: sf, sampleName: sampleName,
                    coarseTune: coarse, fineTune: fine,
                    volume: padVolume, pan: padPan,
                    sliceInfoStart: sliceInfoStart, sliceInfoEnd: sliceInfoEnd,
                    sliceInfoLoopStart: sliceInfoLoop,
                    oneShot: triggerMode == 1 || synthOneShot, reverse: direction == 1,
                    isNoteMode: isNoteMode, rootNote: rootNote,
                    isChopMode: isChopMode, chopRegions: chopRegions, chopMode: chopMode,
                    sliceStarts: [], loadImpl: loadImpl,
                    warpEnable: warpEn, nativeBPM: nativeBPM,
                    isGateMode: trigMode == 2, layerLoop: layerLoop,
                    muteGroup: muteGroup, monophonic: monophonic,
                    ampAttack: ampAttack, ampDecay: ampDecay, ampRelease: ampRelease,
                    layerOffset: layerOffset,
                    filterType: filterType, filterCutoff: filterCutoff,
                    filterResonance: filterResonance,
                    muted: padMuted,
                    automationEvents: noteAutoEvents[midiNote] ?? [],
                    isFilterMode: isFilterMode
                ))
            }

            if !pads.isEmpty {
                return MPCDrumTrack(name: name, volume: vol, pan: pan, pads: pads)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func extractBPM(from data: [String: Any]) -> Double {
        // If masterTempoEnabled, the global masterTempo overrides all sequences.
        if let enabled = data["masterTempoEnabled"] as? Bool, enabled,
           let master = data["masterTempo"] as? Double { return master }
        // When per-sequence BPM is in use, the MPC's factory default is 128 BPM.
        // Unmodified sequences stay at 128; the user adjusts individual scenes away from that.
        // Setting the ALS master to 128 means those untouched scenes inherit it naturally
        // (IsTempoEnabled=false) while explicitly changed scenes get IsTempoEnabled=true.
        return 128.0
    }

    private static func extractLengthBars(from data: [String: Any]) -> Int {
        if let seqs = data["sequences"] as? [[String: Any]] {
            let sorted = seqs.sorted { ($0["key"] as? Int ?? 0) < ($1["key"] as? Int ?? 0) }
            if let val  = sorted.first?["value"] as? [String: Any],
               let bars = val["lengthBars"] as? Int { return bars }
        }
        return 2
    }

    private static func parseTimeSig(from data: [String: Any]) -> MPCTimeSig {
        guard let seqs   = data["sequences"] as? [[String: Any]] else {
            return MPCTimeSig(beatsPerBar: 4, pulsesPerBeat: 960)
        }
        let sortedSeqs = seqs.sorted { ($0["key"] as? Int ?? 0) < ($1["key"] as? Int ?? 0) }
        guard let val    = sortedSeqs.first?["value"] as? [String: Any],
              let tsTrack = val["timeSignatureTrack"] as? [String: Any],
              let tsList  = tsTrack["timeSignatures"] as? [[String: Any]],
              let ts      = tsList.first else {
            return MPCTimeSig(beatsPerBar: 4, pulsesPerBeat: 960)
        }
        return MPCTimeSig(
            beatsPerBar:   ts["beatsPerBar"] as? Int ?? 4,
            pulsesPerBeat: ts["beatLength"]  as? Int ?? 960
        )
    }

    private static func parsePulsesPerBeat(from value: [String: Any]) -> Int {
        guard let tsTrack = value["timeSignatureTrack"] as? [String: Any],
              let tsList  = tsTrack["timeSignatures"] as? [[String: Any]],
              let ts      = tsList.first,
              let bl      = ts["beatLength"] as? Int else { return 960 }
        return bl
    }

    // MARK: - Master compressor detection

    /// Returns an MPCCompressorState if an enabled Color Compressor is present on the
    /// master output bus (data.mixer.outputs[0].mixable.inserts.effects[]).
    ///
    /// The plugin state blob ("119.<base64>") is decoded to extract:
    ///   • bypassed — bytes[105:108] == [0x03, 0xD0, 0x80]
    ///   • colorOn  — bytes[101:103] == [0x1F, 0xF8]
    ///
    /// Attack/Release/Amount raw values use a proprietary encoding that cannot be
    /// reverse-engineered from the available test data, so Ableton defaults are used
    /// and only the parameter *range* is constrained to match MPC specs.
    private static func parseMasterCompressor(from data: [String: Any]) -> MPCCompressorState? {
        guard let mixer   = data["mixer"]            as? [String: Any],
              let outputs = mixer["outputs"]         as? [[String: Any]],
              let master  = outputs.first,
              let mixable = master["mixable"]        as? [String: Any],
              let inserts = mixable["inserts"]       as? [String: Any],
              let effects = inserts["effects"]       as? [[String: Any]]
        else { return nil }

        guard let fx = effects.first(where: { fx in
            guard let plugin = fx["plugin"]          as? [String: Any],
                  let desc   = plugin["description"] as? [String: Any],
                  let name   = desc["name"]          as? String,
                  name == "Color Compressor"
            else { return false }
            let enabled = fx["enable"] as? Bool ?? true
            return enabled
        }) else { return nil }

        let enabled = fx["enable"] as? Bool ?? true

        // Attempt to decode bypass / color state from the plugin state blob.
        // Format: "119.<base64>" where '.' substitutes for 'A' (both = 0 in base64).
        // Strip the "119." prefix first, then base64-decode the remainder.
        // Decodes to 119 bytes; variable parameter region is bytes 79–104.
        //   Color ON:   bytes[98..99]   == [0x1F, 0xF8]
        //   Bypass ON:  bytes[102..104] == [0x03, 0xD0, 0x80]
        var bypassed = false
        var colorOn  = false

        if let plugin   = fx["plugin"]  as? [String: Any],
           let stateStr = plugin["state"] as? String,
           stateStr.hasPrefix("119.") {
            let b64    = stateStr.dropFirst(4).replacingOccurrences(of: ".", with: "A")
            let padded = b64 + String(repeating: "=", count: (4 - b64.count % 4) % 4)
            if let blob = Data(base64Encoded: padded), blob.count >= 105 {
                colorOn  = blob[98] == 0x1F && blob[99] == 0xF8
                bypassed = blob[102] == 0x03 && blob[103] == 0xD0 && blob[104] == 0x80
            }
        }

        return MPCCompressorState(enabled: enabled, bypassed: bypassed, colorOn: colorOn)
    }
}
