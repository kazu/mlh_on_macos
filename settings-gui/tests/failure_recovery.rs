use gtk::prelude::*;
use mlh_settings_gtk::build_ui;
use std::fs;
use std::path::Path;

fn row_with_label(content: &gtk::Box, expected: &str) -> Option<gtk::Box> {
    let mut child = content.first_child();
    while let Some(widget) = child {
        if let Ok(row) = widget.clone().downcast::<gtk::Box>() {
            if let Some(first) = row.first_child() {
                if let Ok(label) = first.downcast::<gtk::Label>() {
                    if label.text().starts_with(expected) {
                        return Some(row);
                    }
                }
            }
        }
        child = widget.next_sibling();
    }
    None
}

#[test]
#[ignore = "requires MLH_SETTINGS_BACKEND fixture, MLH_TEST_STATE_DIR, and a display"]
fn partial_apply_recovers_or_disables_editing() {
    let state = Path::new(&std::env::var("MLH_TEST_STATE_DIR").unwrap()).to_path_buf();
    fs::create_dir_all(&state).unwrap();
    for marker in ["applied", "fail_snapshot", "allow_snapshot"] {
        let _ = fs::remove_file(state.join(marker));
    }
    gtk::init().unwrap();
    let app = gtk::Application::builder()
        .application_id("com.github.kazu.mlh.settings.failure-test")
        .build();
    let ui = build_ui(&app);

    let action = row_with_label(&ui.content, "番号別またはアプリ別の設定を追加").unwrap();
    let key = action.first_child().unwrap().next_sibling().unwrap()
        .downcast::<gtk::Entry>().unwrap();
    key.set_text("2");
    action.last_child().unwrap().downcast::<gtk::Button>().unwrap().emit_clicked();
    let action_reloaded = row_with_label(&ui.content, "番号 2 モデル").is_some()
        && ui.status.text().contains("未保存の入力");

    fs::remove_file(state.join("applied")).unwrap();
    fs::write(state.join("fail_snapshot"), "").unwrap();
    ui.reload.emit_clicked();
    let model = row_with_label(&ui.content, "モデル  ·").unwrap();
    let controls = model.last_child().unwrap().downcast::<gtk::Box>().unwrap();
    controls.first_child().unwrap().downcast::<gtk::Entry>().unwrap().set_text("retry me");
    ui.save.emit_clicked();
    let editing_disabled = !ui.save.is_sensitive() && !ui.content.is_sensitive();

    assert_eq!((action_reloaded, editing_disabled), (true, true));
    fs::write(state.join("allow_snapshot"), "").unwrap();
    ui.reload.emit_clicked();
    assert!(ui.save.is_sensitive() && ui.content.is_sensitive());
    assert!(ui.status.text().contains("再読み込み"));
}
