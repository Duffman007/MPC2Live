// ALSNoteMap.swift
// Maps MPC MIDI note → Ableton ReceivingNote (internal drum rack slot number).
//
// Ableton's drum rack uses an internal numbering that does NOT match MIDI notes.
// The visible group (C1–D#2) layout in Ableton's display:
//
//   [80] [79] [78] [77]   ← top row    (pad_in_bank 12-15)
//   [84] [83] [82] [81]   ← row 3      (pad_in_bank  8-11)
//   [88] [87] [86] [85]   ← row 2      (pad_in_bank  4-7)
//   [92] [91] [90] [89]   ← bottom row (pad_in_bank  0-3)
//
// Formula (from Koala2Live, verified): base=80, rn = 80 - col + (3 - row) * 4
// where row = padInBank / 4, col = padInBank % 4
// MPC pads start bottom-left (row=0), so we invert the row vs Koala's top-left start.
//
// Both ReceivingNote in the drum rack AND MidiKey in MIDI clips must use this value.
// They are the same number — Ableton routes internally from clip note → pad slot.

enum ALSNoteMap {

    /// Convert MPC pad-in-bank position (0-15) to Ableton ReceivingNote.
    /// ALL banks always map to ReceivingNotes 77-92 (the C1-D#2 visible bank).
    /// The bankIndex offset is NOT used here — it only applies to MIDI clip notes.
    static func receivingNote(padInBank: Int, bankIndex: Int) -> Int {
        let row  = padInBank / 4
        let col  = padInBank % 4
        return 80 - col + (3 - row) * 4  // always base=80, bankIndex ignored
    }

    /// Convert MPC MIDI note directly to Ableton ReceivingNote.
    /// MPC Bank A notes 36-51 → pad_in_bank 0-15, bankIndex 0.
    static func receivingNote(forMPCNote mpcNote: Int) -> Int {
        // MPC note 36 = pad 0 = Bank A pad_in_bank 0
        // MPC note 52 = pad 16 = Bank B pad_in_bank 0 etc.
        let padIndex  = mpcNote - 36          // 0-based pad index
        let bankIndex = padIndex / 16
        let padInBank = padIndex % 16
        return receivingNote(padInBank: padInBank, bankIndex: bankIndex)
    }
}
