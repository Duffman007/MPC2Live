// ALSDrumRack.swift
// Builds the DrumGroupDevice XML block for one bank of MPC pads.
//
// STRATEGY
// Each pad uses the branch template from ReferenceTemplates.branchTemplate.
// Per-pad substitutions use {{PLACEHOLDER}} tokens baked into the template.
//
// IDs: each DrumBranch has 96 AutomationTarget/ModulationTarget/Pointee IDs.
// We assign sequentially from a per-track base so nothing ever collides.
//
// RECEIVING NOTE = 36 + padInBank (always C1–D#2 regardless of MPC bank).

import Foundation

struct ALSDrumRack {

    static let idsPerBranch  = 96
    static let drumRackBase  = 30_000  // above blank-track max ID (~22155)

    // MARK: - Public

    static func build(
        pads: [MPCPad],
        bankIndex: Int,
        projectSamplesURL: URL,
        sourceDataURL: URL?,
        fileToCanonical: [String: String] = [:],
        trackIndex: Int
    ) -> String {
        guard
            let hData = Data(base64Encoded: ReferenceTemplates.drumRackHeader,
                             options: .ignoreUnknownCharacters),
            let fData = Data(base64Encoded: ReferenceTemplates.drumRackFooter,
                             options: .ignoreUnknownCharacters),
            let header = String(data: hData, encoding: .utf8),
            let footer = String(data: fData, encoding: .utf8)
        else { return "<!-- ALSDrumRack: template decode failed -->" }

        let headerBase = drumRackBase + trackIndex * 10_000

        var branches = ""
        for (bi, pad) in pads.enumerated() {
            let idBase = headerBase + 100 + bi * idsPerBranch
            branches += buildBranch(pad: pad, branchIndex: bi,
                                    bankIndex: bankIndex,
                                    idBase: idBase,
                                    trackIndex: trackIndex,
                                    samplesURL: projectSamplesURL,
                                    sourceDir: sourceDataURL,
                                    canonicalFile: fileToCanonical[pad.sampleFile])
        }

        // Remap ALL original reference IDs in the complete assembled rack.
        // Both header AND footer contain IDs from the reference (22182-22217)
        // that must be unique per track.
        var assembled = header + branches + footer
        // Give each drum rack a unique DrumGroupDevice Id to avoid collisions
        // when multiple banks produce multiple drum rack tracks.
        let rackId = 30000 + trackIndex * 10000
        assembled = assembled.replacingOccurrences(
            of: "<DrumGroupDevice Id=\"0\">",
            with: "<DrumGroupDevice Id=\"\(rackId)\">"
        )
        return remapNumericIds(in: assembled, startingAt: headerBase)
    }

    // MARK: - Branch

    private static func buildBranch(
        pad: MPCPad,
        branchIndex: Int,
        bankIndex: Int,
        idBase: Int,
        trackIndex: Int,
        samplesURL: URL,
        sourceDir: URL? = nil,
        canonicalFile: String? = nil
    ) -> String {
        guard
            let tData = Data(base64Encoded: ReferenceTemplates.branchTemplate,
                             options: .ignoreUnknownCharacters),
            var tpl   = String(data: tData, encoding: .utf8)
        else { return "<!-- branch decode failed -->" }

        // Use padInBank + bankIndex directly — handles wrap-around banks correctly.
        let receivingNote = ALSNoteMap.receivingNote(padInBank: pad.padInBank, bankIndex: bankIndex)
        // Read WAVInfo from sourceDir (projectData). For reversed/duplicate pads whose
        // source file may be missing or corrupt, fall back to the canonical file.
        let baseDir = sourceDir ?? samplesURL
        let primaryURL   = baseDir.appendingPathComponent(pad.sampleFile)
        let fallbackURL  = canonicalFile.map { baseDir.appendingPathComponent($0) }
        let info: WAVInfo?
        if let i = WAVInfo.read(from: primaryURL) {
            info = i
        } else if let fb = fallbackURL, let i = WAVInfo.read(from: fb) {
            info = i
        } else {
            info = WAVInfo.read(from: samplesURL.appendingPathComponent(pad.sampleFile))
        }

        // Relative path from .als (inside Project folder) to sample
        let relPath = "Samples/Imported/\(pad.sampleFile)"

        tpl = tpl.replacingOccurrences(of: "{{BRANCH_ID}}",      with: "\(branchIndex)")
        // Mute group: MPC whichMuteGroup 0=none, 1-32 → Ableton ChokeGroup 0=none, 1-16
        // Ableton only has 16 choke groups; clamp MPC groups 17-32 to 16.
        let chokeGroup = pad.muteGroup == 0 ? 0 : min(pad.muteGroup, 16)
        tpl = tpl.replacingOccurrences(of: "{{CHOKE_GROUP}}",    with: "\(chokeGroup)")

        // Display name: use canonical filename (without .wav), append " R" for reversed pads
        let displayFile = canonicalFile ?? pad.sampleFile
        let displayBase = displayFile.lowercased().hasSuffix(".wav")
            ? String(displayFile.dropLast(4)) : displayFile
        let padDisplayName = pad.reverse ? displayBase + " R" : displayBase
        tpl = tpl.replacingOccurrences(of: "{{PAD_NAME}}",        with: xmlEscape(padDisplayName))
        tpl = tpl.replacingOccurrences(of: "{{RECEIVING_NOTE}}",  with: "\(receivingNote)")
        let finalRelPath: String
        if pad.reverse {
            // Use canonical source filename so all duplicates reference the same reversed file
            let baseName = canonicalFile ?? pad.sampleFile
            let revName  = baseName.replacingOccurrences(of: ".wav", with: " R.wav",
                                                         options: [.caseInsensitive, .backwards])
            finalRelPath = "Samples/Processed/Reverse/\(revName)"
        } else if let canon = canonicalFile {
            finalRelPath = "Samples/Imported/\(canon)"
        } else {
            finalRelPath = relPath
        }
        tpl = tpl.replacingOccurrences(of: "{{RELATIVE_PATH}}",   with: xmlEscape(finalRelPath))
        tpl = tpl.replacingOccurrences(of: "{{ABS_PATH}}",        with: "")
        tpl = tpl.replacingOccurrences(of: "{{FILE_SIZE}}",       with: "\(info?.fileSize   ?? 0)")
        tpl = tpl.replacingOccurrences(of: "{{FILE_CRC}}",        with: "\(info?.crc16      ?? 0)")
        // Frame values from sliceInfo (MPC stores actual sample boundaries there)
        let totalFrames = info?.frameCount ?? (pad.sliceInfoEnd > 0 ? pad.sliceInfoEnd : 0)
        let sliceStart: Int
        let sliceEnd:   Int
        if pad.reverse && totalFrames > 0 {
            sliceStart = max(0, totalFrames - pad.sliceInfoEnd)
            sliceEnd   = max(0, totalFrames - pad.sliceInfoStart)
        } else {
            sliceStart = pad.sliceInfoStart
            sliceEnd   = pad.sliceInfoEnd > 0 ? pad.sliceInfoEnd : totalFrames
        }
        let loopStart   = pad.sliceInfoLoopStart

        tpl = tpl.replacingOccurrences(of: "{{SAMPLE_FRAMES}}",         with: "\(sliceEnd)")
        tpl = tpl.replacingOccurrences(of: "{{FRAME_COUNT}}",           with: "\(info?.frameCount ?? sliceEnd)")
        tpl = tpl.replacingOccurrences(of: "{{DEFAULT_SAMPLE_RATE}}",   with: "\(info?.sampleRate ?? 44100)")
        tpl = tpl.replacingOccurrences(of: "{{SAMPLE_START}}",    with: "\(sliceStart)")
        tpl = tpl.replacingOccurrences(of: "{{LOOP_START}}",      with: "\(loopStart)")
        // Tune
        tpl = tpl.replacingOccurrences(of: "{{COARSE_TUNE}}",     with: "\(pad.coarseTune)")
        let alsFineTune = Double(pad.fineTune) * (50.0 / 90.0)
        tpl = tpl.replacingOccurrences(of: "{{FINE_TUNE}}",       with: "\(alsFineTune)")
        // WarpMode=0 (Beats) is correct for drum rack pads. Template default is 4 (Complex Pro).
        tpl = tpl.replacingOccurrences(of: "<WarpMode Value=\"4\" />",
                                       with: "<WarpMode Value=\"0\" />")

        // Use compact InitialSlicePointsFromOnsets and add SlicePoints — matches native Ableton output.
        let tabs18 = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
        tpl = tpl.replacingOccurrences(
            of: "<InitialSlicePointsFromOnsets>\n\(tabs18)</InitialSlicePointsFromOnsets>",
            with: "<InitialSlicePointsFromOnsets />\n\(tabs18)<SlicePoints />")


        // Warp: set IsWarped=true and write Ableton-format near-start markers that define tempo.
        // Ableton uses two markers very close to t=0 to encode the sample's native BPM.
        // This matches exactly what Ableton produces when you click "Warp to N bars".
        // numBeats comes from userSelectableWarpPoolIndex — what the user explicitly set on the MPC.
        // If not set (0), fall back to round(duration * nativeBPM / 60).
        if pad.warpEnable && pad.nativeBPM > 0 {
            tpl = tpl.replacingOccurrences(of: "<IsWarped Value=\"false\" />",
                                           with: "<IsWarped Value=\"true\" />")
            // Ableton near-start marker: BeatTime=1/32, SecTime=(1/32)/nativeBPM*60
            let beatTime1: Double = 1.0 / 32.0   // = 0.03125
            let secTime1          = beatTime1 / pad.nativeBPM * 60.0
            // Replace the template's default 120BPM marker with the actual sample BPM
            let tabs20w = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
            let defaultMark = "\(tabs20w)<WarpMarker Id=\"1\" SecTime=\"0.015625\" BeatTime=\"0.03125\" />"
            let bpmMark     = "\(tabs20w)<WarpMarker Id=\"1\" SecTime=\"\(secTime1)\" BeatTime=\"\(beatTime1)\" />"
            tpl = tpl.replacingOccurrences(of: defaultMark, with: bpmMark)
        }

        // Ensure two WarpMarkers exist for all pads. The template has both but this
        // guards against any future template change. Warp pads already have their BPM marker.
        let tabs20g = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
        let tabs19g = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
        let singleMarker = "\(tabs20g)<WarpMarker Id=\"0\" SecTime=\"0\" BeatTime=\"0\" />\n\(tabs19g)</WarpMarkers>"
        let doubleMarker = "\(tabs20g)<WarpMarker Id=\"0\" SecTime=\"0\" BeatTime=\"0\" />\n"
            + "\(tabs20g)<WarpMarker Id=\"1\" SecTime=\"0.015625\" BeatTime=\"0.03125\" />\n"
            + "\(tabs19g)</WarpMarkers>"
        if !tpl.contains("WarpMarker Id=\"1\"") {
            tpl = tpl.replacingOccurrences(of: singleMarker, with: doubleMarker)
        }

        let tabs17 = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"

        // Gate mode (Note On): triggerMode=2 → Classic playback, stops on pad release.
        if pad.isGateMode {
            tpl = tpl.replacingOccurrences(of: "<PlaybackMode Value=\"1\" />",
                                           with: "<PlaybackMode Value=\"0\" />")
            // Gate release: MPC 0 (position 0) → 1ms minimum, MPC 1.0 (position 127) → 2000ms.
            let gateReleaseMs = max(1.0, pad.ampRelease * 2000.0)
            tpl = tpl.replacingOccurrences(
                of: "<ReleaseTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"60000\" />",
                with: "<ReleaseTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"\(gateReleaseMs)\" />")
        }

        // Polyphonic mode: monophonic=false → Classic + RetriggerMode off + 6 voices.
        if !pad.monophonic {
            tpl = tpl.replacingOccurrences(of: "<PlaybackMode Value=\"1\" />",
                                           with: "<PlaybackMode Value=\"0\" />")
            tpl = tpl.replacingOccurrences(of: "<RetriggerMode Value=\"true\" />",
                                           with: "<RetriggerMode Value=\"false\" />")
        }

        // Layer loop: layer.loop=true → Classic + looping, long sustain, instant release.
        if pad.layerLoop {
            tpl = tpl.replacingOccurrences(of: "<PlaybackMode Value=\"1\" />",
                                           with: "<PlaybackMode Value=\"0\" />")
            tpl = tpl.replacingOccurrences(
                of: "\(tabs17)<Manual Value=\"false\" />\n\(tabs17)<AutomationTarget",
                with: "\(tabs17)<Manual Value=\"true\" />\n\(tabs17)<AutomationTarget")
            tpl = tpl.replacingOccurrences(
                of: "<DecayTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"300\" />",
                with: "<DecayTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"60000\" />")
            tpl = tpl.replacingOccurrences(
                of: "<ReleaseTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"60000\" />",
                with: "<ReleaseTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"1\" />")
        }

        // Amplitude envelope: MPC 0-127 knob → 0-2000ms in ALS (mpc_normalized × 2000).
        // MPC stores a minimum non-zero value (1/63.5 × 2000 ≈ 31.5ms) when the knob is at 0.
        // We treat anything at or below this minimum as instant (0ms) in ALS.
        // For looping pads (warp or layerLoop), both FadeIn and FadeOut are forced to 0 to
        // prevent click artifacts at the loop boundary.
        // MPC knob 0-127, stored 0-1. Position 2 (= 2/127 ≈ 0.01575) → 5ms. Scale = 5 × 127/2 = 317.5.
        let mpcEnvScale = 317.5
        let rawAttackMs = pad.ampAttack * mpcEnvScale
        let rawDecayMs  = pad.ampDecay  * mpcEnvScale
        let isLooping   = pad.warpEnable || pad.layerLoop
        // Use actual MPC envelope values. Zero both fades only for looping pads.
        let fadeInMs     = isLooping ? 0.0 : rawAttackMs
        let fadeOutMs    = isLooping ? 0.0 : rawDecayMs
        let attackTimeMs = rawAttackMs  // Classic envelope attack (gate/loop pads)

        tpl = tpl.replacingOccurrences(
            of: "<AttackTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"0.1000000015\" />",
            with: "<AttackTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"\(attackTimeMs)\" />")
        tpl = tpl.replacingOccurrences(
            of: "<FadeInTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"0\" />",
            with: "<FadeInTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"\(fadeInMs)\" />")
        tpl = tpl.replacingOccurrences(
            of: "<FadeOutTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"0.1000000089\" />",
            with: "<FadeOutTime>\n\(tabs17)<LomId Value=\"0\" />\n\(tabs17)<Manual Value=\"\(fadeOutMs)\" />")

        // Polyphony voice count.
        let numVoices = pad.monophonic ? 1 : 6
        tpl = tpl.replacingOccurrences(of: "<NumVoices Value=\"2\" />",
                                       with: "<NumVoices Value=\"\(numVoices)\" />")

        // Filter injection.
        // MPC filterType: 0=Off, 29=Classic, 2=LPF2, 3=LPF4, 7=HPF2, 8=HPF4, 11=BPF2, 12=BPF4
        // Classic (29) is the MPC default and is always injected — it is present on every pad.
        if pad.filterType != 0 {
            let alsFilterType: Int
            switch pad.filterType {
            case 2, 3, 29: alsFilterType = 0   // LP
            case 7, 8:     alsFilterType = 1   // HP
            case 11, 12:   alsFilterType = 2   // BP
            default:       alsFilterType = 0
            }
            let alsSlope = (pad.filterType == 3 || pad.filterType == 8 ||
                            pad.filterType == 12 || pad.filterType == 29)
            let freq = 30.0 * pow(22000.0 / 30.0, pad.filterCutoff)
            let res  = pad.filterResonance * 1.25
            // Filter IDs: 400000 base (above blank ALS template max of ~300000).
            // 60 IDs per pad: max with 8 banks × 16 pads = 400000 + 127*60 + 51 = 407671 < 500000.
            let filterId = 400000 + (trackIndex * 16 + branchIndex) * 60
            let filterXML = buildSimplrFilter(type: alsFilterType, slope: alsSlope,
                                              freq: freq, res: res, idBase: filterId)
            let tabs15 = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
            let tabs16 = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
            let tabs14 = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t"
            tpl = tpl.replacingOccurrences(
                of: "<Filter>\n\(tabs15)<IsOn>\n\(tabs16)<LomId Value=\"0\" />\n\(tabs16)<Manual Value=\"false\" />",
                with: "<Filter>\n\(tabs15)<IsOn>\n\(tabs16)<LomId Value=\"0\" />\n\(tabs16)<Manual Value=\"true\" />")
            tpl = tpl.replacingOccurrences(
                of: "\(tabs16)<Value />\n\(tabs15)</Slot>\n\(tabs14)</Filter>",
                with: "\(tabs16)<Value>\n\(filterXML)\n\(tabs16)</Value>\n\(tabs15)</Slot>\n\(tabs14)</Filter>")
        }

        // pad.layerOffset: pending ALS mapping investigation.

        // Volume: als = (mpc / default)^2, where default=0.7079457640647888 → 1.0
        // Floor = 0.0003162277571 (-70dB), ceiling = 2.00261235 (+6dB)
        let alsVol: Double
        let mpcVol = pad.volume
        if mpcVol <= 0 {
            alsVol = 0.0003162277571
        } else {
            alsVol = min(2.00261235, pow(mpcVol / 0.7079457640647888, 2.0))
        }
        tpl = tpl.replacingOccurrences(of: "{{PAD_VOLUME}}",      with: "\(alsVol)")

        // Pan: the correct ALS target is the MixerDevice chain Panorama (idBase+94 = {{ID_94}}),
        // not the Simpler's internal Panorama (idBase+33 = {{ID_33}}).
        // Set {{PAD_PAN}} (Simpler internal) to 0 always — it is not the active pan control.
        // Set the MixerDevice Panorama <Manual> by searching backwards from {{ID_94}}.
        // If the pad has pan automation, also reset MixerDevice Panorama to 0 so the
        // envelope takes full control (avoids "stuck at last knob position" artefact).
        tpl = tpl.replacingOccurrences(of: "{{PAD_PAN}}", with: "0.0")
        let hasPanAuto = pad.automationEvents.contains { $0.parameter == MPC_PARAM_PAN }
        let chainPan   = hasPanAuto ? 0.0 : pad.pan * 2.0 - 1.0
        if chainPan != 0.0 {
            // Replace the <Manual Value="0.0" /> immediately before {{ID_94}}'s AutomationTarget.
            let neutralPan = "<Manual Value=\"0.0\" />"
            let targetPan  = "<Manual Value=\"\(chainPan)\" />"
            if let id94Range    = tpl.range(of: "{{ID_94}}"),
               let manualRange  = tpl.range(of: neutralPan, options: .backwards,
                                             range: tpl.startIndex..<id94Range.lowerBound) {
                tpl.replaceSubrange(manualRange, with: targetPan)
            }
        }

        // Pad mute: mixable.mute=true → set the MixerDevice <Speaker> Manual to false.
        // In a DrumRack chain, <Speaker> controls pad mute (not the Simpler's <On>).
        // The Speaker AutomationTarget is at idBase+91 = {{ID_91}}.
        // Search backwards from {{ID_91}} for the last <Manual Value="true" />, which
        // is the Speaker's Manual value immediately before its AutomationTarget line.
        if pad.muted {
            let trueMarker  = "<Manual Value=\"true\" />"
            let falseMarker = "<Manual Value=\"false\" />"
            if let id91Range   = tpl.range(of: "{{ID_91}}"),
               let manualRange = tpl.range(of: trueMarker, options: .backwards,
                                            range: tpl.startIndex..<id91Range.lowerBound) {
                tpl.replaceSubrange(manualRange, with: falseMarker)
            }
        }

        // Replace {{ID_0}} … {{ID_95}} with sequential integers
        for i in 0..<idsPerBranch {
            tpl = tpl.replacingOccurrences(of: "{{ID_\(i)}}", with: "\(idBase + i)")
        }

        return tpl
    }


    // MARK: - SimplerFilter XML builder

    /// Generates the SimplerFilter device XML injected into Simpler's <Filter><Slot>.
    /// type: 0=LP, 1=HP, 2=BP  |  slope: true=24dB/oct (4-pole), false=12dB/oct (2-pole)
    /// freq: 30-22000 Hz  |  res: 0-1.25  |  idBase: starting ID (51 IDs used total)
    private static func buildSimplrFilter(type: Int, slope: Bool,
                                          freq: Double, res: Double, idBase: Int) -> String {
        // Indentation: SimplerFilter lives inside Value which is inside the DrumBranch
        // hierarchy at depth 17. Build each line explicitly.
        let t  = String(repeating: "\t", count: 17)  // SimplerFilter children
        let t1 = String(repeating: "\t", count: 18)  // grandchildren
        let t2 = String(repeating: "\t", count: 19)  // great-grandchildren
        let t3 = String(repeating: "\t", count: 20)  // great-great-grandchildren

        var id = idBase

        // AutomationTarget only (bool/int params that have no ModulationTarget)
        func at() -> String {
            let i = id; id += 1
            return "\(t1)<AutomationTarget Id=\"\(i)\">\n\(t2)<LockEnvelope Value=\"0\" />\n\(t1)</AutomationTarget>"
        }
        // AutomationTarget + ModulationTarget (continuous params)
        func atmt() -> String {
            let i1 = id; id += 1; let i2 = id; id += 1
            return "\(t1)<AutomationTarget Id=\"\(i1)\">\n\(t2)<LockEnvelope Value=\"0\" />\n\(t1)</AutomationTarget>\n"
                 + "\(t1)<ModulationTarget Id=\"\(i2)\">\n\(t2)<LockEnvelope Value=\"0\" />\n\(t1)</ModulationTarget>"
        }
        // AutomationTarget with MidiCCOnOffThresholds (on/off toggle params)
        func ccAt() -> String {
            let i = id; id += 1
            return "\(t1)<AutomationTarget Id=\"\(i)\">\n\(t2)<LockEnvelope Value=\"0\" />\n\(t1)</AutomationTarget>\n"
                 + "\(t1)<MidiCCOnOffThresholds>\n\(t2)<Min Value=\"64\" />\n\(t2)<Max Value=\"127\" />\n\(t1)</MidiCCOnOffThresholds>"
        }
        // Envelope sub-param: AutomationTarget + ModulationTarget, with MidiControllerRange
        func envParam(_ tag: String, _ val: String, min: String, max: String) -> String {
            let ids = atmt()
            return "\(t2)<\(tag)>\n\(t3)<LomId Value=\"0\" />\n\(t3)<Manual Value=\"\(val)\" />\n"
                 + "\(t3)<MidiControllerRange>\n\(t3)\t<Min Value=\"\(min)\" />\n\(t3)\t<Max Value=\"\(max)\" />\n\(t3)</MidiControllerRange>\n"
                 + "\(ids)\n\(t2)</\(tag)>"
        }

        let freqStr  = String(format: "%.6g", freq)
        let resStr   = String(format: "%.6g", res)
        let slopeStr = slope ? "true" : "false"

        var x = ""
        x += "\(t)<SimplerFilter Id=\"0\">\n"

        // LegacyType (int 0-5, always 0)
        x += "\(t1)<LegacyType>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n\(at())\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"5\" />\n\(t2)</MidiControllerRange>\n\(t1)</LegacyType>\n"

        // Type (int 0-4: 0=LP, 1=HP, 2=BP)
        x += "\(t1)<Type>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"\(type)\" />\n\(at())\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"4\" />\n\(t2)</MidiControllerRange>\n\(t1)</Type>\n"

        // CircuitLpHp (int 0-4, always 0)
        x += "\(t1)<CircuitLpHp>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n\(at())\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"4\" />\n\(t2)</MidiControllerRange>\n\(t1)</CircuitLpHp>\n"

        // CircuitBpNoMo (int 0-1, always 0)
        x += "\(t1)<CircuitBpNoMo>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n\(at())\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"1\" />\n\(t2)</MidiControllerRange>\n\(t1)</CircuitBpNoMo>\n"

        // Slope (bool: true=24dB/oct, false=12dB/oct)
        x += "\(t1)<Slope>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"\(slopeStr)\" />\n\(ccAt())\n\(t1)</Slope>\n"

        // Freq (Hz, log 30-22000)
        x += "\(t1)<Freq>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"\(freqStr)\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"30\" />\n\(t3)<Max Value=\"22000\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</Freq>\n"

        // LegacyQ (float 0.3-10, default 0.7)
        x += "\(t1)<LegacyQ>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0.6999999881\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0.3000000119\" />\n\(t3)<Max Value=\"10\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</LegacyQ>\n"

        // Res (float 0-1.25)
        x += "\(t1)<Res>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"\(resStr)\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"1.25\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</Res>\n"

        // X (float 0-1, always 0)
        x += "\(t1)<X>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"1\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</X>\n"

        // Drive (float 0-24, always 0)
        x += "\(t1)<Drive>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"24\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</Drive>\n"

        // Envelope (filter envelope — all fixed values)
        x += "\(t1)<Envelope>\n"
        x += "\(envParam("AttackTime",   "0.1000000015", min: "0.1000000015", max: "20000"))\n"
        x += "\(envParam("AttackLevel",  "0",            min: "0",            max: "1"))\n"
        x += "\(envParam("AttackSlope",  "0",            min: "-1",           max: "1"))\n"
        x += "\(envParam("DecayTime",    "600",          min: "1",            max: "60000"))\n"
        x += "\(envParam("DecayLevel",   "1",            min: "0",            max: "1"))\n"
        x += "\(envParam("DecaySlope",   "1",            min: "-1",           max: "1"))\n"
        x += "\(envParam("SustainLevel", "0",            min: "0",            max: "1"))\n"
        x += "\(envParam("ReleaseTime",  "50",           min: "1",            max: "60000"))\n"
        x += "\(envParam("ReleaseLevel", "0",            min: "0",            max: "1"))\n"
        x += "\(envParam("ReleaseSlope", "1",            min: "-1",           max: "1"))\n"
        // LoopMode (int 0-4, no ModulationTarget)
        x += "\(t2)<LoopMode>\n\(t3)<LomId Value=\"0\" />\n\(t3)<Manual Value=\"0\" />\n\(at())\n"
        x += "\(t3)<MidiControllerRange>\n\(t3)\t<Min Value=\"0\" />\n\(t3)\t<Max Value=\"4\" />\n\(t3)</MidiControllerRange>\n\(t2)</LoopMode>\n"
        x += "\(envParam("LoopTime",     "100",          min: "0.200000003",  max: "20000"))\n"
        x += "\(envParam("RepeatTime",   "3",            min: "0",            max: "14"))\n"
        x += "\(envParam("TimeVelScale", "0",            min: "-100",         max: "100"))\n"
        x += "\(t2)<CurrentOverlay Value=\"0\" />\n"
        // IsOn (bool toggle, no ModulationTarget)
        x += "\(t2)<IsOn>\n\(t3)<LomId Value=\"0\" />\n\(t3)<Manual Value=\"false\" />\n\(ccAt())\n\(t2)</IsOn>\n"
        x += "\(envParam("Amount",       "0",            min: "-72",          max: "72"))\n"
        x += "\(t2)<ScrollPosition Value=\"0\" />\n"
        x += "\(t1)</Envelope>\n"

        // ModByPitch / ModByVelocity / ModByLfo
        x += "\(t1)<ModByPitch>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"1\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"1\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</ModByPitch>\n"

        x += "\(t1)<ModByVelocity>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"1\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</ModByVelocity>\n"

        x += "\(t1)<ModByLfo>\n\(t2)<LomId Value=\"0\" />\n\(t2)<Manual Value=\"0\" />\n"
        x += "\(t2)<MidiControllerRange>\n\(t3)<Min Value=\"0\" />\n\(t3)<Max Value=\"24\" />\n\(t2)</MidiControllerRange>\n\(atmt())\n\(t1)</ModByLfo>\n"

        x += "\(t)</SimplerFilter>"
        return x
    }




    // MARK: - Clip Envelope Generation (Session View per-clip automation)

    /// MPC fader automation parameter IDs (confirmed from XPJ recording).
    static let MPC_PARAM_VOLUME         = 518
    static let MPC_PARAM_PAN            = 517
    static let MPC_PARAM_TONE           = 1043
    static let MPC_PARAM_AMP_ATTACK     = 519
    static let MPC_PARAM_AMP_DECAY_REL  = 520
    static let MPC_PARAM_FILTER_CUTOFF  = 514

    /// ALS AutomationTarget offsets from idBase (confirmed from output.als analysis).
    static let CHAIN_TONE_AT_OFFSET     = 16   // TransposeKey
    static let GATE_ATTACK_AT_OFFSET    = 41   // AttackTime  (gate mode)
    static let GATE_DECAY_AT_OFFSET     = 47   // DecayTime   (gate mode)
    static let GATE_RELEASE_AT_OFFSET   = 55   // ReleaseTime (gate mode)
    static let ONESHOT_FADEIN_AT_OFFSET = 68   // FadeInTime  (one-shot mode)
    static let ONESHOT_FADEOUT_AT_OFFSET = 71  // FadeOutTime (one-shot mode)
    static let CHAIN_VOLUME_AT_OFFSET   = 92   // Chain Volume (MixerDevice)
    static let CHAIN_PAN_AT_OFFSET      = 94   // Chain Panorama (MixerDevice) ← confirmed correct

    /// MPC envelope scale: knob pos 0-1 → 0-317.5 ms  (MPC knob 0-127, max ≈ 317.5 ms).
    static let MPC_ENV_SCALE = 317.5

    /// Converts MPC volume (0-1, unity=0.7079) to ALS pad chain volume linear gain (0–2).
    /// At MPC unity (0.7079): 1.0. At 0: silence floor. At 1.0: ~1.41 (+3 dB).
    /// PointeeId = idBase + 92, range 0.0003162–1.99526.
    static func mpcVolumeToChainDb(_ v: Double) -> Double {
        guard v > 0 else { return 0.0003162277571 }
        return max(0.0003162277571, min(1.99526238, v / 0.7079457640647888))
    }

    /// Converts MPC pan (0-1, 0.5=centre) to ALS Panorama (-1=left, 0=centre, +1=right).
    static func mpcPanToALS(_ v: Double) -> Double {
        return max(-1.0, min(1.0, (v - 0.5) * 2.0))
    }

    /// Converts MPC pad tone (0-1, 0.5=no shift) to ALS TransposeKey in semitones (-24 to +24).
    static func mpcToneToALS(_ v: Double) -> Double {
        return (v - 0.5) * 48.0
    }

    /// Converts MPC amp attack/decay (0-1) to ALS FadeInTime / FadeOutTime / AttackTime ms.
    /// Same scale used for both one-shot and gate attack/decay.
    static func mpcEnvToMs(_ v: Double) -> Double {
        return v * MPC_ENV_SCALE
    }

    /// Converts MPC gate release (0-1) to ALS ReleaseTime ms.
    /// Range is 0-2000 ms, minimum 1 ms (Ableton floor).
    static func mpcReleaseToMs(_ v: Double) -> Double {
        return max(1.0, v * 2000.0)
    }

    /// Converts MPC filter cutoff (0-1 log-normalised) to ALS Freq in Hz (30-22000).
    static func mpcCutoffToHz(_ v: Double) -> Double {
        return 30.0 * pow(22000.0 / 30.0, v)
    }

    /// Returns clip-envelope data for pads that have volume or pan automation in the given sequence.
    /// The caller injects this into the ALSMIDIClip XML for the matching clip.
    ///
    /// - Returns: Array of (pointeeId, events[(timeBeats, gainLinear)]) — one per automated pad/parameter.
    static func buildClipEnvelopes(
        pads: [MPCPad],
        trackIndex: Int,
        sequenceName: String,
        ppq: Int
    ) -> [(pointeeId: Int, initialGain: Double, events: [(time: Double, gain: Double)])] {
        let idsPerBranch = 96
        let headerBase   = 30_000 + trackIndex * 10_000
        var result: [(pointeeId: Int, initialGain: Double, events: [(time: Double, gain: Double)])] = []

        for (bi, pad) in pads.enumerated() {
            let idBase = headerBase + 100 + bi * idsPerBranch

            // Volume automation
            let volEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_VOLUME && $0.sequenceName == sequenceName
            }
            if !volEvents.isEmpty {
                let sorted = volEvents.sorted { $0.time < $1.time }
                let events = sorted.map { (
                    time: Double($0.time) / Double(ppq),
                    gain: mpcVolumeToChainDb($0.value)
                )}
                result.append((
                    pointeeId:   idBase + CHAIN_VOLUME_AT_OFFSET,
                    initialGain: mpcVolumeToChainDb(sorted.first!.value),
                    events:      events
                ))
            }

            // Pan automation
            let panEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_PAN && $0.sequenceName == sequenceName
            }
            if !panEvents.isEmpty {
                let sorted = panEvents.sorted { $0.time < $1.time }
                let events = sorted.map { (
                    time: Double($0.time) / Double(ppq),
                    gain: mpcPanToALS($0.value)
                )}
                result.append((
                    pointeeId:   idBase + CHAIN_PAN_AT_OFFSET,
                    initialGain: mpcPanToALS(pad.pan),
                    events:      events
                ))
            }

            // Pad tone (coarse tune) automation
            let toneEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_TONE && $0.sequenceName == sequenceName
            }
            if !toneEvents.isEmpty {
                let sorted = toneEvents.sorted { $0.time < $1.time }
                let events = sorted.map { (
                    time: Double($0.time) / Double(ppq),
                    gain: mpcToneToALS($0.value)
                )}
                result.append((
                    pointeeId:   idBase + CHAIN_TONE_AT_OFFSET,
                    initialGain: mpcToneToALS(Double(pad.coarseTune) / 24.0 + 0.5),
                    events:      events
                ))
            }

            // Amp Attack automation (param 519).
            // One-shot pads → FadeInTime (+68).  Gate pads → AttackTime (+41).
            // Formula matches static path: v × 317.5 ms.
            let attackEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_AMP_ATTACK && $0.sequenceName == sequenceName
            }
            if !attackEvents.isEmpty {
                let sorted   = attackEvents.sorted { $0.time < $1.time }
                let offset   = pad.isGateMode ? GATE_ATTACK_AT_OFFSET : ONESHOT_FADEIN_AT_OFFSET
                let sentinel = mpcEnvToMs(pad.ampAttack)
                let events   = sorted.map { (
                    time: Double($0.time) / Double(ppq),
                    gain: mpcEnvToMs($0.value)
                )}
                result.append((pointeeId: idBase + offset, initialGain: sentinel, events: events))
            }

            // Amp Decay/Release automation (param 520).
            // One-shot pads → FadeOutTime (+71), formula v × 317.5 ms.
            // Gate pads     → ReleaseTime  (+55), formula max(1, v × 2000) ms.
            let decayEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_AMP_DECAY_REL && $0.sequenceName == sequenceName
            }
            if !decayEvents.isEmpty {
                let sorted = decayEvents.sorted { $0.time < $1.time }
                if pad.isGateMode {
                    let sentinel = mpcReleaseToMs(pad.ampRelease)
                    let events   = sorted.map { (
                        time: Double($0.time) / Double(ppq),
                        gain: mpcReleaseToMs($0.value)
                    )}
                    result.append((pointeeId: idBase + GATE_RELEASE_AT_OFFSET,
                                   initialGain: sentinel, events: events))
                } else {
                    let sentinel = mpcEnvToMs(pad.ampDecay)
                    let events   = sorted.map { (
                        time: Double($0.time) / Double(ppq),
                        gain: mpcEnvToMs($0.value)
                    )}
                    result.append((pointeeId: idBase + ONESHOT_FADEOUT_AT_OFFSET,
                                   initialGain: sentinel, events: events))
                }
            }

            // Filter Cutoff automation (param 514).
            // Only applies when the pad has a filter device injected (filterType ≠ 0).
            // PointeeId = filterBase + 5 (Freq parameter inside SimplerFilter).
            // Formula matches static path: 30 × (22000/30)^v Hz.
            guard pad.filterType != 0 else { continue }
            let cutoffEvents = pad.automationEvents.filter {
                $0.parameter == MPC_PARAM_FILTER_CUTOFF && $0.sequenceName == sequenceName
            }
            if !cutoffEvents.isEmpty {
                let filterBase = 400000 + (trackIndex * 16 + bi) * 60
                let sorted     = cutoffEvents.sorted { $0.time < $1.time }
                let sentinel   = mpcCutoffToHz(pad.filterCutoff)
                let events     = sorted.map { (
                    time: Double($0.time) / Double(ppq),
                    gain: mpcCutoffToHz($0.value)
                )}
                result.append((pointeeId: filterBase + 5, initialGain: sentinel, events: events))
            }
        }
        return result
    }


    // MARK: - ID remapping (header only — 2 known numeric IDs)

    /// Replace only original reference IDs (22000-23000 range) with unique per-track IDs.
    /// Branch IDs (30000+) are already unique and must NOT be remapped.
    private static func remapNumericIds(in xml: String, startingAt base: Int) -> String {
        let pattern = #"(?:AutomationTarget|ModulationTarget|Pointee) Id="(\d+)""#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return xml }

        let ns      = xml as NSString
        let nsRange = NSRange(location: 0, length: ns.length)
        let matches = re.matches(in: xml, range: nsRange)

        // Only remap IDs from original reference ALS (22182-22217 range)
        var seen:   [String: Int] = [:]
        var counter = base
        for m in matches {
            guard let gr = Range(m.range(at: 1), in: xml) else { continue }
            let old = String(xml[gr])
            // Remap template IDs: 22000-23000 (blank ALS) and 30000-30099 (drum rack header/footer)
            guard let v = Int(old), (v >= 22000 && v <= 23000) || (v >= 30000 && v < 30100) else { continue }
            if seen[old] == nil { seen[old] = counter; counter += 1 }
        }

        // Rebuild string forward (no stale range issues)
        var result  = ""
        var lastEnd = xml.startIndex
        for m in matches {
            guard let gr = Range(m.range(at: 1), in: xml) else { continue }
            let old = String(xml[gr])
            result += xml[lastEnd..<gr.lowerBound]
            if let newId = seen[old] { result += "\(newId)" } else { result += old }
            lastEnd = gr.upperBound
        }
        result += xml[lastEnd...]
        return result
    }

    // MARK: - Helpers

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension MPCPad {
    var padInBank: Int { padIndex % 16 }
}
