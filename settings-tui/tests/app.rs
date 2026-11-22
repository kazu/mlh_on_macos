use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use mlh_settings_tui::{app::App, model::Snapshot};

fn sample() -> Snapshot {
    serde_json::from_str(r#"{
        "schema":1,
        "sections":[{"id":"openai","label":"OpenAI"}],
        "fields":[
            {"id":"openai.key","section":"openai","label":"API キー","kind":"secret","value":null,"origin":"keychain","options":[],"editable":true,"description":"","has_value":true},
            {"id":"openai.model","section":"openai","label":"モデル","kind":"text","value":"old","origin":"default","options":[],"editable":true,"description":"","has_value":false}
        ],
        "actions":[{"id":"execute.entry.add","section":"openai","label":"追加","inputs":[{"id":"key","label":"番号","kind":"text"}]}]
    }"#).unwrap()
}

#[test]
fn action_collects_inputs_for_apply() {
    let mut app = App::new(sample());
    app.handle_key(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Char('2'), KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    let request = app.request();
    assert_eq!(request.actions.len(), 1);
    assert_eq!(request.actions[0].id, "execute.entry.add");
    assert_eq!(
        request.actions[0].values.get("key").map(String::as_str),
        Some("2")
    );
    let encoded = serde_json::to_value(&request).unwrap();
    assert_eq!(encoded["actions"][0]["values"]["key"], "2");
}

#[test]
fn secret_is_never_displayed_but_can_be_replaced_and_reset() {
    let mut app = App::new(sample());
    assert_eq!(
        app.displayed_value(app.selected_field().unwrap()),
        "設定済み"
    );
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    assert_eq!(
        app.displayed_value(app.selected_field().unwrap()),
        "設定済み"
    );
    assert_eq!(app.request().changes[0].value.as_deref(), Some("n"));
    app.handle_key(KeyEvent::new(KeyCode::Char('r'), KeyModifiers::NONE));
    assert_eq!(app.displayed_value(app.selected_field().unwrap()), "未設定");
    assert_eq!(app.request().changes[0].op, "reset");
}

#[test]
fn escape_discards_edit_without_staging_change() {
    let mut app = App::new(sample());
    app.handle_key(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
    assert!(app.request().changes.is_empty());
    assert_eq!(app.displayed_value(app.selected_field().unwrap()), "old");
}

#[test]
fn unavailable_secret_store_cannot_stage_key_changes() {
    let mut snapshot = sample();
    let secret = &mut snapshot.fields[0];
    secret.editable = false;
    secret.has_value = false;
    secret.description = "Secret Service を利用できません".into();
    let mut app = App::new(snapshot);
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Char('r'), KeyModifiers::NONE));
    assert!(app.editing.is_none());
    assert!(app.request().changes.is_empty());
    assert_eq!(app.displayed_value(app.selected_field().unwrap()), "未設定");

    let mut snapshot = sample();
    snapshot.fields[0].editable = false;
    snapshot.fields[0].origin = "environment".into();
    let mut app = App::new(snapshot);
    app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    app.handle_key(KeyEvent::new(KeyCode::Char('r'), KeyModifiers::NONE));
    assert!(app.request().changes.is_empty());
    assert_eq!(
        app.displayed_value(app.selected_field().unwrap()),
        "設定済み"
    );
}
