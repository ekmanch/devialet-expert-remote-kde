/// Devialet's recursive dB -> 16-bit volume-word encoding (docs/protocol.md,
/// "Volume encoding"):
///
/// ```text
/// dbConvert(0.0)  == 0x0000
/// dbConvert(0.5)  == 0x3F00
/// dbConvert(|db|) == (256 >> ceil(1 + ln(|db|)/ln(2))) + dbConvert(|db| - 0.5)
/// ```
///
/// Sign is *not* applied here (the input is `abs()`ed); callers OR in the
/// `0x8000` sign bit, see `command::volume_packet`.
///
/// The literal formula recurses on exact float equality to `0.0`/`0.5` and
/// never terminates for an input that is not a multiple of 0.5 (possible
/// from the CLI's `--volume`). So the input is rounded to the nearest 0.5dB
/// step first and the recursion runs on an integer step count: it always
/// terminates and is byte-identical to the formula at every exact step.
pub fn db_convert(db_value: f64) -> u16 {
    let steps = (db_value.abs() / 0.5).round().max(0.0) as u32;
    db_convert_steps(steps)
}

fn db_convert_steps(steps: u32) -> u16 {
    match steps {
        0 => 0x0000,
        1 => 0x3F00,
        n => {
            let db_abs = n as f64 * 0.5;
            // Literally `ceil(1 + ln(db_abs) / ln(2.0))`. `ln(2.0)` is
            // computed at runtime, not a constant, to match the reference
            // implementation's floating point as closely as possible.
            let shift = (1.0 + db_abs.ln() / 2.0_f64.ln()).ceil();
            let term: u16 = if (0.0..32.0).contains(&shift) {
                (256u32 >> (shift as u32)) as u16
            } else {
                // Only reachable at extreme |db| far beyond any realistic
                // amp range - fail safe to 0 rather than a shift panic.
                0
            };
            term.wrapping_add(db_convert_steps(n - 1))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Expected values computed with an independent implementation of the
    // literal formula (float recursion, no rounding) at exact 0.5dB steps:
    // the step-based version must be byte-identical there.
    #[test]
    fn matches_reference_at_exact_half_db_steps() {
        assert_eq!(db_convert(0.0), 0x0000);
        assert_eq!(db_convert(0.5), 0x3F00);
        assert_eq!(db_convert(1.0), 0x3F80);
        assert_eq!(db_convert(1.5), 0x3FC0);
        assert_eq!(db_convert(2.0), 0x4000);
        assert_eq!(db_convert(4.0), 0x4080);
        assert_eq!(db_convert(8.0), 0x4100);
        assert_eq!(db_convert(15.0), 0x4170);
        assert_eq!(db_convert(40.0), 0x4220);
    }

    #[test]
    fn negative_input_uses_absolute_value() {
        // dbConvert itself never applies the sign bit - abs() only.
        assert_eq!(db_convert(-15.0), db_convert(15.0));
    }

    #[test]
    fn non_half_step_input_rounds_instead_of_hanging() {
        // -15.3 isn't an exact 0.5dB step; the literal recursion would
        // never terminate. Must round to the nearest step (15.5).
        assert_eq!(db_convert(-15.3), db_convert(15.5));
    }
}
