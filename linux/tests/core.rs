use mlh_ibus::core;

#[test]
fn invokes_existing_mlh_conversion() {
    let mut engine = core::Engine::new();
    assert_eq!(engine.run("hello").unwrap().kind, 0);
    let result = engine.run("nihongof/").unwrap();
    assert_eq!(result.text.as_deref(), Some("にほんご"));
    assert_eq!(result.henkan_begin, 4);
    assert!(!result.needs_kanji);
}

#[test]
fn converts_kana_with_the_existing_dictionary() {
    let dictionary = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../.build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"
    );
    let mut conversion = core::Conversion::new("にほんご", dictionary).unwrap();
    assert!(!conversion.text().is_empty());
    conversion.step(0);
    assert!(!conversion.text().is_empty());
}
