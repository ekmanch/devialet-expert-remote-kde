use crate::crc16::crc16_ccitt_false;
use crate::dbconvert::db_convert;

/// Fixed size of every command packet (header, counters, CRC, padding),
/// regardless of command type. See docs/protocol.md.
pub const PACKET_LEN: usize = 142;

/// Forced volume sent after every source switch, overriding the amp's
/// inconsistent per-input volume memory (docs/known-gotchas.md #5). A
/// product decision, not part of the wire protocol: callers send it as a
/// second command after `source_packet`.
pub const SOURCE_SWITCH_VOLUME_DB: f64 = -40.0;

/// Returns the counter to use after `current`, wrapping `0xFFFF -> 0`.
/// Use `counter` in the packet being built now, then set
/// `counter = next_counter(counter)` for the following call.
pub fn next_counter(current: u16) -> u16 {
    if current == 0xFFFF {
        0
    } else {
        current + 1
    }
}

/// Builds one 142-byte command packet. Pure: no I/O, no implicit counter
/// state; callers supply the packet/command counter values to embed.
pub fn build_command_packet(
    byte6: u8,
    byte7: u8,
    byte8: u8,
    byte9: u8,
    packet_counter: u16,
    command_counter: u16,
) -> [u8; PACKET_LEN] {
    let mut data = [0u8; PACKET_LEN];
    data[0] = 0x44;
    data[1] = 0x72;
    data[2] = (packet_counter >> 8) as u8;
    data[3] = (packet_counter & 0xFF) as u8;
    data[4] = (command_counter >> 8) as u8;
    data[5] = (command_counter & 0xFF) as u8;
    data[6] = byte6;
    data[7] = byte7;
    data[8] = byte8;
    data[9] = byte9;
    // Offsets 10-11 stay zero.

    let first_12: [u8; 12] = data[0..12].try_into().expect("slice is exactly 12 bytes");
    let crc = crc16_ccitt_false(&first_12);
    data[12] = (crc >> 8) as u8;
    data[13] = (crc & 0xFF) as u8;
    // Offsets 14-141 stay zero (padding).

    data
}

/// Power on/off.
pub fn power_packet(on: bool, packet_counter: u16, command_counter: u16) -> [u8; PACKET_LEN] {
    build_command_packet(
        if on { 0x01 } else { 0x00 },
        0x01,
        0x00,
        0x00,
        packet_counter,
        command_counter,
    )
}

/// Mute on/off.
pub fn mute_packet(muted: bool, packet_counter: u16, command_counter: u16) -> [u8; PACKET_LEN] {
    build_command_packet(
        if muted { 0x01 } else { 0x00 },
        0x07,
        0x00,
        0x00,
        packet_counter,
        command_counter,
    )
}

/// Set volume. Clamps to `hard_limit_db` here when `Some`, so no caller
/// can bypass the hard limit (docs/DESIGN.md §3), then encodes the clamped
/// value with `db_convert` and sets the sign bit (`0x8000`) when it is
/// negative. `None` applies no ceiling.
pub fn volume_packet(
    db_in: f64,
    hard_limit_db: Option<f64>,
    packet_counter: u16,
    command_counter: u16,
) -> [u8; PACKET_LEN] {
    let db = match hard_limit_db {
        Some(limit) => db_in.min(limit),
        None => db_in,
    };
    let mut vol = db_convert(db);
    if db < 0.0 {
        vol |= 0x8000;
    }
    let hi = (vol >> 8) as u8;
    let lo = (vol & 0xFF) as u8;
    build_command_packet(0x00, 0x04, hi, lo, packet_counter, command_counter)
}

/// Status-broadcast source index (0-14) -> select-source command value.
/// Non-linear, empirically reverse-engineered - **do not** "clean up" or
/// re-derive this from a formula (docs/known-gotchas.md #3). Unmapped
/// indices fall back to the raw index value; per docs/protocol.md that
/// fallback is unverified.
///
/// Keyed by numeric status index, a fixed hardware slot that holds across
/// amps (docs/devialet_source_mapping.md). What is connected and named at
/// a slot varies per unit, so never hardcode a source name from its index;
/// read it live from the status broadcast (`Status.sources`).
fn source_command_value(status_index: u8) -> i32 {
    match status_index {
        0 => -1,  // hardware slot 0
        2 => 0,   // hardware slot 2
        3 => 3,   // hardware slot 3
        4 => 4,   // hardware slot 4
        5 => 5,   // hardware slot 5
        14 => 14, // hardware slot 14
        other => other as i32,
    }
}

/// Select source, by status-broadcast index (0-14, from the amp's own
/// status packet - *not* a command value, see `source_command_value`).
///
/// Status index 1 uses hardcoded bytes that don't follow the bit-packing
/// formula (from a packet capture, docs/protocol.md). The slot is fixed;
/// its name is per-unit (one amp calls it "Phono", another "UPnP", see
/// docs/devialet_source_mapping.md). Every other index goes through
/// `source_command_value` and the bit-packing below.
///
/// Builds only the source packet; the caller must also send
/// `SOURCE_SWITCH_VOLUME_DB` as a second command.
pub fn source_packet(status_index: u8, packet_counter: u16, command_counter: u16) -> [u8; PACKET_LEN] {
    if status_index == 1 {
        return build_command_packet(0x00, 0x05, 0x3F, 0x80, packet_counter, command_counter);
    }

    let cmd_value = source_command_value(status_index);
    // i32 arithmetic (signed, arithmetic shr) as in the reference
    // implementation: cmd_value can be -1 (status index 0).
    let out_val: i32 = 0x4000 | (cmd_value << 5);
    let hi = ((out_val >> 8) & 0xFF) as u8;
    let lo = if cmd_value > 7 {
        ((out_val & 0xFF) >> 1) as u8
    } else {
        (out_val & 0xFF) as u8
    };
    build_command_packet(0x00, 0x05, hi, lo, packet_counter, command_counter)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hdr(counter_bytes: [u8; 4], byte6: u8, byte7: u8, byte8: u8, byte9: u8, crc: [u8; 2]) -> Vec<u8> {
        let mut v = vec![0x44, 0x72];
        v.extend_from_slice(&counter_bytes);
        v.extend_from_slice(&[byte6, byte7, byte8, byte9, 0x00, 0x00]);
        v.extend_from_slice(&crc);
        v
    }

    // Expected bytes (payload + CRC) were computed with an independent
    // re-implementation of the Kotlin app's DevialetController.kt. Source
    // indices 9 and 14 are also cross-checked against the real-device wire
    // bytes in docs/protocol.md ("Source selection encoding").

    #[test]
    fn packet_is_142_bytes_and_zero_padded() {
        let p = power_packet(true, 0, 0);
        assert_eq!(p.len(), PACKET_LEN);
        assert!(p[14..].iter().all(|&b| b == 0));
    }

    #[test]
    fn power_on_off() {
        let on = power_packet(true, 0, 0);
        assert_eq!(&on[..14], hdr([0, 0, 0, 0], 0x01, 0x01, 0x00, 0x00, [0xA0, 0xBD]).as_slice());

        let off = power_packet(false, 0, 0);
        assert_eq!(&off[..14], hdr([0, 0, 0, 0], 0x00, 0x01, 0x00, 0x00, [0xE5, 0x1D]).as_slice());
    }

    #[test]
    fn mute_on_off() {
        let on = mute_packet(true, 0, 0);
        assert_eq!(&on[..14], hdr([0, 0, 0, 0], 0x01, 0x07, 0x00, 0x00, [0x6D, 0x38]).as_slice());

        let off = mute_packet(false, 0, 0);
        assert_eq!(&off[..14], hdr([0, 0, 0, 0], 0x00, 0x07, 0x00, 0x00, [0x28, 0x98]).as_slice());
    }

    #[test]
    fn volume_at_hard_limit_is_not_further_clamped() {
        // Exact boundary value: db_in == hard_limit_db must pass through
        // as-is (min() is inclusive), not get pushed any quieter.
        let p = volume_packet(-15.0, Some(-15.0), 0, 0);
        assert_eq!(&p[..14], hdr([0, 0, 0, 0], 0x00, 0x04, 0xC1, 0x70, [0xDB, 0x52]).as_slice());
    }

    #[test]
    fn volume_above_hard_limit_is_clamped_down_to_it() {
        // -10dB is "louder" than a -15dB hard limit and must be clamped to
        // produce byte-identical output to requesting -15dB directly.
        let requested_loud = volume_packet(-10.0, Some(-15.0), 0, 0);
        let at_limit = volume_packet(-15.0, Some(-15.0), 0, 0);
        assert_eq!(requested_loud, at_limit);
    }

    #[test]
    fn volume_below_hard_limit_is_not_clamped() {
        // -40dB (the forced post-source-switch volume) is quieter than a
        // -15dB hard limit and must pass through unclamped.
        let p = volume_packet(SOURCE_SWITCH_VOLUME_DB, Some(-15.0), 0, 0);
        assert_eq!(&p[..14], hdr([0, 0, 0, 0], 0x00, 0x04, 0xC2, 0x20, [0x1E, 0x40]).as_slice());
    }

    #[test]
    fn volume_zero_db_is_clamped_to_configured_hard_limit() {
        // Regression guard for known-gotchas.md #6: 0dB must never reach
        // the wire unclamped when a hard limit is configured - it has to
        // come out byte-identical to requesting the limit directly.
        let zero = volume_packet(0.0, Some(-15.0), 0, 0);
        let at_limit = volume_packet(-15.0, Some(-15.0), 0, 0);
        assert_eq!(zero, at_limit);
    }

    #[test]
    fn volume_with_a_different_configured_hard_limit_clamps_to_that_value() {
        // The limit is a runtime value: any configured limit (here -10dB)
        // is honored, not just -15.0.
        let p = volume_packet(-5.0, Some(-10.0), 0, 0);
        let at_limit = volume_packet(-10.0, Some(-10.0), 0, 0);
        assert_eq!(p, at_limit);
    }

    #[test]
    fn volume_with_no_hard_limit_configured_is_never_clamped() {
        // hard_limit_db: None is unbounded. 0dB (the value known-gotchas.md
        // #6 blocks when a limit is set) proves None applies no hidden
        // fallback ceiling.
        let unbounded = volume_packet(0.0, None, 0, 0);
        let db = db_convert(0.0);
        let hi = (db >> 8) as u8;
        let lo = (db & 0xFF) as u8;
        assert_eq!((unbounded[8], unbounded[9]), (hi, lo));
    }

    #[test]
    fn source_index_1_hardcoded_bytes() {
        // Status index 1 - hardcoded 0x3F 0x80, not the general formula.
        // The wire bytes are fixed, the slot's name is per-unit
        // (docs/devialet_source_mapping.md).
        let p = source_packet(1, 0, 0);
        assert_eq!(&p[..14], hdr([0, 0, 0, 0], 0x00, 0x05, 0x3F, 0x80, [0xAF, 0x46]).as_slice());
    }

    /// Regression test for known-gotchas.md #3 (raw status index passed
    /// through as the command value). Asserts the full mapped table's
    /// non-linear command bytes: an identity mapping would fail every case
    /// except index 2.
    ///
    /// The inline names are known-gotchas.md's labels from one reference
    /// amp, kept for readability; names are per-unit
    /// (docs/devialet_source_mapping.md). Only index and bytes are asserted.
    #[test]
    fn source_index_to_command_value_regression_bug_3() {
        let cases: &[(u8, u8, u8)] = &[
            // (status_index, expected byte8, expected byte9)
            (0, 0xFF, 0xE0),  // Optical 1  -> cmd_value -1 (NOT index 0's own bytes)
            (2, 0x40, 0x00),  // UPnP       -> cmd_value 0
            (3, 0x40, 0x60),  // Roon Ready -> cmd_value 3
            (4, 0x40, 0x80),  // AirPlay    -> cmd_value 4
            (5, 0x40, 0xA0),  // Spotify    -> cmd_value 5
            (14, 0x41, 0x60), // Air (BT)   -> cmd_value 14
        ];
        for &(status_index, expected_hi, expected_lo) in cases {
            let p = source_packet(status_index, 0, 0);
            assert_eq!(
                (p[8], p[9]),
                (expected_hi, expected_lo),
                "status_index {status_index} produced wrong command bytes"
            );
        }
    }

    /// The only two wire-byte values confirmed against a physical amp in
    /// docs/protocol.md, not just derived from the formula: status index 9
    /// (unmapped, raw-index fallback) -> 0x41 0x10; status index 14
    /// (cmd_value 14) -> 0x41 0x60.
    #[test]
    fn source_bytes_match_real_device_confirmed_values() {
        let index_9 = source_packet(9, 0, 0);
        assert_eq!((index_9[8], index_9[9]), (0x41, 0x10));

        let index_14 = source_packet(14, 0, 0);
        assert_eq!((index_14[8], index_14[9]), (0x41, 0x60));
    }

    #[test]
    fn unmapped_source_index_falls_back_to_raw_index() {
        // Index 9 isn't mapped in source_command_value - falls back to
        // cmd_value 9 (the ">7" bit-packing branch). What it selects on the
        // amp is unverified, but the wire bytes are deterministic and this
        // regresses if the fallback logic changes.
        let p = source_packet(9, 0, 0);
        assert_eq!((p[8], p[9]), (0x41, 0x10));
    }

    #[test]
    fn counters_are_embedded_big_endian_and_independent_of_payload() {
        let p = power_packet(true, 0x0102, 0x0304);
        assert_eq!(&p[2..6], &[0x01, 0x02, 0x03, 0x04]);
    }

    #[test]
    fn counter_wraps_at_0xffff() {
        assert_eq!(next_counter(0xFFFE), 0xFFFF);
        assert_eq!(next_counter(0xFFFF), 0x0000);
        assert_eq!(next_counter(0x0000), 0x0001);
    }

    #[test]
    fn same_logical_command_with_different_counters_has_different_crc() {
        // Each command is sent twice; the two copies differ in counters
        // (and therefore CRC), not in command bytes.
        let first = power_packet(true, 0, 0);
        let second = power_packet(true, 1, 1);
        assert_ne!(first, second);
        assert_eq!(&first[6..10], &second[6..10]); // same command bytes
    }
}
