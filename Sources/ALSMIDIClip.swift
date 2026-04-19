// ALSMIDIClip.swift
// Converts MPC note events into Ableton Live MidiClip XML.
//
// TICK CONVERSION
// MPC PPQ = 960 pulses per beat  (from timeSignatureTrack beatLength)
// ALS beat = 1.0 in ALS time units (1 beat = 1.0, 1 bar of 4/4 = 4.0)
// Conversion: alsTime = mpcPulses / mpcPPQ
// e.g. pulse 960 → beat 1.0, pulse 3840 → beat 4.0 (1 bar)
//
// TRANSPOSITION
// Each bank's notes are transposed so pad-in-bank 0 → MIDI 36 (C1).
// Formula: alsNote = 36 + padInBank  where padInBank = padIndex % 16
// The note_to_padInBank map is built from the MPCProject's padNoteMap.

import Foundation

struct ALSMIDIClip {

    // MARK: - Public

    /// Build MidiClip XML for one bank's events in one sequence.
    /// - Parameters:
    ///   - clipName: display name shown in Ableton's clip slot
    ///   - sequence: the full MPC sequence (all events from all banks)
    ///   - bankIndex: 0=A, 1=B … 7=H — used to filter + transpose events
    ///   - noteToPadInBank: maps original MPC MIDI note → pad-in-bank (0–15)
    ///   - ppq: MPC pulses per beat (typically 960)
    ///   - beatsPerBar: time signature numerator (typically 4)
    static func build(
        clipName: String,
        sequence: MPCSequence,
        bankIndex: Int,
        noteToPadInBank: [Int: Int],
        noteToBankIndex: [Int: Int],
        ppq: Int,
        beatsPerBar: Int,
        clipEnvelopes: [(pointeeId: Int, initialGain: Double, events: [(time: Double, gain: Double)])] = []
    ) -> String {
        let lengthBeats = Double(sequence.lengthPulses) / Double(ppq)
        let minDuration = 0.0625  // 1/16th beat minimum note length

        // Filter events for this bank and group by ALS note (KeyTrack)
        var keyMap: [Int: [(time: Double, duration: Double, velocity: Int, noteId: Int)]] = [:]
        var noteId = 1

        for ev in sequence.events {
            guard let padInBank = noteToPadInBank[ev.midiNote] else { continue }
            // Only include notes belonging to this bank
            guard let evBankIndex = noteToBankIndex[ev.midiNote],
                  evBankIndex == bankIndex else { continue }
            // Skip 16 Levels Tune events — they route to the pad's own Simpler track.
            // (modifierActiveState0=true sets tuningModifier; velocity-mode events have nil)
            if ev.tuningModifier != nil { continue }
            // Skip 16 Levels Filter events — they route to the pad's own filter-mode track.
            // (modifierActiveState2=true sets filterModifier)
            if ev.filterModifier != nil { continue }

            // MIDI clip fires the original MPC MIDI note (36=C1, 37=C#1 etc.)
            // ReceivingNote in the drum rack is separate — handled by ALSDrumRack.
            let alsNote = 36 + padInBank  // transpose to Ableton pad trigger note
            let startBeats  = Double(ev.timePulses) / Double(ppq)
            let durBeats    = max(minDuration, Double(ev.lengthPulses) / Double(ppq))
            let endBeats    = min(startBeats + durBeats, lengthBeats)
            let clippedDur  = max(minDuration, endBeats - startBeats)

            // Skip if note starts at or after clip end
            guard startBeats < lengthBeats else { continue }

            let vel = max(1, min(127, Int((ev.velocity * 127).rounded())))
            keyMap[alsNote, default: []].append(
                (time: startBeats, duration: clippedDur, velocity: vel, noteId: noteId)
            )
            noteId += 1
        }

        // Build KeyTrack XML
        var keyTracksXml = ""
        var ktId = 0
        for alsNote in keyMap.keys.sorted() {
            var notesXml = ""
            for n in keyMap[alsNote]! {
                notesXml += tab(15) +
                    "<MidiNoteEvent Time=\"\(fmt(n.time))\" Duration=\"\(fmt(n.duration))\" " +
                    "Velocity=\"\(n.velocity)\" OffVelocity=\"0\" NoteId=\"\(n.noteId)\" />\n"
            }
            keyTracksXml += tab(13) + "<KeyTrack Id=\"\(ktId)\">\n"
            keyTracksXml += tab(14) + "<Notes>\n"
            keyTracksXml += notesXml
            keyTracksXml += tab(14) + "</Notes>\n"
            keyTracksXml += tab(14) + "<MidiKey Value=\"\(alsNote)\" />\n"
            keyTracksXml += tab(13) + "</KeyTrack>\n"
            ktId += 1
        }

        return buildClipXML(clipName: clipName, lengthBeats: lengthBeats,
                             keyTracksXml: keyTracksXml, noteId: noteId,
                             clipEnvelopes: clipEnvelopes)
    }

    private static func buildClipXML(
        clipName: String,
        lengthBeats: Double,
        keyTracksXml: String,
        noteId: Int = 1,
        clipEnvelopes: [(pointeeId: Int, initialGain: Double, events: [(time: Double, gain: Double)])] = []
    ) -> String {
        let L = fmt(lengthBeats)
        return
            tab(10) + "<MidiClip Id=\"0\" Time=\"0\">\n" +
            tab(11) + "<LomId Value=\"0\" />\n" +
            tab(11) + "<LomIdView Value=\"0\" />\n" +
            tab(11) + "<CurrentStart Value=\"0\" />\n" +
            tab(11) + "<CurrentEnd Value=\"\(L)\" />\n" +
            tab(11) + "<Loop>\n" +
            tab(12) + "<LoopStart Value=\"0\" />\n" +
            tab(12) + "<LoopEnd Value=\"\(L)\" />\n" +
            tab(12) + "<StartRelative Value=\"0\" />\n" +
            tab(12) + "<LoopOn Value=\"true\" />\n" +
            tab(12) + "<OutMarker Value=\"\(L)\" />\n" +
            tab(12) + "<HiddenLoopStart Value=\"0\" />\n" +
            tab(12) + "<HiddenLoopEnd Value=\"\(L)\" />\n" +
            tab(11) + "</Loop>\n" +
            tab(11) + "<Name Value=\"\(xmlEscape(clipName))\" />\n" +
            tab(11) + "<Color Value=\"-1\" />\n" +
            tab(11) + "<LaunchMode Value=\"0\" />\n" +
            tab(11) + "<LaunchQuantisation Value=\"0\" />\n" +
            tab(11) + "<Grid>\n" +
            tab(12) + "<FixedNumerator Value=\"1\" />\n" +
            tab(12) + "<FixedDenominator Value=\"16\" />\n" +
            tab(12) + "<GridIntervalPixel Value=\"20\" />\n" +
            tab(12) + "<Ntoles Value=\"2\" />\n" +
            tab(12) + "<SnapToGrid Value=\"true\" />\n" +
            tab(12) + "<Fixed Value=\"false\" />\n" +
            tab(11) + "</Grid>\n" +
            tab(11) + "<FreezeStart Value=\"0\" />\n" +
            tab(11) + "<FreezeEnd Value=\"0\" />\n" +
            tab(11) + "<IsWarped Value=\"true\" />\n" +
            tab(11) + "<TakeId Value=\"-1\" />\n" +
            tab(11) + "<IsInKey Value=\"true\" />\n" +
            tab(11) + "<ScaleInformation>\n" +
            tab(12) + "<Root Value=\"0\" />\n" +
            tab(12) + "<Name Value=\"0\" />\n" +
            tab(11) + "</ScaleInformation>\n" +
            tab(11) + "<Notes>\n" +
            tab(12) + "<KeyTracks>\n" +
            keyTracksXml +
            tab(12) + "</KeyTracks>\n" +
            tab(12) + "<PerNoteEventStore>\n" +
            tab(13) + "<EventLists />\n" +
            tab(12) + "</PerNoteEventStore>\n" +
            tab(12) + "<NoteProbabilityGroups />\n" +
            tab(12) + "<ProbabilityGroupIdGenerator>\n" +
            tab(13) + "<NextId Value=\"1\" />\n" +
            tab(12) + "</ProbabilityGroupIdGenerator>\n" +
            tab(12) + "<NoteIdGenerator>\n" +
            tab(13) + "<NextId Value=\"\(noteId)\" />\n" +
            tab(12) + "</NoteIdGenerator>\n" +
            tab(11) + "</Notes>\n" +
            buildEnvelopesXML(clipEnvelopes: clipEnvelopes) +
            tab(11) + "<BankSelectCoarse Value=\"-1\" />\n" +
            tab(11) + "<BankSelectFine Value=\"-1\" />\n" +
            tab(11) + "<ProgramChange Value=\"-1\" />\n" +
            tab(11) + "<NoteEditorFoldInZoom Value=\"-1\" />\n" +
            tab(11) + "<NoteEditorFoldInScroll Value=\"0\" />\n" +
            tab(11) + "<NoteEditorFoldOutZoom Value=\"144\" />\n" +
            tab(11) + "<NoteEditorFoldOutScroll Value=\"0\" />\n" +
            tab(11) + "<NoteEditorFoldScaleZoom Value=\"-1\" />\n" +
            tab(11) + "<NoteEditorFoldScaleScroll Value=\"0\" />\n" +
            tab(11) + "<NoteSpellingPreference Value=\"0\" />\n" +
            tab(11) + "<AccidentalSpellingPreference Value=\"3\" />\n" +
            tab(11) + "<PreferFlatRootNote Value=\"false\" />\n" +
            tab(11) + "<ExpressionGrid>\n" +
            tab(12) + "<FixedNumerator Value=\"1\" />\n" +
            tab(12) + "<FixedDenominator Value=\"16\" />\n" +
            tab(12) + "<GridIntervalPixel Value=\"20\" />\n" +
            tab(12) + "<Ntoles Value=\"2\" />\n" +
            tab(12) + "<SnapToGrid Value=\"false\" />\n" +
            tab(12) + "<Fixed Value=\"false\" />\n" +
            tab(11) + "</ExpressionGrid>\n" +
            tab(10) + "</MidiClip>\n"
    }


    /// Build the <Envelopes>…</Envelopes> section for session-view clip automation.
    /// Returns empty string when no envelopes are present.
    private static func buildEnvelopesXML(
        clipEnvelopes: [(pointeeId: Int, initialGain: Double, events: [(time: Double, gain: Double)])]
    ) -> String {
        guard !clipEnvelopes.isEmpty else { return "" }
        let t11 = tab(11); let t12 = tab(12); let t13 = tab(13)
        let t14 = tab(14); let t15 = tab(15); let t16 = tab(16)
        var envXMLs: [String] = []
        for (envId, env) in clipEnvelopes.enumerated() {
            var eventLines = ""
            // Sentinel event: sets the initial value before the clip starts
            eventLines += "\(t16)<FloatEvent Id=\"0\" Time=\"-63072000\" Value=\"\(fmtGain(env.initialGain))\" />\n"
            for (ei, pt) in env.events.enumerated() {
                eventLines += "\(t16)<FloatEvent Id=\"\(ei + 1)\" Time=\"\(fmtTime(pt.time))\" Value=\"\(fmtGain(pt.gain))\" />\n"
            }
            envXMLs.append(
                "\(t13)<ClipEnvelope Id=\"\(envId)\">\n" +
                "\(t14)<EnvelopeTarget>\n" +
                "\(t15)<PointeeId Value=\"\(env.pointeeId)\" />\n" +
                "\(t14)</EnvelopeTarget>\n" +
                "\(t14)<Automation>\n" +
                "\(t15)<Events>\n" +
                eventLines +
                "\(t15)</Events>\n" +
                "\(t15)<AutomationTransformViewState>\n" +
                "\(t16)<IsTransformPending Value=\"false\" />\n" +
                "\(t16)<TimeAndValueTransforms />\n" +
                "\(t15)</AutomationTransformViewState>\n" +
                "\(t14)</Automation>\n" +
                "\(t14)<LoopSlot>\n" +
                "\(t15)<Value />\n" +
                "\(t14)</LoopSlot>\n" +
                "\(t14)<ScrollerTimePreserver>\n" +
                "\(t15)<LeftTime Value=\"0\" />\n" +
                "\(t15)<RightTime Value=\"0\" />\n" +
                "\(t14)</ScrollerTimePreserver>\n" +
                "\(t13)</ClipEnvelope>\n"
            )
        }
        return
            "\(t11)<Envelopes>\n" +
            "\(t12)<Envelopes>\n" +
            envXMLs.joined() +
            "\(t12)</Envelopes>\n" +
            "\(t11)</Envelopes>\n"
    }
    private static func fmtGain(_ v: Double) -> String { String(format: "%.10g", v) }
    private static func fmtTime(_ v: Double) -> String { String(format: "%.10g", v) }

    // MARK: - Helpers



    private static func tab(_ n: Int) -> String { String(repeating: "\t", count: n) }

    private static func fmt(_ v: Double) -> String {
        // ALS uses plain decimals — trim unnecessary trailing zeros
        if v == v.rounded() && abs(v) < 1_000_000 { return String(Int(v)) }
        // Up to 13 significant figures, no trailing zeros
        var s = String(format: "%.13g", v)
        return s
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
    // MARK: - Note mode (16 Levels Tune) clip builder

    /// Build a MIDI clip for a note-mode pad.
    /// Each event's pitch = rootNote + round((modifierValue0 × 120) - 60)
    /// If tuningModifier is nil (shouldn't happen on a note-mode pad), use rootNote.
    static func buildNoteMode(
        clipName: String,
        sequence: MPCSequence,
        pad: MPCPad,
        ppq: Int,
        beatsPerBar: Int
    ) -> String {
        let lengthBeats  = Double(sequence.lengthPulses) / Double(ppq)
        let minDuration  = 0.0625

        // Filter events for this pad's midiNote only
        let padEvents = sequence.events.filter { $0.midiNote == pad.midiNote }

        // Group by transposed MIDI note
        var keyMap: [Int: [(time: Double, duration: Double, velocity: Int, noteId: Int)]] = [:]
        var noteId = 1

        for ev in padEvents {
            let beatTime = Double(ev.timePulses) / Double(ppq)
            let duration = max(minDuration, Double(ev.lengthPulses) / Double(ppq))
            let vel      = max(1, min(127, Int(ev.velocity * 127)))

            // Convert tuningModifier to MIDI note.
            // MPC 16 Levels Tune: modifierValue0 is a normalised fine-tune value where
            // 0.5 = no pitch change. Adjacent pad positions are ~1/240 apart, and each
            // step of 1/240 corresponds to exactly 1 semitone.
            // Formula: round((t - 0.5) × 240)  →  semitone offset from rootNote.
            let midiNote: Int
            if let t = ev.tuningModifier {
                let semitoneOffset = ((t - 0.5) * 240.0).rounded()
                midiNote = max(0, min(127, pad.rootNote + Int(semitoneOffset)))
            } else {
                midiNote = pad.rootNote
            }

            keyMap[midiNote, default: []].append((beatTime, duration, vel, noteId))
            noteId += 1
        }

        var keyTracksXml = ""
        for (idx, alsNote) in keyMap.keys.sorted().enumerated() {
            var notesXml = ""
            for n in keyMap[alsNote]! {
                notesXml += tab(15) + "<MidiNoteEvent Time=\"\(fmt(n.time))\" "
                    + "Duration=\"\(fmt(n.duration))\" "
                    + "Velocity=\"\(n.velocity)\" "
                    + "VelocityDeviation=\"0\" OffVelocity=\"64\" "
                    + "Probability=\"1\" IsEnabled=\"true\" NoteId=\"\(n.noteId)\" />\n"
            }
            keyTracksXml += tab(13) + "<KeyTrack Id=\"\(idx)\">\n"
            keyTracksXml += tab(14) + "<Notes>\n"
            keyTracksXml += notesXml
            keyTracksXml += tab(14) + "</Notes>\n"
            keyTracksXml += tab(14) + "<MidiKey Value=\"\(alsNote)\" />\n"
            keyTracksXml += tab(13) + "</KeyTrack>\n"
        }

        return buildClipXML(clipName: clipName, lengthBeats: lengthBeats,
                             keyTracksXml: keyTracksXml, noteId: noteId)
    }
    // MARK: - Chop mode clip builder

    /// Build a MIDI clip for a chop-mode pad.
    /// Each event's chopSlice maps to Simpler slice note: 36 + sliceIndex
    static func buildChop(
        clipName: String,
        sequence: MPCSequence,
        pad: MPCPad,
        ppq: Int,
        beatsPerBar: Int
    ) -> String {
        let lengthBeats = Double(sequence.lengthPulses) / Double(ppq)
        let minDuration = 0.0625

        let padEvents = sequence.events.filter {
            $0.midiNote == pad.midiNote && $0.chopSlice != nil
        }

        var keyMap: [Int: [(time: Double, duration: Double, velocity: Int, noteId: Int)]] = [:]
        var noteId = 1

        for ev in padEvents {
            let beatTime = Double(ev.timePulses) / Double(ppq)
            let duration = max(minDuration, Double(ev.lengthPulses) / Double(ppq))
            let vel      = max(1, min(127, Int(ev.velocity * 127)))
            let alsNote  = 36 + (ev.chopSlice ?? 0)

            keyMap[alsNote, default: []].append((beatTime, duration, vel, noteId))
            noteId += 1
        }

        var keyTracksXml = ""
        for (idx, alsNote) in keyMap.keys.sorted().enumerated() {
            var notesXml = ""
            for n in keyMap[alsNote]! {
                notesXml += tab(15) + "<MidiNoteEvent Time=\"\(fmt(n.time))\" "
                    + "Duration=\"\(fmt(n.duration))\" "
                    + "Velocity=\"\(n.velocity)\" "
                    + "VelocityDeviation=\"0\" OffVelocity=\"64\" "
                    + "Probability=\"1\" IsEnabled=\"true\" NoteId=\"\(n.noteId)\" />\n"
            }
            keyTracksXml += tab(13) + "<KeyTrack Id=\"\(idx)\">\n"
            keyTracksXml += tab(14) + "<Notes>\n"
            keyTracksXml += notesXml
            keyTracksXml += tab(14) + "</Notes>\n"
            keyTracksXml += tab(14) + "<MidiKey Value=\"\(alsNote)\" />\n"
            keyTracksXml += tab(13) + "</KeyTrack>\n"
        }

        return buildClipXML(clipName: clipName, lengthBeats: lengthBeats,
                             keyTracksXml: keyTracksXml, noteId: noteId)
    }

    // MARK: - Filter mode (16 Levels Filter) clip builder

    /// Build a MIDI clip for a filter-mode pad.
    /// Each event's filterModifier value maps to a drum rack slot index via the fixed MPC formula:
    ///   slot = round((value × 127 + 1) / 8) − 1   (0-based, clamped 0–15)
    /// This avoids floating-point dict-key mismatches by computing the slot analytically.
    static func buildFilterMode(
        clipName: String,
        sequence: MPCSequence,
        pad: MPCPad,
        filterValueToIndex: [Double: Int] = [:],   // kept for call-site compatibility; not used
        ppq: Int,
        beatsPerBar: Int
    ) -> String {
        let lengthBeats = Double(sequence.lengthPulses) / Double(ppq)
        let minDuration = 0.0625

        // Only events for this pad that carry a filter modifier
        let padEvents = sequence.events.filter {
            $0.midiNote == pad.midiNote && $0.filterModifier != nil
        }

        var keyMap: [Int: [(time: Double, duration: Double, velocity: Int, noteId: Int)]] = [:]
        var noteId = 1

        for ev in padEvents {
            guard let fv = ev.filterModifier else { continue }
            // Compute slot index analytically from the fixed MPC formula (8k−1)/127.
            // Robust against JSON float representation differences.
            let idx = max(0, min(15, Int(round((fv * 127.0 + 1.0) / 8.0)) - 1))
            let beatTime = Double(ev.timePulses)  / Double(ppq)
            let duration = max(minDuration, Double(ev.lengthPulses) / Double(ppq))
            let vel      = max(1, min(127, Int(ev.velocity * 127)))
            // Drum rack trigger note: 36 + padInBank (mirrors standard drum rack clip convention)
            let alsNote  = 36 + idx

            keyMap[alsNote, default: []].append((beatTime, duration, vel, noteId))
            noteId += 1
        }

        var keyTracksXml = ""
        for (ktIdx, alsNote) in keyMap.keys.sorted().enumerated() {
            var notesXml = ""
            for n in keyMap[alsNote]! {
                notesXml += tab(15) + "<MidiNoteEvent Time=\"\(fmt(n.time))\" "
                    + "Duration=\"\(fmt(n.duration))\" "
                    + "Velocity=\"\(n.velocity)\" "
                    + "VelocityDeviation=\"0\" OffVelocity=\"64\" "
                    + "Probability=\"1\" IsEnabled=\"true\" NoteId=\"\(n.noteId)\" />\n"
            }
            keyTracksXml += tab(13) + "<KeyTrack Id=\"\(ktIdx)\">\n"
            keyTracksXml += tab(14) + "<Notes>\n"
            keyTracksXml += notesXml
            keyTracksXml += tab(14) + "</Notes>\n"
            keyTracksXml += tab(14) + "<MidiKey Value=\"\(alsNote)\" />\n"
            keyTracksXml += tab(13) + "</KeyTrack>\n"
        }

        return buildClipXML(clipName: clipName, lengthBeats: lengthBeats,
                             keyTracksXml: keyTracksXml, noteId: noteId)
    }

}
