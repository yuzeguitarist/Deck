//! Shared vectors with `DeckTests/canonical_json_vectors.json` (keep paths in sync).

use deckclip_core::auth::canonical_json;
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
struct CanonicalCase {
    args: Value,
    canonical: String,
}

#[test]
fn canonical_json_matches_shared_fixture_file() {
    const RAW: &str =
        include_str!("../../deckclip-protocol/tests/fixtures/canonical_json_vectors.json");
    let cases: Vec<CanonicalCase> = serde_json::from_str(RAW).expect("parse fixture JSON");
    for (idx, case) in cases.into_iter().enumerate() {
        assert_eq!(
            canonical_json(&case.args),
            case.canonical,
            "fixture case {idx}"
        );
    }
}
