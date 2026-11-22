use gtk::prelude::*;
use serde::{Deserialize, Serialize};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::io::Write;
use std::process::{Command, Stdio};
use std::rc::Rc;

#[derive(Clone, Deserialize)]
struct Snapshot {
    schema: u32,
    sections: Vec<Section>,
    fields: Vec<Field>,
    actions: Vec<Action>,
}

#[derive(Clone, Deserialize)]
struct Section {
    id: String,
    label: String,
}

#[derive(Clone, Deserialize)]
struct Field {
    id: String,
    section: String,
    label: String,
    kind: String,
    value: Option<String>,
    origin: String,
    options: Vec<OptionValue>,
    editable: bool,
    description: String,
    has_value: bool,
}

#[derive(Clone, Deserialize)]
struct OptionValue {
    value: String,
    label: String,
}

#[derive(Clone, Deserialize)]
struct Action {
    id: String,
    section: String,
    label: String,
    inputs: Vec<ActionInput>,
}

#[derive(Clone, Deserialize)]
struct ActionInput {
    id: String,
    label: String,
    kind: String,
}

#[derive(Serialize)]
struct ApplyRequest {
    schema: u32,
    changes: Vec<Change>,
    actions: Vec<ActionRequest>,
}

#[derive(Serialize)]
struct Change {
    id: String,
    op: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<String>,
}

#[derive(Serialize)]
struct ActionRequest {
    id: String,
    values: HashMap<String, String>,
}

struct Editor {
    id: String,
    original: Option<String>,
    current: Box<dyn Fn() -> String>,
    reset: Rc<Cell<bool>>,
}

fn collect_changes(editors: &[Editor]) -> Vec<Change> {
    editors
        .iter()
        .filter_map(|editor| {
            if editor.reset.get() {
                return Some(Change {
                    id: editor.id.clone(),
                    op: "reset",
                    value: None,
                });
            }
            let value = (editor.current)();
            if editor.original.as_deref() == Some(value.as_str())
                || (editor.original.is_none() && value.is_empty())
            {
                None
            } else {
                Some(Change {
                    id: editor.id.clone(),
                    op: "set",
                    value: Some(value),
                })
            }
        })
        .collect()
}

fn backend_path() -> std::path::PathBuf {
    if let Some(path) = std::env::var_os("MLH_SETTINGS_BACKEND") {
        return path.into();
    }
    std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.join("mlh-settings-backend")))
        .unwrap_or_else(|| "mlh-settings-backend".into())
}

fn snapshot() -> Result<Snapshot, String> {
    let output = Command::new(backend_path())
        .arg("snapshot")
        .output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    let snapshot: Snapshot =
        serde_json::from_slice(&output.stdout).map_err(|error| error.to_string())?;
    if snapshot.schema != 1 {
        return Err(format!("Unsupported settings schema: {}", snapshot.schema));
    }
    Ok(snapshot)
}

fn apply(request: &ApplyRequest) -> Result<(), String> {
    let mut process = Command::new(backend_path())
        .arg("apply")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let data = serde_json::to_vec(request).map_err(|error| error.to_string())?;
    process
        .stdin
        .take()
        .ok_or("backend stdin is unavailable")?
        .write_all(&data)
        .map_err(|error| error.to_string())?;
    let output = process
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    Ok(())
}

fn label(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(0.0);
    label.set_wrap(true);
    label
}

fn render(
    content: &gtk::Box,
    status: &gtk::Label,
    editors: &Rc<RefCell<Vec<Editor>>>,
    save: &gtk::Button,
) -> Result<(), String> {
    let state = snapshot()?;
    while let Some(child) = content.first_child() {
        content.remove(&child);
    }
    editors.borrow_mut().clear();
    for section in state.sections {
        let section_fields: Vec<_> = state
            .fields
            .iter()
            .filter(|field| field.section == section.id)
            .cloned()
            .collect();
        let section_actions: Vec<_> = state
            .actions
            .iter()
            .filter(|action| action.section == section.id)
            .cloned()
            .collect();
        if section_fields.is_empty() && section_actions.is_empty() {
            continue;
        }
        let heading = label(&section.label);
        heading.add_css_class("title-3");
        heading.set_margin_top(18);
        content.append(&heading);
        for field in section_fields {
            render_field(content, editors, field);
        }
        for action in section_actions {
            render_action(content, status, editors, save, action);
        }
    }
    status.set_text("");
    Ok(())
}

fn render_field(content: &gtk::Box, editors: &Rc<RefCell<Vec<Editor>>>, field: Field) {
    let row = gtk::Box::new(gtk::Orientation::Vertical, 5);
    row.set_margin_top(10);
    let title = label(&format!("{}  ·  {}", field.label, field.origin));
    row.append(&title);
    if !field.description.is_empty() {
        let description = label(&field.description);
        description.add_css_class("dim-label");
        row.append(&description);
    }
    let controls = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let original = field.value.clone();
    let reset = Rc::new(Cell::new(false));
    let current: Box<dyn Fn() -> String> = match field.kind.as_str() {
        "multiline" | "list" => {
            let view = gtk::TextView::new();
            view.set_wrap_mode(gtk::WrapMode::WordChar);
            view.set_editable(field.editable);
            view.buffer().set_text(field.value.as_deref().unwrap_or(""));
            let scroll = gtk::ScrolledWindow::new();
            scroll.set_min_content_height(if field.kind == "list" { 100 } else { 150 });
            scroll.set_hexpand(true);
            scroll.set_child(Some(&view));
            controls.append(&scroll);
            Box::new(move || {
                let buffer = view.buffer();
                buffer
                    .text(&buffer.start_iter(), &buffer.end_iter(), false)
                    .to_string()
            })
        }
        "select" => {
            let mut choices = field.options.clone();
            if field.value.is_none() {
                choices.insert(
                    0,
                    OptionValue {
                        value: String::new(),
                        label: "未設定".into(),
                    },
                );
            }
            if let Some(value) = &field.value {
                if !choices.iter().any(|choice| &choice.value == value) {
                    choices.insert(
                        0,
                        OptionValue {
                            value: value.clone(),
                            label: value.clone(),
                        },
                    );
                }
            }
            let labels: Vec<&str> = choices.iter().map(|choice| choice.label.as_str()).collect();
            let dropdown = gtk::DropDown::from_strings(&labels);
            let selected = choices
                .iter()
                .position(|choice| Some(&choice.value) == field.value.as_ref())
                .unwrap_or(0);
            dropdown.set_selected(selected as u32);
            dropdown.set_sensitive(field.editable);
            controls.append(&dropdown);
            Box::new(move || {
                choices
                    .get(dropdown.selected() as usize)
                    .map(|choice| choice.value.clone())
                    .unwrap_or_default()
            })
        }
        _ => {
            let entry = gtk::Entry::new();
            entry.set_text(if field.kind == "secret" {
                ""
            } else {
                field.value.as_deref().unwrap_or("")
            });
            entry.set_hexpand(true);
            entry.set_editable(field.editable);
            if field.kind == "secret" {
                entry.set_visibility(false);
                if field.has_value {
                    entry.set_placeholder_text(Some("保存済み（変更する場合のみ入力）"));
                }
            }
            controls.append(&entry);
            Box::new(move || entry.text().to_string())
        }
    };
    if field.editable {
        let button = gtk::Button::with_label("初期値に戻す");
        let flag = reset.clone();
        button.connect_clicked(move |_| flag.set(true));
        controls.append(&button);
        editors.borrow_mut().push(Editor {
            id: field.id,
            original,
            current,
            reset,
        });
    }
    row.append(&controls);
    content.append(&row);
}

fn render_action(
    content: &gtk::Box,
    status: &gtk::Label,
    editors: &Rc<RefCell<Vec<Editor>>>,
    save: &gtk::Button,
    action: Action,
) {
    let row = gtk::Box::new(gtk::Orientation::Vertical, 5);
    row.set_margin_top(14);
    row.append(&label(&action.label));
    let mut inputs = Vec::new();
    for input in action.inputs {
        let entry = gtk::Entry::new();
        entry.set_placeholder_text(Some(&input.label));
        if input.kind == "secret" {
            entry.set_visibility(false);
        }
        row.append(&entry);
        inputs.push((input.id, entry));
    }
    let button = gtk::Button::with_label("実行");
    let action_id = action.id;
    let content_copy = (*content).clone();
    let status_copy = (*status).clone();
    let editors_copy = editors.clone();
    let save_copy = (*save).clone();
    button.connect_clicked(move |_| {
        let values = inputs
            .iter()
            .map(|(id, entry)| (id.clone(), entry.text().to_string()))
            .collect();
        let request = ApplyRequest {
            schema: 1,
            changes: collect_changes(&editors_copy.borrow()),
            actions: vec![ActionRequest {
                id: action_id.clone(),
                values,
            }],
        };
        apply_and_refresh(&request, &content_copy, &status_copy, &editors_copy,
                          &save_copy, "設定を更新しました");
    });
    row.append(&button);
    content.append(&row);
}

fn apply_and_refresh(
    request: &ApplyRequest,
    content: &gtk::Box,
    status: &gtk::Label,
    editors: &Rc<RefCell<Vec<Editor>>>,
    save: &gtk::Button,
    success: &str,
) {
    let apply_result = apply(request);
    let reload_result = render(content, status, editors, save);
    match (apply_result, reload_result) {
        (Ok(()), Ok(())) => {
            content.set_sensitive(true);
            save.set_sensitive(true);
            status.set_text(success);
        }
        (Err(error), Ok(())) => {
            content.set_sensitive(true);
            save.set_sensitive(true);
            status.set_text(&format!(
                "操作に失敗しました: {error} 現在の設定を再読み込みしました。未保存の入力は消えています。"
            ));
        }
        (Ok(()), Err(reload_error)) => {
            content.set_sensitive(false);
            save.set_sensitive(false);
            status.set_text(&format!(
                "設定は更新されましたが再読み込みに失敗しました: {reload_error} 再読み込みを押してください。"
            ));
        }
        (Err(error), Err(reload_error)) => {
            content.set_sensitive(false);
            save.set_sensitive(false);
            status.set_text(&format!(
                "操作に失敗しました: {error} 再読み込みにも失敗しました: {reload_error} 再読み込みを押してください。"
            ));
        }
    }
}

pub struct SettingsUi {
    pub window: gtk::ApplicationWindow,
    pub content: gtk::Box,
    pub status: gtk::Label,
    pub save: gtk::Button,
    pub reload: gtk::Button,
}

pub fn build_ui(app: &gtk::Application) -> SettingsUi {
        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("mlh 設定")
            .default_width(780)
            .default_height(780)
            .build();
        let outer = gtk::Box::new(gtk::Orientation::Vertical, 12);
        outer.set_margin_start(20);
        outer.set_margin_end(20);
        outer.set_margin_top(16);
        outer.set_margin_bottom(16);
        let header = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        let title = label("mlh 設定");
        title.add_css_class("title-1");
        title.set_hexpand(true);
        header.append(&title);
        let reload = gtk::Button::with_label("再読み込み");
        header.append(&reload);
        let save = gtk::Button::with_label("保存");
        save.add_css_class("suggested-action");
        header.append(&save);
        outer.append(&header);
        let status = label("");
        status.set_wrap(true);
        outer.append(&status);
        let scroll = gtk::ScrolledWindow::new();
        scroll.set_vexpand(true);
        let content = gtk::Box::new(gtk::Orientation::Vertical, 6);
        scroll.set_child(Some(&content));
        outer.append(&scroll);
        window.set_child(Some(&outer));
        let editors = Rc::new(RefCell::new(Vec::new()));
        if let Err(error) = render(&content, &status, &editors, &save) {
            content.set_sensitive(false);
            save.set_sensitive(false);
            status.set_text(&error);
        }
        let content_copy = content.clone();
        let status_copy = status.clone();
        let editors_copy = editors.clone();
        let save_copy = save.clone();
        reload.connect_clicked(move |_| {
            match render(&content_copy, &status_copy, &editors_copy, &save_copy) {
                Ok(()) => {
                    content_copy.set_sensitive(true);
                    save_copy.set_sensitive(true);
                    status_copy.set_text("設定を再読み込みしました");
                }
                Err(error) => {
                    content_copy.set_sensitive(false);
                    save_copy.set_sensitive(false);
                    status_copy.set_text(&format!("再読み込みに失敗しました: {error}"));
                }
            }
        });
        let content_copy = content.clone();
        let status_copy = status.clone();
        let save_copy = save.clone();
        save.connect_clicked(move |_| {
            let changes = collect_changes(&editors.borrow());
            let request = ApplyRequest {
                schema: 1,
                changes,
                actions: vec![],
            };
            apply_and_refresh(&request, &content_copy, &status_copy, &editors,
                              &save_copy, "設定を保存しました");
        });
        SettingsUi { window, content, status, save, reload }
}

pub fn run() -> gtk::glib::ExitCode {
    let app = gtk::Application::builder()
        .application_id("com.github.kazu.mlh.settings")
        .build();
    app.connect_activate(|app| {
        let ui = build_ui(app);
        ui.window.present();
    });
    app.run()
}
