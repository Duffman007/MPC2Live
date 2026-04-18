// MPCProject.swift
// Model types representing the parsed state of an Akai MPC .xpj project.
// Only the fields we actually need for ALS conversion are represented.

import Foundation

// MARK: - Top-level project

struct MPCProject {
    let name: String            // derived from filename
    let bpm: Double
    let timeSignature: MPCTimeSig
    let lengthBars: Int
    let drumTrack: MPCDrumTrack?      // first drum program (nil if none)
    let sequences: [MPCSequence]      // all sequences (one clip slot each)
    let hasMasterCompressor: Bool     // true = Color Compressor on master output bus
    // Convenience for single-sequence access
    var sequence: MPCSequence { sequences.first ?? MPCSequence(name: "Sequence 01", trackName: "", events: [], lengthPulses: 7680, bpm: bpm) }
}

// MARK: - Time signature

struct MPCTimeSig {
    let beatsPerBar: Int
    let pulsesPerBeat: Int          // MPC calls this beatLength; typically 960
}

// MARK: - Drum track / program

struct MPCDrumTrack {
    let name: String                 // e.g. "Drum 001"
    let volume: Double               // 0.0–1.0, as gainCoefficient
    let pan: Double                  // 0.0–1.0 (0.5 = centre)
    let pads: [MPCPad]               // only pads with samples loaded
}

// MARK: - Pad


/// A single per-pad automation event extracted from an MPC sequence (event type 2).
struct MPCAutomationEvent {
    let sequenceName: String  // name of the sequence this event belongs to (e.g. "Sequence 02")
    let time: Int             // MPC pulses (960 PPQ from sequence start)
    let parameter: Int        // e.g. 518 = pad volume fader
    let value: Double         // 0-1 normalized MPC value
}

struct MPCPad {
    let padIndex: Int                // 0-based, within the 128-pad bank
    let midiNote: Int                // MIDI note number (36 = pad 0 by default)
    let sampleFile: String           // filename e.g. "Kick 1.wav"
    let sampleName: String           // display name e.g. "Kick 1"
    let coarseTune: Int              // layer.coarseTune (-24 to +24 semitones)
    let fineTune: Int                // layer.fineTune (-90 to +90 cents)
    let volume: Double               // mixable.volume (0.0–1.0)
    let pan: Double                  // mixable.pan (0.0–1.0)
    let sliceInfoStart: Int          // layer.sliceInfo.Start (sample start frame)
    let sliceInfoEnd: Int            // layer.sliceInfo.End (sample end frame)
    let sliceInfoLoopStart: Int      // layer.sliceInfo.LoopStart
    let oneShot: Bool                // true = one-shot (no note-off), false = gated
    let reverse: Bool                // direction: 1 = reverse
    let isNoteMode: Bool             // true = 16 Levels Tune (chromatic Simpler track needed)
    let rootNote: Int                // MIDI root note for Simpler (from sample metadata, default 60)
    let isChopMode: Bool             // true = Chop mode (Simpler slice track needed)
    let chopRegions: Int             // number of chop slices (default 16)
    let chopMode: Int                // 0=manual, 1=threshold, 2=regions, 3=beatgrid
    let sliceStarts: [Int]           // frame positions from WAV atem chunk (empty if unavailable)
    let loadImpl: Int                // 0=project-embedded, 1=load from device library
    let warpEnable: Bool             // true = warp to project BPM
    let nativeBPM: Double            // sample's detected tempo (from instrument.tempo)
    let isGateMode: Bool             // triggerMode=2 → gate/note-on (Classic, no loop, stops on release)
    let layerLoop: Bool              // layer.loop=true → loop playback (Classic mode + loop)
    let muteGroup: Int               // whichMuteGroup 0=none, 1-32; Ableton ChokeGroup 0=none, 1-16
    let monophonic: Bool             // true = one voice (new hit cuts old); false = polyphonic
    let ampAttack: Double            // synthSection.ampEnvelope.Attack.value0 (0-1, × 2000 = ms)
    let ampDecay: Double             // synthSection.ampEnvelope.Decay.value0
    let ampRelease: Double           // synthSection.ampEnvelope.Release.value0
    let layerOffset: Int             // layer.offset — negative = delayed trigger (pending ALS mapping)
    let filterType: Int              // 0=Off, 29=Classic, 2=LPF2, 3=LPF4, 7=HPF2, 8=HPF4, 11=BPF2, 12=BPF4
    let filterCutoff: Double         // 0.0-1.0 normalized (log maps to 30-22000 Hz in ALS)
    let filterResonance: Double      // 0.0-1.0 normalized (maps to ALS Res 0-1.25)
    let muted: Bool                  // mixable.mute — instrument-level mute (not per-sequence)
    let automationEvents: [MPCAutomationEvent]   // type=2 events from sequence, matched by note number
}

// MARK: - Sequence / MIDI events

struct MPCSequence {
    let name: String
    let trackName: String            // name of the clip track (e.g. "Drum 001")
    let events: [MPCNoteEvent]
    let lengthPulses: Int            // total clip length in MPC pulses
    let bpm: Double                  // sequence BPM (may differ from project master)
}

struct MPCNoteEvent {
    let timePulses: Int              // onset in MPC pulses
    let midiNote: Int
    let velocity: Double             // 0.0–1.0
    let lengthPulses: Int
    let tuningModifier: Double?      // modifierValue0 if modifierActiveState0==true, else nil
    let chopSlice: Int?              // round(modifierValue15*127) if modifierActiveState15==true
}

// MARK: - Bank grouping

struct MPCBank {
    let bankIndex: Int           // 0=A … 7=H
    let name: String             // "Bank A" … "Bank H"
    let pads: [MPCPad]           // loaded pads in this bank (padIndex 0-15 within bank)
    let noteToPadInBank: [Int: Int]  // mpcMidiNote → padInBank (0–15)
    let noteToBankIndex: [Int: Int]  // mpcMidiNote → bankIndex (for event filtering)
}

extension MPCDrumTrack {
    /// Group loaded pads into banks (16 pads each).
    /// Empty banks are omitted.
    func banks() -> [MPCBank] {
        var grouped: [Int: [MPCPad]] = [:]
        for pad in pads {
            let bankIdx = pad.padIndex / 16
            grouped[bankIdx, default: []].append(pad)
        }
        return grouped.keys.sorted().map { bankIdx in
            let bankPads = grouped[bankIdx]!
            let letter   = String(UnicodeScalar(UInt32(65 + bankIdx))!)
            var noteMap: [Int: Int] = [:]
            var bankMap: [Int: Int] = [:]
            for pad in bankPads {
                noteMap[pad.midiNote] = pad.padIndex % 16
                bankMap[pad.midiNote] = bankIdx
            }
            return MPCBank(
                bankIndex: bankIdx,
                name: "Bank \(letter)",
                pads: bankPads,
                noteToPadInBank: noteMap,
                noteToBankIndex: bankMap
            )
        }
    }
}
