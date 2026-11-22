use std::{
    fs,
    os::unix::fs::PermissionsExt,
    time::{SystemTime, UNIX_EPOCH},
};

use mlh_settings_tui::{app::App, backend, model::Change};

#[test]
fn failed_secret_write_reloads_partially_saved_settings_without_replaying_changes() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir =
        std::env::temp_dir().join(format!("mlh-settings-tui-{}-{suffix}", std::process::id()));
    fs::create_dir(&dir).unwrap();
    let backend_path = dir.join("mlh-settings-backend");
    fs::copy(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/partial-save.sh"),
        &backend_path,
    )
    .unwrap();
    fs::set_permissions(&backend_path, fs::Permissions::from_mode(0o700)).unwrap();

    let mut app = App::new(backend::load_snapshot(&backend_path).unwrap());
    app.changes.insert(
        "openai.model".into(),
        Change {
            id: "openai.model".into(),
            op: "set".into(),
            value: Some("new".into()),
        },
    );
    app.changes.insert(
        "openai.apiKey".into(),
        Change {
            id: "openai.apiKey".into(),
            op: "set".into(),
            value: Some("private".into()),
        },
    );
    backend::save(&backend_path, &mut app);

    let request: serde_json::Value =
        serde_json::from_slice(&fs::read(backend_path.with_extension("state.request")).unwrap())
            .unwrap();
    assert_eq!(request["changes"].as_array().unwrap().len(), 2);
    assert_eq!(app.snapshot.fields[0].value.as_deref(), Some("new"));
    assert!(!app.snapshot.fields[1].has_value);
    assert!(app.changes.is_empty());
    assert!(!app.save_disabled);
    assert!(app.message.contains("Secret Service write failed"));
    assert!(app.message.contains("未保存の入力は消えました"));
    assert!(!app.message.contains("private"));
    fs::remove_dir_all(dir).unwrap();
}
