// WAVInfo.swift
// Reads the minimum WAV header fields needed for Ableton's FileRef block:
//   - total frame count  (SampleEnd / DefaultDuration)
//   - file size in bytes (OriginalFileSize)
//   - CRC16 checksum    (OriginalCrc)
//   - MPC atem chunk    (manual chop slice positions)
//
// Ableton's CRC is a standard CRC-16/ARC (poly 0xA001, init 0x0000).

import Foundation

struct WAVInfo {
    let frameCount: Int      // total sample frames in the file
    let fileSize:   Int      // file size in bytes
    let crc16:      Int      // CRC-16/ARC of the entire file
    let sampleRate: Int      // samples per second (from fmt chunk)
    let sliceStarts: [Int]   // frame positions of manual chop slice starts (from atem chunk)

    /// Read WAV info from a file URL. Returns nil if the file can't be read
    /// or isn't a valid WAV — the converter will still work, just with 0s.
    static func read(from url: URL) -> WAVInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let fileSize = data.count

        // Parse WAV header: "RIFF" (4) + size (4) + "WAVE" (4) + chunks
        guard data.count >= 44 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0...3].elementsEqual([0x52,0x49,0x46,0x46]),  // RIFF
              bytes[8...11].elementsEqual([0x57,0x41,0x56,0x45])  // WAVE
        else { return nil }

        // Walk chunks to find "fmt ", "data", and "atem"
        var pos = 12
        var channels: Int = 0
        var sampleRate: Int = 44100
        var bitsPerSample: Int = 16
        var dataFrames: Int = 0
        var sliceStarts: [Int] = []

        while pos + 8 <= bytes.count {
            let tag  = bytes[pos..<pos+4]
            let size = Int(bytes[pos+4])
                     | (Int(bytes[pos+5]) << 8)
                     | (Int(bytes[pos+6]) << 16)
                     | (Int(bytes[pos+7]) << 24)
            pos += 8

            if tag.elementsEqual([0x66,0x6d,0x74,0x20]) {  // "fmt "
                if pos + 16 <= bytes.count {
                    channels      = Int(bytes[pos+2]) | (Int(bytes[pos+3]) << 8)
                    sampleRate    = Int(bytes[pos+4]) | (Int(bytes[pos+5]) << 8)
                                  | (Int(bytes[pos+6]) << 16) | (Int(bytes[pos+7]) << 24)
                    bitsPerSample = Int(bytes[pos+14]) | (Int(bytes[pos+15]) << 8)
                }
            } else if tag.elementsEqual([0x64,0x61,0x74,0x61]) { // "data"
                let bytesPerFrame = max(1, channels * max(1, bitsPerSample / 8))
                dataFrames = size / bytesPerFrame
            } else if tag.elementsEqual([0x61,0x74,0x65,0x6d]) { // "atem"
                // MPC proprietary chunk: raw UTF-8 JSON
                if size > 0, let chunkData = try? Data(bytes[pos..<min(pos+size, bytes.count)]) {
                   let cleanData = chunkData.filter { $0 != 0 }  // strip trailing null byte
                   if let json = try? JSONSerialization.jsonObject(with: cleanData) as? [String: Any],
                   let v0 = json["value0"] as? [String: Any] {
                    // MPC atem format: slices stored as "Slice 0", "Slice 1", ... "Slice N-1"
                    // Each has "Start" and "End" frame positions
                    let numSlices = v0["Num slices"] as? Int ?? 0
                    if numSlices > 0 {
                        for i in 0..<numSlices {
                            if let slice = v0["Slice \(i)"] as? [String: Any],
                               let start = slice["Start"] as? Int {
                                sliceStarts.append(start)
                            }
                        }
                    }
                   }
                }
            }

            pos += size + (size & 1)  // chunks are word-aligned
        }

        let crc = crc16arc(data)
        return WAVInfo(frameCount: dataFrames, fileSize: fileSize,
                       crc16: crc, sampleRate: sampleRate, sliceStarts: sliceStarts)
    }

    // MARK: - CRC-16/ARC  (poly 0xA001, init 0, no final XOR)

    private static func crc16arc(_ data: Data) -> Int {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt16(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xA001 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt16 = 0
        for byte in data { crc = table[Int((crc ^ UInt16(byte)) & 0xff)] ^ (crc >> 8) }
        return Int(crc)
    }
}
