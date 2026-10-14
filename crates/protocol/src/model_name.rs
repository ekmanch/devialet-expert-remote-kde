//! Maps a raw mDNS hostname (e.g. `"Expert140Pro"`) to a display-ready
//! Devialet model name (e.g. `"Devialet Expert 140 Pro"`).
//!
//! A general transform, **not** a per-model lookup table, matching the
//! Kotlin app's `AmpModelNameResolver.parseModelName`: a space at every
//! letter->digit and digit->uppercase-letter boundary, then a `"Devialet "`
//! prefix. Digit->lowercase is deliberately *not* a boundary ("2go" stays
//! "2go").

/// Takes the part of `mdns_hostname` before its first `-` (Devialet's mDNS
/// hostnames are `"<Model><Digits><Suffix>-<serial>.local."`), trimmed,
/// and formats it as described in the module doc. Returns `None` if that
/// part is empty.
pub fn parse_model_name(mdns_hostname: &str) -> Option<String> {
    // First segment before any '-', or the whole string if there is none.
    let raw = mdns_hostname.split('-').next().unwrap_or("").trim();
    if raw.is_empty() {
        return None;
    }

    let chars: Vec<char> = raw.chars().collect();
    let mut spaced = String::with_capacity(raw.len() + 1);
    for (i, &c) in chars.iter().enumerate() {
        if i > 0 {
            let prev = chars[i - 1];
            let is_boundary = (prev.is_ascii_alphabetic() && c.is_ascii_digit())
                || (prev.is_ascii_digit() && c.is_ascii_uppercase());
            if is_boundary {
                spaced.push(' ');
            }
        }
        spaced.push(c);
    }

    Some(format!("Devialet {spaced}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn confirmed_real_example_expert_140_pro() {
        // The one example confirmed against real hardware
        // ("Expert140Pro-<serial>.local", via avahi-browse/avahi-resolve).
        assert_eq!(
            parse_model_name("Expert140Pro-AB12CD34.local."),
            Some("Devialet Expert 140 Pro".to_string())
        );
    }

    #[test]
    fn strips_everything_from_the_first_hyphen_onward() {
        assert_eq!(parse_model_name("Expert140Pro-1234.local."), parse_model_name("Expert140Pro-9999999.local."));
    }

    #[test]
    fn digit_to_lowercase_letter_is_not_a_boundary() {
        // Only digit->UPPERCASE is a boundary, not digit->lowercase; keep
        // this asymmetry rather than "fixing" it.
        assert_eq!(parse_model_name("2go"), Some("Devialet 2go".to_string()));
    }

    #[test]
    fn multiple_letter_digit_and_digit_uppercase_boundaries_all_split() {
        // Synthetic name: several boundaries of each kind in one string
        // (the confirmed real example has only one of each).
        assert_eq!(
            parse_model_name("Phantom2Reactor900-serial.local."),
            Some("Devialet Phantom 2 Reactor 900".to_string())
        );
    }

    #[test]
    fn no_digits_at_all_still_gets_the_devialet_prefix() {
        assert_eq!(parse_model_name("Konnect-serial.local."), Some("Devialet Konnect".to_string()));
    }

    #[test]
    fn leading_digits_do_not_get_a_leading_space() {
        assert_eq!(parse_model_name("900Something-serial.local."), Some("Devialet 900 Something".to_string()));
    }

    #[test]
    fn empty_before_the_first_hyphen_returns_none() {
        assert_eq!(parse_model_name("-serial.local."), None);
    }

    #[test]
    fn hostname_with_no_hyphen_is_used_in_full_matching_kotlins_substring_before_semantics() {
        // Not expected on real Devialet hostnames, but matches the Kotlin
        // app's substringBefore('-'): no '-' uses the whole string.
        assert_eq!(parse_model_name("NoHyphenHost"), Some("Devialet NoHyphenHost".to_string()));
    }

    #[test]
    fn blank_hostname_returns_none() {
        assert_eq!(parse_model_name(""), None);
        assert_eq!(parse_model_name("   "), None);
    }
}
