// ALSSimpler.swift
// Builds an Ableton OriginalSimpler DeviceChain for note-mode (16 Levels Tune) pads.
// Template extracted from Koala2Live (KoalaALS.py) _SIMPLER_DC_TPL_B64.
// Injected into a plain MidiTrack's <DeviceChain><DeviceChain> in place of <Devices />.

import Foundation

enum ALSSimpler {

    // Base64-encoded gzip of the blank Simpler DeviceChain XML
    // Source: Koala2Live _SIMPLER_DC_TPL_B64 (Ableton Live 12.3.2)
    private static let templateB64 =
        "H4sIAPRwx2kC/+1dW3PbuJJ+9v6K1LzHvN+quFvlOPGMa+xYa3o855w3RIJtlilCS1JOdLb2vy/A"
        + "i0QSF0oWQdqW8jA1Fpog2F93oxvoBvyv8CWcwvMnEMb/9R8n+T+/+C2t/j7xb5LwMYxBFITzRQST"
        + "T5ez//xN/W3dfuJfofnl7NM9iJaQtHxS2m33IfzJab9Mv/1agHgG1x1kyRI2ab4kEDyjZUbTPoAo"
        + "bRHfxJs/hEM78a9BvAQR970n/tkyQ3OQhSi+A8kjzPJP1y1NdWqfn79l+vwtfoERWkDey5R2Z42R"
        + "hLPw/Pwmvnl4uHtKYPqEolnaeMV1GFc922aza/Ihv6pGTXfaL+7o3FfqLPOv0WwZ5cMM0DLBwoGW"
        + "ccYBbwISMIcZTNKrMM3+TsBigeUj5zlNi8I4g3DNQrclJyDNAhjBaQZnd+Ecgh8RvMRQ/+LJVY3+"
        + "PAoXFfu7nplgBsDsFj7UWZSTNzh6EUZwTZqPWWtAXlA0uyG/3kLCuxc4AdnT3WojDVoLshZpRXZ6"
        + "qlz/82wyUZ4RiMAUzX8gZZKA1acLlHz6J1oqEzD7dK7qp2D2QvdY70n5K8WwKOEcTK1n5StMnzO0"
        + "2Kfz+tfodPNV/iXT5+9YICoyPtVGJ2maytwQBgfhv3kKVSc9T6YCqkKO/wg3Ytym8RUGmsWPTHlR"
        + "WgLjKxzRyi0DnAXTJFxkacvwXWA9FJqy4Aktoxn+78+i6zpvaStJAK9TlGg2ic7iGGW5djN54Vc6"
        + "j1X1V0apSINU4dD61ws4CbPp0xcYz/Cg0rtlHMaP/IGT2eEryEBF8b//17LoLzD5mYQZxgJlWOHx"
        + "4L8v5z+wpSkfMFTHahmbCKxg0rCwyygLA0BmsGuwaOBc/IptWZY2paL2DGktJ75Pl3GY/bWYgQye"
        + "JTCIyGR5kaD5TYwhSr/NwozYrrMHbBZvIZitkf0DpJfzBUqwwcofyg1iWjHkO4Sz9AzL8ioNU8KN"
        + "sqGtQIL5jLTXBeDm7o9vtwx1yK1mTQLoia+Qz7MpMU9iqgBFiC/BOcmfcHUL4kfY/Lkxo9EfIp7T"
        + "coLzBKXpA5jBjo42dOIefYU9Uv8eTyzTMOv8Cq2vr9D2+grBcEvsUfJOABEM179FKMOArZ0ihjJ8"
        + "hdkyFs0f2DLBYAqizTStqqxpNUbYzwGCju5RtJyLJvurMH7u0JPC0AQZsTSCySyn+havjYBmmqbF"
        + "eGOwTDPs1l8htGgD0PGOE7+7+9xPhFuhLCLqREjhfgbxnyBI4Xv/QO5nlFBTPibH9dzJ+Xyt+1kM"
        + "KVWqiUzJ55jTn+CF9Yp9/dHd3iZ2ULd1UbdzUgVuqmvbrmaLnqh5q5Zum0zabp+V47VWcQ6WXuxF"
        + "bETAcUzbMSyNJekNR47RnMPwVwoeGwNii/sDwE7T12XS8DGJjtk6n76U9Np4TVdVWS8oReIOkWj6"
        + "b5AsBDZX4SiQT9wv7JGug2Gh9S+Jv0CQ/Z6Ea1qTS3kLH/Gnp2t54BIG2SqCnaaefCR2fHFgnYUw"
        + "bfODtF6D5BnrFiVDm7bKcw3glMTW+f+TD1r/oXQ9rNUeNk5V1bN1S63+6fXe3C1605u96Zrhaobp"
        + "2Bbp1Wj0dqoamm6xhJ//6cXrOsz37wmIlxHAccXqDsUw3QQTHcRYR5bJumubNbaLaDnNlsVaT5Oc"
        + "+SnniAD9C6OMLd8c4KhAJJF1+vaik6Yz2O/f4dGnIYxxbJpiR6WumbaInMxJdTbqImJqKMyhX6YE"
        + "G1HUW63ikWCKkiMyiRRNDCHDAVatveMFCvMNPpG6IHyMAQGNnmLqrdToyJw6xxEqCf8alNSK6SZc"
        + "w14jNpUo4ZuV0k7GaI7njm5K8mKB2BceB3OU1Ncqws9tNbdbK3tJ9XoR/oIz6ruZLkpOyvh09vRK"
        + "3naJp7DkBUQT/OR6YVdnGrjvGYo2Ws90GIIYLO5Q3eozg+BqpJ0ix+ZJNU+JDL1P1hxCENUWDjZL"
        + "Dsz5paSi2oo1bxEFGaWovZjfRBRYC7+uYjAPp+u+UvEywuaJWu8dzwgWX4RI+EprXae56MdZDfKv"
        + "EMDidQvmos6x67WCSWdkIPK4cGC7jGe36McmiGa+aUMmmulqZLdkCXECkxDNtqEG8QzNA7gRa83R"
        + "XMPTdVOjNhh4a2t+OYOQDQXUnKbxTFA2QJF21aPiJorilbDW3g6jnWyKYP4nKIogc4FBuIrRWA1h"
        + "SFhH7/ydJY9e8evcW+rYXWps6jRfp6mvfF27Q5YOUaCVYF7B+DF72gNN7b2gqWnDoqlLRJNGLdfu"
        + "xnbrrkCyDDufmYYcZnZtvXZsvnaujHZuwOb7RxQrc+4ekKqYw6qKJUVV2JjlUF5gf+AQZjDsnA8K"
        + "pCMNyBZixY9Mbwb7xC8wSWELdAG8LXSZHh6Xw+5vbUHq/mIxf7ewgmIjKLaB3SaQRKVtFubx16tZ"
        + "ynImuRz1PiJHW+yrXOlyT+3VjKWbu0yFyA5t9Zn8zrmQ6qoESDk2SNde9S6BBVq70DRYfrD8cZNO"
        + "W7HUXm4YO0zmclb/wH5Ym5N+EKHWQKlMmByuJhnZt2yh5OdrUwtUIF6P2Y1WPP1XSlYG0myCflIr"
        + "CXT2jNLOdfHz5Jt6h/ka7QKl8E+4GkftP5uuSPGp1j303hhQ783+9Z6D1QbDizCGI4FoCa23pfYH"
        + "ojUgiLZEEFtgFap59YDO5iSr9i1Owf1h6AyIods/hlyo/KrjPqfgnVZCdO84A1OZbUVxQo7amhPM"
        + "fTf/LMvA9JnsXtGpH+L0SloRT7VyD1yzmNRdMXpbN8X9NRisq8wUiS1id5FseTa9T7mdeHVLmEiF"
        + "PWev94qi+WJgPNBLcbjC4We0vzz0IQSftS7otf5hd0eC3RsCdha4Je5B25IfFO7YhoyCu65qQ+DO"
        + "Atf/Cqdg1Yv1tzzv1PM813H7gL8TfVuGwddVfSQJMORKAA/mAv9+zL32btXeHAl0awDQmdY+b+nH"
        + "2L9f1O2RUHcGQJ1p66vqgYN27nTVHQl3yc6dAN2qOqSfeV49zWMy4z3P89pInp4m2dPjA72uEDps"
        + "7ddGcvA0YxDgRdp/4PO9NpKXp1mDIM+c8auaBTn6zuW0bM9q13XELmEzXyls6yQYJuN7mW01tZhu"
        + "Da2fFVW9XFE1RllQ1TVnJCV05SohB29sehdl9dbekmD0IgCddtfsH3NvHMx1Vbbh5WCblx3dwygv"
        + "pn8rrpbaDb0Efde1kbDX5WIvQNg/XyYJjDNyUEsEVqKqS3rje0QJMd3OadLtXz6MkeTDlLzizkLW"
        + "D6aERxOUhvWqU+ZBD4wN3NbuMX1MF513xXiUMwhsIBzDMTVXN9sZVc0EKnLeQtY8TYjapJaVmWqo"
        + "HzEztcU+aoufscNfbfAXWDB39v0r+AimK3IOBO2ciu1Lt3nh6zMd7GyrVp3avI1J6/J1GilarDF0"
        + "1xEoPMb6Q/Pafj+8Nl/JawaXz8Nkugyzq8UfiyGZ7Xx8ZnM5W/H8y+I7ukZDct19P1zX9uM6i7c+"
        + "Z1FnJ36zq/T5LPdks1ycVNeZVrfN4WvKNtl7CoO7/kUC/2dPhus6+7SeHeXN6BI43nu2WbjioW+o"
        + "MtHnOOOGtsdLxa64r9CAlp7Rf+9rx05tL//nutr+aKunRpnqqHldIt876PoYoBsSQWci7N/Sx7b0"
        + "MHf1PY2c6lbf+Jpj4GtJxJdC0v/HO0C2b1jtMWB1JML6j/aRpUn4At8+sLrZN7LuGMh6EpFlIMms"
        + "HDk5ViSIRcMcKXHF1I4VCVvvofWP+khZK6ZxLEgYM2fFHClnxbSOBQlvI1HRHClL2XSOBQmjWfuR"
        + "MpRN71iPMJ6tt0by7CztWI8worJbI7l2lnEsR3gzs7w1kp9nWcdyhFGVfyTvznKO1Qgjz/Yj+XiW"
        + "d2jVCLZ6rEY4ViOwRWOk7GRbP1YjjFWNYI+UcWybx2qEsasRbGsk7O33UI1AHdr2Gvng3QnDhcQZ"
        + "YHbuyjjrTjnrzjnbLumMcaTbyVsrBHH0LgYwKfZUzZH8Ydt724Ug7E1y8jlfVu2jbV+THqG9v7wX"
        + "Z4wcRUdmjiIPzQLm6grjw8twcsZITHQM2UizAS3AvnpAB5jw5IyRoehYsoFug7mu66Nq6Bj1fO1y"
        + "vvyC28ZTfvAEFj2W4u1074ahHW4tXuvGtzZObVjKC9HP4tkENHovfn81Xp81fa8TzA1bxECq9fWn"
        + "X7cTzGWefm0Y/Z9+TeFUIseKuXY7uvzUMIsiAvMdHGJumAPCaMmCkQFaCeefcLUnnHupozYQivaA"
        + "KDqyUGRgVaJ4GBcKGO6AKHqyUGTeKIAnSZSAOfjYamgOeCWTKeFKJgZKa+QOw5CaA3o1piEPQZYp"
        + "rdpu49mHNqPmgC6NacnDsInTGr7DmAvNAT0a05EH4vb363CqZXa8RFVQzLTjfaqisqjObfw9rlel"
        + "MqXlXq9qelKuV2WjyS182hXlPF/D1nXHsZx9b0AWdybtGl1LHRRnS5OIMwUot9Rp0DuRPw+Ipj4s"
        + "moZENCnUOAVMu2HJL13aDVQxpnbP1tga9tZyS86t5Uz8eGVJw94/P5b1HfYSc8uRhyttfDnlKYMC"
        + "O6TtHdZjsjx5WNKml1tzchBqag/rJNlynCQehtyioR1nVm650FueWe1hPSZbjsfEQZBfCnSAkY49"
        + "rA9lWzKR5irx4cy39rC+k+3IxJOecZkVJ/vGrVxeuvJuet7aLgglx9xZcthFO+yKnR11hFurs6sl"
        + "5FfpyFzbs71BNcdRpWgOC0heHc5u+Bp7wio2gWaPSDrasEjqkmwgCzR+dc3Aq3dqB6C96qZjDIuo"
        + "KQVRHnTb1cywb1e4iWHwhDLmrs0FmMHLuLddG9eTaQH0fq25Yw0rMbYUiWEjWK07DOYIOc5bd4S0"
        + "VzhCHC7manOzzA5Ub4Zdr3M8aXpDQ+grXGtZJYi1c6Yxn35h6nFS3l31mPLOSXlvw+I3Sx+GuyLI"
        + "1Y5XBJU0RakJBoJ9P9DAt9U49se/GYhxWw25fmAJ4+nqDdRpnqpqUWzgOY7dwQKj70sGHGeMEi9X"
        + "8s0SDGj9W5DBoZXL+/j35LDZ6n/BQTlp2pPb5gBVk32Xx7pjFEK7Mguh2WD6QQYTiNgnG0nTKVf/"
        + "+DrFY6wfLML47dchq6d9X5XiGmOolClRpWgk/ckTSN/BtRqG3bcP4lpjoGtLRJcBpY/DiJQe3kHg"
        + "O4aP6cr0MVlYbmIKVp3VyUGcDOJ6IyDtqUNEE2xQ/WCOUPa095111vvD2tPGwFqXOSczsCyrAPYG"
        + "WHRB0e4rBh3XJ3Ue0Lkf8GM4Y55MZ4yFsX8LsyR8fGyeB3Mi/aJXzzqYi145HPb/Dmf7m9R3aFDH"
        + "uDjQk3lxIA3k+qil1hlM25yz1HiE7DjhH9JTdaRNJ/246cTfdGojs0ZLGwkt44hWB1o1ZHzs635N"
        + "G+XOWNOxVYvhlDCjqXTVMalcNm4e5KbsCLpvv1qT++o6G5Q2H/x7GB0ZQ4x1iw8kgfzIm3VSNsWe"
        + "XJezJBIO8iD4c+JfQDj7gd1t9sOl3WvxasNA7cjArRmosRioHxm4NQN1FgONIwO3ZqDBYqB5ZODW"
        + "DDRZDLSODNyagTVe+b9H6AeOGur9fF/O71E4hSknx2hDgKMFkidZxvaCKGSzcEQ2cPmrQLWQ/Bam"
        + "KFrWmdE6QdYPFgkEs7d7aJSq9nZslDvg2V+uhLO/OFCRoOpfiCTWhg8jQfjZdEUgUq17YDjg0V+u"
        + "hKO/OFj5E5RkYA7jDDFKA/dAkctHV9K6RR9Kr+8oLr7CZV+NsVQVxy6MLY8RIGcL7WPqhCewNaxe"
        + "n3bPG05nPFXCcXk8CP38Co0vMJ7lzODNtNcLyCZs26XtrmkhJ/TRJWTlLH4wFYHesDWenpwaTwZq"
        + "FZLMbfkPjeiwNZ6eKRNR5onEZdtlPI2WM8jYm90NXtb+K5+7lrwSvo7tUPGua8ee6xY7rmum8xib"
        + "E1BHDl+m5Y6dIJKZRGBForF6wNM2x1fwEUxXdQo6dvIVKkTz70P4M4BZFsaPjcgtgBGODOFsAh65"
        + "7yQ+3LdZmKHkPkzDHxEUhW0BnKJ4lopJincGgHDk/Ang6JRnRvx7mGQh5mZB/C+E5pyNY8xiIj1F"
        + "599igMc5E46iwOMLDjOe0TLr/DRfYfOw6iiIwilu2Q3Q9UZu+2lfucHRbxjjDy8IqhZyPNgLiaTX"
        + "PwThIybbGIp0/YKKFrO4SpNt/vT/FIsWeRXuAAA="

    // MARK: - Public

    /// Build a Simpler DeviceChain XML string for the given pad.
    /// Returns the inner DeviceChain block to replace <Devices /> in the MidiTrack.
    /// `canonicalFile` is the deduplicated filename that was actually copied to Samples/Imported/
    /// (may differ from pad.sampleFile which can have a 3-digit suffix e.g. "Kick001.wav").
    static func build(
        pad: MPCPad,
        samplesURL: URL,
        canonicalFile: String? = nil
    ) -> String {
        guard let compressed = Data(base64Encoded: templateB64,
                                    options: .ignoreUnknownCharacters),
              let xml = try? ALSWriter.gunzip(compressed)
        else { return "<!-- ALSSimpler: template decode failed -->" }
        return patch(xml, pad: pad, samplesURL: samplesURL, canonicalFile: canonicalFile)
    }

    // MARK: - Private

    private static func patch(_ xml: String, pad: MPCPad, samplesURL: URL,
                              canonicalFile: String? = nil) -> String {
        // The template ends with two </DeviceChain> tags — strip the extra trailing one
        // (it was captured as part of the outer MidiTrack DeviceChain in the reference)
        var tpl = xml
        if let lastRange = tpl.range(of: "</DeviceChain>", options: .backwards) {
            tpl = String(tpl[..<lastRange.lowerBound])
        }

        // Use canonical filename for the path — the dedup logic may have mapped
        // e.g. "Kick001.wav" → "Kick.wav" and only copied the canonical to Samples/Imported/.
        let effectiveFile = canonicalFile ?? pad.sampleFile
        let relPath    = "Samples/Imported/\(effectiveFile)"
        let wavURL     = samplesURL.appendingPathComponent(effectiveFile)
        let info       = WAVInfo.read(from: wavURL)
        let sampleEnd  = info?.frameCount ?? 0
        let fileSize   = info?.fileSize ?? 0
        let displayName = pad.sampleName
        let padName     = padLabel(pad)

        // UserName = pad label e.g. "H01"
        tpl = replaceFirst(tpl,
            pattern: #"<UserName Value="[^"]*""#,
            with: "<UserName Value=\"\(xmlEscape(padName))\"")

        // Name (display name in Simpler header)
        tpl = replaceFirst(tpl,
            pattern: #"<Name Value="[^"]*""#,
            with: "<Name Value=\"\(xmlEscape(displayName))\"")

        // RelativePath to sample
        tpl = replaceFirst(tpl,
            pattern: #"<RelativePath Value="[^"]*\.(?:wav|WAV|aif|aiff|mp3)[^"]*""#,
            with: "<RelativePath Value=\"\(xmlEscape(relPath))\"")

        // Clear stale absolute Path for the sample — Ableton resolves via RelativePath.
        // The template was built from a Koala2Live reference and contains a hardcoded
        // absolute path (e.g. OTHER.wav) that must be blanked out.
        tpl = replaceFirst(tpl,
            pattern: #"<Path Value="[^"]*\.(?:wav|WAV|aif|aiff|mp3)[^"]*""#,
            with: "<Path Value=\"\"")

        // Clear stale .adv preset FileRef paths (Koala2Live template artefacts).
        tpl = tpl.replacingOccurrences(
            of: #"<RelativePath Value="[^"]*\.adv[^"]*" />"#,
            with: "<RelativePath Value=\"\" />",
            options: .regularExpression)
        tpl = tpl.replacingOccurrences(
            of: #"<Path Value="[^"]*\.adv[^"]*" />"#,
            with: "<Path Value=\"\" />",
            options: .regularExpression)

        // SampleEnd
        tpl = replaceFirst(tpl,
            pattern: #"<SampleEnd Value="[^"]*""#,
            with: "<SampleEnd Value=\"\(sampleEnd)\"")

        // PlaybackMode: 1 = one-shot, 0 = classic
        let playbackMode = pad.oneShot ? 1 : 0
        tpl = replaceFirst(tpl,
            pattern: #"<PlaybackMode Value="[^"]*""#,
            with: "<PlaybackMode Value=\"\(playbackMode)\"")

        // OriginalFileSize and OriginalCrc
        tpl = replaceFirst(tpl,
            pattern: #"<OriginalFileSize Value="[^"]*""#,
            with: "<OriginalFileSize Value=\"\(fileSize)\"")

        return tpl
    }

    private static func padLabel(_ pad: MPCPad) -> String {
        let letter = String(UnicodeScalar(UInt32(65 + pad.padIndex / 16))!)
        let num    = String(format: "%02d", (pad.padIndex % 16) + 1)
        return "\(letter)\(num)"
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replaceFirst(_ xml: String, pattern: String, with replacement: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return xml }
        let ns  = xml as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = re.firstMatch(in: xml, range: range),
              let r = Range(match.range, in: xml) else { return xml }
        return xml.replacingCharacters(in: r, with: replacement)
    }
    // MARK: - Chop / Slice mode

    /// Build a Simpler DeviceChain in Slice mode for a chop pad.
    /// PlaybackMode=2, SlicingStyle=2 (Region), SlicingRegions=chopRegions.
    static func buildSlice(
        pad: MPCPad,
        samplesURL: URL,
        sliceStarts: [Int] = [],
        sampleRate: Int = 44100,
        canonicalFile: String? = nil
    ) -> String {
        guard let compressed = Data(base64Encoded: templateB64,
                                    options: .ignoreUnknownCharacters),
              let xml = try? ALSWriter.gunzip(compressed)
        else { return "<!-- ALSSimpler: template decode failed -->" }
        return patchSlice(xml, pad: pad, samplesURL: samplesURL,
                          sliceStarts: sliceStarts, sampleRate: sampleRate,
                          canonicalFile: canonicalFile)
    }

    private static func patchSlice(_ xml: String, pad: MPCPad, samplesURL: URL,
                                    sliceStarts: [Int], sampleRate: Int,
                                    canonicalFile: String? = nil) -> String {
        var tpl = xml
        // Strip extra trailing </DeviceChain>
        if let lastRange = tpl.range(of: "</DeviceChain>", options: .backwards) {
            tpl = String(tpl[..<lastRange.lowerBound])
        }

        let effectiveFile = canonicalFile ?? pad.sampleFile
        let relPath     = "Samples/Imported/\(effectiveFile)"
        let wavURL      = samplesURL.appendingPathComponent(effectiveFile)
        let info        = WAVInfo.read(from: wavURL)
        let sampleEnd   = info?.frameCount ?? 0
        let fileSize    = info?.fileSize ?? 0
        // sliceStarts passed in directly — already read in buildChopTrack
        let displayName = pad.sampleName
        let padName     = padLabel(pad)

        tpl = replaceFirst(tpl,
            pattern: #"<UserName Value="[^"]*""#,
            with: "<UserName Value=\"\(xmlEscape(padName))\"")
        tpl = replaceFirst(tpl,
            pattern: #"<Name Value="[^"]*""#,
            with: "<Name Value=\"\(xmlEscape(displayName))\"")
        tpl = replaceFirst(tpl,
            pattern: #"<RelativePath Value="[^"]*\.(?:wav|WAV|aif|aiff|mp3)[^"]*""#,
            with: "<RelativePath Value=\"\(xmlEscape(relPath))\"")

        // Clear stale absolute Path and .adv preset refs (Koala2Live template artefacts)
        tpl = replaceFirst(tpl,
            pattern: #"<Path Value="[^"]*\.(?:wav|WAV|aif|aiff|mp3)[^"]*""#,
            with: "<Path Value=\"\"")
        tpl = tpl.replacingOccurrences(
            of: #"<RelativePath Value="[^"]*\.adv[^"]*" />"#,
            with: "<RelativePath Value=\"\" />",
            options: .regularExpression)
        tpl = tpl.replacingOccurrences(
            of: #"<Path Value="[^"]*\.adv[^"]*" />"#,
            with: "<Path Value=\"\" />",
            options: .regularExpression)

        tpl = replaceFirst(tpl,
            pattern: #"<SampleEnd Value="[^"]*""#,
            with: "<SampleEnd Value=\"\(sampleEnd)\"")
        tpl = replaceFirst(tpl,
            pattern: #"<OriginalFileSize Value="[^"]*""#,
            with: "<OriginalFileSize Value=\"\(fileSize)\"")

        // Slice mode: PlaybackMode=2 in Globals, SlicingStyle=2 (Region), SlicingRegions=N
        // The Globals PlaybackMode is the FIRST occurrence; SimplerSlicing has its own
        tpl = replaceFirst(tpl,
            pattern: #"<PlaybackMode Value="[^"]*""#,
            with: "<PlaybackMode Value=\"2\"")

        // Pitch: coarse tune (semitones) and fine tune (cents, scaled from MPC's ±90 to ALS ±50)
        let alsFineTune = Double(pad.fineTune) * (50.0 / 90.0)
        // Replace Manual Value inside TransposeKey block — use the opening tag as anchor
        let tabs10 = "\t\t\t\t\t\t\t\t\t\t"
        let keyOld  = "<TransposeKey>\n\(tabs10)<LomId Value=\"0\" />\n\(tabs10)<Manual Value=\"0\" />"
        let keyNew  = "<TransposeKey>\n\(tabs10)<LomId Value=\"0\" />\n\(tabs10)<Manual Value=\"\(pad.coarseTune)\" />"
        tpl = tpl.replacingOccurrences(of: keyOld, with: keyNew)
        let fineOld = "<TransposeFine>\n\(tabs10)<LomId Value=\"0\" />\n\(tabs10)<Manual Value=\"0\" />"
        let fineNew = "<TransposeFine>\n\(tabs10)<LomId Value=\"0\" />\n\(tabs10)<Manual Value=\"\(alsFineTune)\" />"
        tpl = tpl.replacingOccurrences(of: fineOld, with: fineNew)

        // Warp: set IsWarped=true so Ableton stretches the loop to project BPM
        if pad.warpEnable {
            tpl = tpl.replacingOccurrences(of: "<IsWarped Value=\"false\" />",
                                           with: "<IsWarped Value=\"true\" />")
        }

        // SlicingStyle and slice points:
        // - Have WAV slice positions → SlicingStyle=3 (Manual) + inject ManualSlicePoints
        // - chopMode=2 (equal regions) → SlicingStyle=2 (Region) with count
        // - chopMode=0 (manual, no positions yet) → SlicingStyle=0 (Transient, auto-detect)
        if !sliceStarts.isEmpty {
            // Manual slice mode with actual positions from WAV atem chunk.
            // sliceStarts = [Slice0.Start, Slice1.Start, ..., SliceN-1.Start]
            // SampleStart = Slice0.Start (trim pre-roll before first real chop)
            // ManualSlicePoints = inter-slice boundaries only (Slice1.Start onward)
            let sr = sampleRate > 0 ? sampleRate : 44100
            let slice0Start = sliceStarts[0]
            let cutPoints   = Array(sliceStarts.dropFirst())  // Slice1..N-1 starts

            // Set SampleStart to Slice 0's actual start position
            tpl = replaceFirst(tpl,
                pattern: #"<SampleStart Value="[^"]*""#,
                with: "<SampleStart Value=\"\(slice0Start)\"")

            tpl = replaceFirst(tpl,
                pattern: #"<SlicingStyle Value="[^"]*""#,
                with: "<SlicingStyle Value=\"3\"")
            tpl = replaceFirst(tpl,
                pattern: #"<SlicingRegions Value="[^"]*""#,
                with: "<SlicingRegions Value=\"\(sliceStarts.count)\"")

            // Inject cut points as ManualSlicePoints
            var spXml = ""
            for frame in cutPoints {
                let timeInSec = Double(frame) / Double(sr)
                let tabs = String(repeating: "\t", count: 20)
                spXml += "\(tabs)<SlicePoint TimeInSeconds=\"\(timeInSec)\" Rank=\"0\" NormalizedEnergy=\"1\" />\n"
            }
            let manualTarget = "<ManualSlicePoints />"
            let manualRepl   = "<ManualSlicePoints>\n\(spXml)\(String(repeating: "\t", count: 19))</ManualSlicePoints>"
            tpl = tpl.replacingOccurrences(of: manualTarget, with: manualRepl)
        } else if pad.chopMode == 2 {
            // Equal region mode
            tpl = replaceFirst(tpl,
                pattern: #"<SlicingStyle Value="[^"]*""#,
                with: "<SlicingStyle Value=\"2\"")
            tpl = replaceFirst(tpl,
                pattern: #"<SlicingRegions Value="[^"]*""#,
                with: "<SlicingRegions Value=\"\(pad.chopRegions)\"")
        } else {
            // Manual chops but no WAV data yet — use Transient detection
            tpl = replaceFirst(tpl,
                pattern: #"<SlicingStyle Value="[^"]*""#,
                with: "<SlicingStyle Value=\"0\"")
            tpl = replaceFirst(tpl,
                pattern: #"<SlicingRegions Value="[^"]*""#,
                with: "<SlicingRegions Value=\"\(pad.chopRegions)\"")
        }

        return tpl
    }

}
