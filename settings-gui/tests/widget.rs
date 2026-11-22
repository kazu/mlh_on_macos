use gtk::prelude::*;
use mlh_settings_gtk::build_ui;
use std::process::Command;

fn row_with_label(content: &gtk::Box, expected: &str) -> gtk::Box {
    let mut child = content.first_child();
    while let Some(widget) = child {
        if let Ok(row) = widget.clone().downcast::<gtk::Box>() {
            if let Some(first) = row.first_child() {
                if let Ok(label) = first.downcast::<gtk::Label>() {
                    if label.text().starts_with(expected) {
                        return row;
                    }
                }
            }
        }
        child = widget.next_sibling();
    }
    panic!("row not found: {expected}");
}

fn backend_snapshot() -> serde_json::Value {
    let output = Command::new(std::env::var("MLH_SETTINGS_BACKEND").unwrap())
        .arg("snapshot")
        .output()
        .unwrap();
    assert!(output.status.success());
    serde_json::from_slice(&output.stdout).unwrap()
}

#[test]
#[ignore = "requires an isolated XDG_CONFIG_HOME, MLH_SETTINGS_BACKEND, and a display"]
fn edits_field_and_runs_action_through_widgets() {
    gtk::init().unwrap();
    let app = gtk::Application::builder()
        .application_id("com.github.kazu.mlh.settings.widget-test")
        .build();
    let ui = build_ui(&app);

    let model_row = row_with_label(&ui.content, "モデル  ·");
    let controls = model_row.last_child().unwrap().downcast::<gtk::Box>().unwrap();
    let entry = controls.first_child().unwrap().downcast::<gtk::Entry>().unwrap();
    let model = format!("gtk-test-model-{}", std::process::id());
    entry.set_text(&model);
    ui.save.emit_clicked();
    assert_eq!(ui.status.text(), "設定を保存しました");
    let saved = backend_snapshot();
    assert_eq!(saved["fields"].as_array().unwrap().iter()
        .find(|field| field["id"] == "openai.model").unwrap()["value"].as_str(), Some(model.as_str()));

    let action_row = row_with_label(&ui.content, "番号別またはアプリ別の設定を追加");
    let key = action_row.first_child().unwrap().next_sibling().unwrap()
        .downcast::<gtk::Entry>().unwrap();
    key.set_text("2");
    action_row.last_child().unwrap().downcast::<gtk::Button>().unwrap().emit_clicked();
    assert_eq!(ui.status.text(), "設定を更新しました");
    assert!(backend_snapshot()["fields"].as_array().unwrap().iter()
        .any(|field| field["id"] == "execute.entry.g.2.model"));
}
