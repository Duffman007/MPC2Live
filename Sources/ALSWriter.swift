// ALSWriter.swift
// Handles loading the blank ALS template and writing a valid Ableton project.
//
// OUTPUT STRUCTURE
//   <name> Project/
//       <name>.als                       ← gzip-compressed XML
//       Ableton Project Info/
//           AbletonProject.cfg           ← Apple plist, required by Live
//       Samples/
//           Imported/                    ← WAV files copied here in Phase 3
//
// COMPRESSION
// Ableton .als = gzip-compressed XML UTF-8.
// Uses the system zlib C library (libz) directly with wbits=31 (gzip mode).
// Available on all Apple platforms without extra dependencies.
// On Linux: link with -lz (see Package.swift linkerSettings).

import Foundation
import zlib

enum ALSWriterError: Error, CustomStringConvertible {
    case base64DecodeFailed
    case decompressionFailed(String)
    case encodingFailed
    case compressionFailed(String)
    case ioError(String)

    var description: String {
        switch self {
        case .base64DecodeFailed:         return "Failed to decode base64 ALS template"
        case .decompressionFailed(let m): return "Decompression failed: \(m)"
        case .encodingFailed:             return "Failed to encode XML as UTF-8"
        case .compressionFailed(let m):   return "Compression failed: \(m)"
        case .ioError(let m):             return "IO error: \(m)"
        }
    }
}

struct ALSWriter {

    // MARK: - Public API

    /// Write a complete Ableton project folder.
    /// If `url` points to a plain .als path, the folder is created alongside it.
    ///
    ///   writeBlank(to: URL("~/Desktop/MyDrums.als"), bpm: 93)
    ///   →  ~/Desktop/MyDrums Project/
    ///          MyDrums.als
    ///          Ableton Project Info/AbletonProject.cfg
    ///          Samples/Imported/
    static func writeBlank(to url: URL, bpm: Double = 120.0) throws {
        var xml = try loadBlankTemplate()
        xml = setBPM(xml, bpm: bpm)
        try writeProject(xml: xml, to: url)
    }

    /// Conventional project folder URL for a given .als output path.
    /// e.g. ~/Desktop/MyDrums.als  →  ~/Desktop/MyDrums Project/
    static func projectFolderURL(for alsURL: URL) -> URL {
        let stem = alsURL.deletingPathExtension().lastPathComponent
        let dir  = alsURL.deletingLastPathComponent()
        return dir.appendingPathComponent("\(stem) Project", isDirectory: true)
    }

    // MARK: - Template loading

    static func loadBlankTemplate() throws -> String {
        guard let gzData = Data(base64Encoded: ALSTemplate.blankALSBase64,
                                options: .ignoreUnknownCharacters) else {
            throw ALSWriterError.base64DecodeFailed
        }
        return try gunzip(gzData)
    }

    // MARK: - XML mutations

    static func setBPM(_ xml: String, bpm: Double) -> String {
        let s = formatBPM(bpm)
        var result = xml

        // <Tempo> block: <Manual Value="120" />
        result = result.replacingOccurrences(
            of: #"(<Tempo>[\s\S]*?<Manual Value=")[\d.]+""#,
            with: "$1\(s)\"",
            options: .regularExpression
        )
        // Automation seed: FloatEvent Id="0" Time="-63072000" Value="120"
        result = result.replacingOccurrences(
            of: #"(FloatEvent Id="0" Time="-63072000" Value=")[\d.]+""#,
            with: "$1\(s)\"",
            options: .regularExpression
        )
        return result
    }

    /// Update NextPointeeId to be safely above all IDs we assign.
    /// Ableton rejects the file if any Id >= NextPointeeId.
    /// We use 200_000 — well above the ~31_000 max we assign for 8 banks × 16 pads.
    static func setNextPointeeId(_ xml: String, value: Int = 500_000) -> String {
        xml.replacingOccurrences(
            of: #"<NextPointeeId Value="\d+" />"#,
            with: "<NextPointeeId Value=\"\(value)\" />",
            options: .regularExpression
        )
    }

    /// Inject an Ableton Compressor2 (default settings) into the MainTrack Devices block.
    /// Called when the MPC project has an enabled Color Compressor on the master output.
    ///
    /// The blank template's MainTrack inner DeviceChain looks like:
    ///   <Devices />\n\t\t\t\t\t<SignalModulations />\n\t\t\t\t</DeviceChain>\n\t\t\t</DeviceChain>\n\t\t</MainTrack>
    /// We replace <Devices /> with a fully populated <Devices>…</Devices> block.
    static func injectMasterCompressor(_ xml: String, idBase: Int = 490_000) -> String {
        let t5  = String(repeating: "\t", count: 5)
        let t6  = String(repeating: "\t", count: 6)
        let t7  = String(repeating: "\t", count: 7)
        let t8  = String(repeating: "\t", count: 8)
        let t9  = String(repeating: "\t", count: 9)
        let t10 = String(repeating: "\t", count: 10)
        let t11 = String(repeating: "\t", count: 11)

        var id = idBase
        func uid() -> Int { let v = id; id += 1; return v }

        func param(_ name: String, _ val: String, _ mn: String, _ mx: String, hasMod: Bool = true) -> String {
            let atId = uid()
            let mtId = hasMod ? uid() : -1
            var s  = "\(t7)<\(name)>\n"
            s += "\(t8)<LomId Value=\"0\" />\n"
            s += "\(t8)<Manual Value=\"\(val)\" />\n"
            s += "\(t8)<MidiControllerRange>\n"
            s += "\(t9)<Min Value=\"\(mn)\" />\n"
            s += "\(t9)<Max Value=\"\(mx)\" />\n"
            s += "\(t8)</MidiControllerRange>\n"
            s += "\(t8)<AutomationTarget Id=\"\(atId)\">\n"
            s += "\(t9)<LockEnvelope Value=\"0\" />\n"
            s += "\(t8)</AutomationTarget>\n"
            if hasMod {
                s += "\(t8)<ModulationTarget Id=\"\(mtId)\">\n"
                s += "\(t9)<LockEnvelope Value=\"0\" />\n"
                s += "\(t8)</ModulationTarget>\n"
            }
            s += "\(t7)</\(name)>\n"
            return s
        }

        func boolParam(_ name: String, _ val: String) -> String {
            let atId = uid()
            var s  = "\(t7)<\(name)>\n"
            s += "\(t8)<LomId Value=\"0\" />\n"
            s += "\(t8)<Manual Value=\"\(val)\" />\n"
            s += "\(t8)<AutomationTarget Id=\"\(atId)\">\n"
            s += "\(t9)<LockEnvelope Value=\"0\" />\n"
            s += "\(t8)</AutomationTarget>\n"
            s += "\(t8)<MidiCCOnOffThresholds>\n"
            s += "\(t9)<Min Value=\"64\" />\n"
            s += "\(t9)<Max Value=\"127\" />\n"
            s += "\(t8)</MidiCCOnOffThresholds>\n"
            s += "\(t7)</\(name)>\n"
            return s
        }

        let onId = uid(); let ptId = uid()
        let scOnId = uid()
        let scVolAtId = uid(); let scVolMtId = uid()
        let scDwAtId  = uid(); let scDwMtId  = uid()

        var comp = "\(t6)<Compressor2 Id=\"0\">\n"
        comp += "\(t7)<LomId Value=\"0\" />\n"
        comp += "\(t7)<LomIdView Value=\"0\" />\n"
        comp += "\(t7)<IsExpanded Value=\"true\" />\n"
        comp += "\(t7)<BreakoutIsExpanded Value=\"false\" />\n"
        comp += "\(t7)<On>\n"
        comp += "\(t8)<LomId Value=\"0\" />\n"
        comp += "\(t8)<Manual Value=\"true\" />\n"
        comp += "\(t8)<AutomationTarget Id=\"\(onId)\">\n"
        comp += "\(t9)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t8)</AutomationTarget>\n"
        comp += "\(t8)<MidiCCOnOffThresholds>\n"
        comp += "\(t9)<Min Value=\"64\" />\n"
        comp += "\(t9)<Max Value=\"127\" />\n"
        comp += "\(t8)</MidiCCOnOffThresholds>\n"
        comp += "\(t7)</On>\n"
        comp += "\(t7)<ModulationSourceCount Value=\"0\" />\n"
        comp += "\(t7)<ParametersListWrapper LomId=\"0\" />\n"
        comp += "\(t7)<Pointee Id=\"\(ptId)\" />\n"
        comp += "\(t7)<LastSelectedTimeableIndex Value=\"0\" />\n"
        comp += "\(t7)<LastSelectedClipEnvelopeIndex Value=\"0\" />\n"
        comp += "\(t7)<LastPresetRef>\n"
        comp += "\(t8)<Value>\n"
        comp += "\(t9)<AbletonDefaultPresetRef Id=\"0\">\n"
        comp += "\(t10)<FileRef>\n"
        comp += "\(t11)<RelativePathType Value=\"0\" />\n"
        comp += "\(t11)<RelativePath Value=\"\" />\n"
        comp += "\(t11)<Path Value=\"\" />\n"
        comp += "\(t11)<Type Value=\"2\" />\n"
        comp += "\(t11)<LivePackName Value=\"\" />\n"
        comp += "\(t11)<LivePackId Value=\"\" />\n"
        comp += "\(t11)<OriginalFileSize Value=\"0\" />\n"
        comp += "\(t11)<OriginalCrc Value=\"0\" />\n"
        comp += "\(t11)<SourceHint Value=\"\" />\n"
        comp += "\(t10)</FileRef>\n"
        comp += "\(t10)<DeviceId Name=\"Compressor2\" />\n"
        comp += "\(t9)</AbletonDefaultPresetRef>\n"
        comp += "\(t8)</Value>\n"
        comp += "\(t7)</LastPresetRef>\n"
        comp += "\(t7)<LockedScripts />\n"
        comp += "\(t7)<IsFolded Value=\"false\" />\n"
        comp += "\(t7)<ShouldShowPresetName Value=\"true\" />\n"
        comp += "\(t7)<UserName Value=\"\" />\n"
        comp += "\(t7)<Annotation Value=\"\" />\n"
        comp += "\(t7)<SourceContext>\n"
        comp += "\(t8)<Value>\n"
        comp += "\(t9)<BranchSourceContext Id=\"0\">\n"
        comp += "\(t10)<OriginalFileRef />\n"
        comp += "\(t10)<BrowserContentPath Value=\"view:X-AudioFx#Compressor\" />\n"
        comp += "\(t10)<LocalFiltersJson Value=\"\" />\n"
        comp += "\(t10)<PresetRef>\n"
        comp += "\(t11)<AbletonDefaultPresetRef Id=\"0\">\n"
        comp += "\(t11)\t<FileRef>\n"
        comp += "\(t11)\t\t<RelativePathType Value=\"0\" />\n"
        comp += "\(t11)\t\t<RelativePath Value=\"\" />\n"
        comp += "\(t11)\t\t<Path Value=\"\" />\n"
        comp += "\(t11)\t\t<Type Value=\"2\" />\n"
        comp += "\(t11)\t\t<LivePackName Value=\"\" />\n"
        comp += "\(t11)\t\t<LivePackId Value=\"\" />\n"
        comp += "\(t11)\t\t<OriginalFileSize Value=\"0\" />\n"
        comp += "\(t11)\t\t<OriginalCrc Value=\"0\" />\n"
        comp += "\(t11)\t\t<SourceHint Value=\"\" />\n"
        comp += "\(t11)\t</FileRef>\n"
        comp += "\(t11)\t<DeviceId Name=\"Compressor2\" />\n"
        comp += "\(t11)</AbletonDefaultPresetRef>\n"
        comp += "\(t10)</PresetRef>\n"
        comp += "\(t10)<BranchDeviceId Value=\"device:ableton:audiofx:Compressor2\" />\n"
        comp += "\(t9)</BranchSourceContext>\n"
        comp += "\(t8)</Value>\n"
        comp += "\(t7)</SourceContext>\n"
        comp += "\(t7)<MpePitchBendUsesTuning Value=\"true\" />\n"
        comp += "\(t7)<ViewData Value=\"{}\" />\n"
        comp += "\(t7)<OverwriteProtectionNumber Value=\"3075\" />\n"
        comp += param("Threshold",         "1",               "0.0003162277571", "1.99526238")
        comp += param("Ratio",             "4",               "1",               "340282326356119256160033759537265639424")
        comp += param("ExpansionRatio",    "1.14999998",      "1",               "2")
        comp += param("Attack",            "1",               "0.009999999776",  "1000")
        comp += param("Release",           "30",              "1",               "3000")
        comp += boolParam("AutoReleaseControlOnOff", "false")
        comp += param("Gain",              "0",               "-36",             "36")
        comp += boolParam("GainCompensation", "false")
        comp += param("DryWet",            "1",               "0",               "1")
        comp += param("Model",             "1",               "0",               "2",    hasMod: false)
        comp += param("LegacyModel",       "1",               "0",               "2",    hasMod: false)
        comp += boolParam("LogEnvelope", "true")
        comp += param("LegacyEnvFollowerMode", "0",           "0",               "2",    hasMod: false)
        comp += param("Knee",              "6",               "0",               "18")
        comp += param("LookAhead",         "0",               "0",               "2",    hasMod: false)
        comp += boolParam("SideListen", "false")

        // SideChain block (off, no routing)
        comp += "\(t7)<SideChain>\n"
        comp += "\(t8)<OnOff>\n"
        comp += "\(t9)<LomId Value=\"0\" />\n"
        comp += "\(t9)<Manual Value=\"false\" />\n"
        comp += "\(t9)<AutomationTarget Id=\"\(scOnId)\">\n"
        comp += "\(t10)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t9)</AutomationTarget>\n"
        comp += "\(t9)<MidiCCOnOffThresholds>\n"
        comp += "\(t10)<Min Value=\"64\" />\n"
        comp += "\(t10)<Max Value=\"127\" />\n"
        comp += "\(t9)</MidiCCOnOffThresholds>\n"
        comp += "\(t8)</OnOff>\n"
        comp += "\(t8)<RoutedInput>\n"
        comp += "\(t9)<Routable>\n"
        comp += "\(t10)<Target Value=\"AudioIn/None\" />\n"
        comp += "\(t10)<UpperDisplayString Value=\"No Output\" />\n"
        comp += "\(t10)<LowerDisplayString Value=\"\" />\n"
        comp += "\(t10)<MpeSettings>\n"
        comp += "\(t11)<ZoneType Value=\"0\" />\n"
        comp += "\(t11)<FirstNoteChannel Value=\"1\" />\n"
        comp += "\(t11)<LastNoteChannel Value=\"15\" />\n"
        comp += "\(t10)</MpeSettings>\n"
        comp += "\(t10)<MpePitchBendUsesTuning Value=\"true\" />\n"
        comp += "\(t9)</Routable>\n"
        comp += "\(t9)<Volume>\n"
        comp += "\(t10)<LomId Value=\"0\" />\n"
        comp += "\(t10)<Manual Value=\"1\" />\n"
        comp += "\(t10)<MidiControllerRange>\n"
        comp += "\(t11)<Min Value=\"0.0003162277571\" />\n"
        comp += "\(t11)<Max Value=\"15.8489332\" />\n"
        comp += "\(t10)</MidiControllerRange>\n"
        comp += "\(t10)<AutomationTarget Id=\"\(scVolAtId)\">\n"
        comp += "\(t11)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t10)</AutomationTarget>\n"
        comp += "\(t10)<ModulationTarget Id=\"\(scVolMtId)\">\n"
        comp += "\(t11)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t10)</ModulationTarget>\n"
        comp += "\(t9)</Volume>\n"
        comp += "\(t8)</RoutedInput>\n"
        comp += "\(t8)<DryWet>\n"
        comp += "\(t9)<LomId Value=\"0\" />\n"
        comp += "\(t9)<Manual Value=\"1\" />\n"
        comp += "\(t9)<MidiControllerRange>\n"
        comp += "\(t10)<Min Value=\"0\" />\n"
        comp += "\(t10)<Max Value=\"1\" />\n"
        comp += "\(t9)</MidiControllerRange>\n"
        comp += "\(t9)<AutomationTarget Id=\"\(scDwAtId)\">\n"
        comp += "\(t10)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t9)</AutomationTarget>\n"
        comp += "\(t9)<ModulationTarget Id=\"\(scDwMtId)\">\n"
        comp += "\(t10)<LockEnvelope Value=\"0\" />\n"
        comp += "\(t9)</ModulationTarget>\n"
        comp += "\(t8)</DryWet>\n"
        comp += "\(t7)</SideChain>\n"

        comp += boolParam("SideChainEq_On", "true")
        comp += param("SideChainEq_Mode",   "5",              "0",   "5",  hasMod: false)
        comp += param("SideChainEq_Freq",   "80",             "30",  "15000")
        comp += param("SideChainEq_Q",      "0.7071067691",   "0.1000000015", "12")
        comp += param("SideChainEq_Gain",   "0",              "-15", "15")
        comp += "\(t7)<Live8LegacyMode Value=\"false\" />\n"
        comp += "\(t7)<ViewMode Value=\"2\" />\n"
        comp += "\(t7)<IsOutputCurveVisible Value=\"false\" />\n"
        comp += "\(t7)<RmsTimeShort Value=\"8\" />\n"
        comp += "\(t7)<RmsTimeLong Value=\"250\" />\n"
        comp += "\(t7)<ReleaseTimeShort Value=\"15\" />\n"
        comp += "\(t7)<ReleaseTimeLong Value=\"1500\" />\n"
        comp += "\(t7)<CrossfaderSmoothingTime Value=\"10\" />\n"
        comp += "\(t6)</Compressor2>\n"

        // The MainTrack's inner DeviceChain is uniquely preceded by </FreezeSequencer>.
        // The same 5-tab <Devices /> pattern also appears in PreHearTrack — use the
        // FreezeSequencer anchor to target only the MainTrack occurrence.
        let t4 = String(repeating: "\t", count: 4)
        let anchor  = "</FreezeSequencer>\n\(t4)<DeviceChain>\n\(t5)<Devices />"
        let anchRpl = "</FreezeSequencer>\n\(t4)<DeviceChain>\n\(t5)<Devices>\n\(comp)\(t5)</Devices>"
        if xml.contains(anchor) {
            return xml.replacingOccurrences(of: anchor, with: anchRpl)
        }
        // Fallback: if template changes, replace first occurrence
        let target      = "<Devices />\n\(t5)<SignalModulations />"
        let replacement = "<Devices>\n\(comp)\(t5)</Devices>\n\(t5)<SignalModulations />"
        return xml.replacingOccurrences(of: target, with: replacement, options: [],
                                        range: xml.range(of: target) ?? xml.startIndex..<xml.endIndex)
    }

    // MARK: - Project folder writer


    /// Set per-scene BPM values. scenes is [(bpm, enabled)] indexed 0-based.
    /// Only sets IsTempoEnabled=true when the scene BPM differs from the master.
    static func setSceneBPMs(_ xml: String, sequences: [(name: String, bpm: Double)],
                              masterBPM: Double) -> String {
        var result = xml
        for (i, seq) in sequences.enumerated() {
            let enabled = abs(seq.bpm - masterBPM) > 0.01
            let sceneTag = "<Scene Id=\"\(i)\">"
            guard let startRange = result.range(of: sceneTag),
                  let endRange   = result.range(of: "</Scene>",
                      range: startRange.lowerBound..<result.endIndex) else { continue }
            var scene = String(result[startRange.lowerBound..<endRange.upperBound])
            scene = scene.replacingOccurrences(
                of: "<Tempo Value=\"[0-9.]+\" />",
                with: "<Tempo Value=\"\(seq.bpm)\" />",
                options: .regularExpression)
            scene = scene.replacingOccurrences(
                of: "<IsTempoEnabled Value=\"[^\"]+\" />",
                with: "<IsTempoEnabled Value=\"\(enabled ? "true" : "false")\" />",
                options: .regularExpression)
            result = result.replacingCharacters(
                in: startRange.lowerBound..<endRange.upperBound, with: scene)
        }
        return result
    }

    static func writeProject(xml: String, to alsURL: URL) throws {
        let stem        = alsURL.deletingPathExtension().lastPathComponent
        let projectDir  = projectFolderURL(for: alsURL)
        let infoDir     = projectDir.appendingPathComponent("Ableton Project Info")
        let samplesDir  = projectDir.appendingPathComponent("Samples/Imported")
        let outALS      = projectDir.appendingPathComponent("\(stem).als")
        let outCFG      = infoDir.appendingPathComponent("AbletonProject.cfg")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: infoDir,    withIntermediateDirectories: true)
            try fm.createDirectory(at: samplesDir, withIntermediateDirectories: true)
        } catch {
            throw ALSWriterError.ioError("Could not create project folders: \(error.localizedDescription)")
        }

        // Write .als
        try save(xml: xml, to: outALS)

        // Write AbletonProject.cfg (Apple plist format, required by Live)
        let cfg = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>Creator</key>
            \t<string>Ableton Live 12.3.2</string>
            \t<key>MajorVersion</key>
            \t<integer>5</integer>
            \t<key>MinorVersion</key>
            \t<string>12.0_12300</string>
            \t<key>SchemaChangeCount</key>
            \t<integer>1</integer>
            </dict>
            </plist>
            """
        do {
            try cfg.write(to: outCFG, atomically: true, encoding: .utf8)
        } catch {
            throw ALSWriterError.ioError("Could not write .cfg: \(error.localizedDescription)")
        }
    }

    // MARK: - Low-level file write

    static func save(xml: String, to url: URL) throws {
        guard let data = xml.data(using: .utf8) else {
            throw ALSWriterError.encodingFailed
        }
        let compressed = try gzip(data)
        do {
            try compressed.write(to: url, options: .atomic)
        } catch {
            throw ALSWriterError.ioError(error.localizedDescription)
        }
    }

    // MARK: - Gzip decompress (wbits = 31 = 15+16, gzip auto-detect)

    static func gunzip(_ data: Data) throws -> String {
        let decompressed = try zlibProcess(data, deflating: false)
        guard let str = String(data: decompressed, encoding: .utf8) else {
            throw ALSWriterError.decompressionFailed("Result is not valid UTF-8")
        }
        return str
    }

    // MARK: - Gzip compress (wbits = 31 = 15+16, gzip output)

    static func gzip(_ data: Data) throws -> Data {
        return try zlibProcess(data, deflating: true)
    }

    // MARK: - zlib stream processor

    private static func zlibProcess(_ input: Data, deflating: Bool) throws -> Data {
        // wbits 31 = MAX_WBITS(15) + 16 = gzip format for both inflate and deflate
        let wbits: Int32 = 15 + 16

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree  = nil
        stream.opaque = nil

        let initResult: Int32
        if deflating {
            initResult = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                                       wbits, 8, Z_DEFAULT_STRATEGY,
                                       ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        } else {
            initResult = inflateInit2_(&stream, wbits, ZLIB_VERSION,
                                       Int32(MemoryLayout<z_stream>.size))
        }
        guard initResult == Z_OK else {
            let msg = "\(deflating ? "deflate" : "inflate")Init2_ returned \(initResult)"
            throw deflating ? ALSWriterError.compressionFailed(msg)
                            : ALSWriterError.decompressionFailed(msg)
        }
        defer {
            if deflating { _ = deflateEnd(&stream) } else { _ = inflateEnd(&stream) }
        }

        // Streaming loop — grow output in 256 KB chunks.
        // MPC .xpj files compress ~63:1 so we can't predict output size from input.
        let chunkSize = 262_144
        var output    = Data()
        var chunk     = Data(count: chunkSize)
        var status: Int32 = Z_OK

        try input.withUnsafeBytes { (srcBuf: UnsafeRawBufferPointer) in
            guard let srcBase = srcBuf.baseAddress else { return }
            stream.next_in  = UnsafeMutablePointer(
                mutating: srcBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(input.count)

            repeat {
                let written: Int = chunk.withUnsafeMutableBytes { dstBuf -> Int in
                    guard let dstBase = dstBuf.baseAddress else { return 0 }
                    stream.next_out  = dstBase.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(chunkSize)
                    status = deflating
                        ? deflate(&stream, Z_FINISH)
                        : inflate(&stream, Z_FINISH)
                    return chunkSize - Int(stream.avail_out)
                }
                if written > 0 { output.append(chunk.prefix(written)) }
            } while status == Z_OK || (status == Z_BUF_ERROR && stream.avail_in > 0)
        }

        guard status == Z_STREAM_END else {
            let msg = "zlib status \(status): \(stream.msg.map { String(cString: $0) } ?? "none")"
            throw deflating ? ALSWriterError.compressionFailed(msg)
                            : ALSWriterError.decompressionFailed(msg)
        }
        return output
    }
    // MARK: - Helpers

    private static func formatBPM(_ bpm: Double) -> String {
        bpm.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(bpm)) : String(bpm)
    }
}
