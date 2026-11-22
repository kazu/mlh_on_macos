use std::collections::BTreeMap;

use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

use crate::model::{Action, ActionRequest, ApplyRequest, Change, Field, Snapshot};

pub struct ActionEditor {
    pub action_id: String,
    pub input_index: usize,
    pub values: BTreeMap<String, String>,
    pub buffer: String,
}

pub enum Effect {
    None,
    Save,
    Quit,
}

pub struct App {
    pub snapshot: Snapshot,
    pub selected: usize,
    pub editing: Option<String>,
    pub action_editing: Option<ActionEditor>,
    pub changes: BTreeMap<String, Change>,
    pub actions: Vec<ActionRequest>,
    pub message: String,
    pub save_disabled: bool,
}

impl App {
    pub fn new(snapshot: Snapshot) -> Self {
        Self {
            snapshot,
            selected: 0,
            editing: None,
            action_editing: None,
            changes: BTreeMap::new(),
            actions: Vec::new(),
            message: String::new(),
            save_disabled: false,
        }
    }

    pub fn selected_field(&self) -> Option<&Field> {
        self.snapshot.fields.get(self.selected)
    }

    pub fn selected_action(&self) -> Option<&Action> {
        self.selected
            .checked_sub(self.snapshot.fields.len())
            .and_then(|index| self.snapshot.actions.get(index))
    }

    pub fn action_prompt(&self) -> Option<&str> {
        let editor = self.action_editing.as_ref()?;
        self.snapshot
            .actions
            .iter()
            .find(|action| action.id == editor.action_id)?
            .inputs
            .get(editor.input_index)
            .map(|input| input.label.as_str())
    }

    pub fn displayed_value(&self, field: &Field) -> String {
        let staged = self.changes.get(&field.id);
        if field.kind == "secret" {
            return if staged.is_some_and(|c| c.op == "reset") {
                "未設定".into()
            } else if staged.is_some_and(|c| c.op == "set") || field.has_value {
                "設定済み".into()
            } else {
                "未設定".into()
            };
        }
        let raw = if let Some(change) = staged {
            if change.op == "reset" {
                return "デフォルトへ戻す".into();
            }
            change.value.as_deref().unwrap_or_default()
        } else {
            field.value.as_deref().unwrap_or_default()
        };
        if field.kind == "select" {
            return field
                .options
                .iter()
                .find(|option| option.value == raw)
                .map_or_else(|| raw.to_string(), |option| option.label.clone());
        }
        raw.to_string()
    }

    pub fn request(&self) -> ApplyRequest {
        ApplyRequest {
            schema: 1,
            changes: self.changes.values().cloned().collect(),
            actions: self.actions.clone(),
        }
    }

    fn stage(&mut self, value: String) {
        if let Some(field) = self.selected_field() {
            let id = field.id.clone();
            self.changes.insert(
                id.clone(),
                Change {
                    id,
                    op: "set".into(),
                    value: Some(value),
                },
            );
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> Effect {
        if key.kind != KeyEventKind::Press {
            return Effect::None;
        }
        if let Some(mut editor) = self.action_editing.take() {
            match key.code {
                KeyCode::Esc => {}
                KeyCode::Enter => {
                    if let Some(action) = self
                        .snapshot
                        .actions
                        .iter()
                        .find(|action| action.id == editor.action_id)
                    {
                        if let Some(input) = action.inputs.get(editor.input_index) {
                            editor
                                .values
                                .insert(input.id.clone(), std::mem::take(&mut editor.buffer));
                            editor.input_index += 1;
                        }
                        if editor.input_index >= action.inputs.len() {
                            self.actions.push(ActionRequest {
                                id: editor.action_id,
                                values: editor.values,
                            });
                        } else {
                            self.action_editing = Some(editor);
                        }
                    }
                }
                KeyCode::Backspace => {
                    editor.buffer.pop();
                    self.action_editing = Some(editor);
                }
                KeyCode::Char(c) => {
                    editor.buffer.push(c);
                    self.action_editing = Some(editor);
                }
                _ => self.action_editing = Some(editor),
            }
            return Effect::None;
        }
        if let Some(mut value) = self.editing.take() {
            match key.code {
                KeyCode::Esc => {}
                KeyCode::Enter => self.stage(value),
                KeyCode::Backspace => {
                    value.pop();
                    self.editing = Some(value);
                }
                KeyCode::Char('n') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    value.push('\n');
                    self.editing = Some(value);
                }
                KeyCode::Char(c) => {
                    value.push(c);
                    self.editing = Some(value);
                }
                _ => self.editing = Some(value),
            }
            return Effect::None;
        }
        if !self.save_disabled
            && key.modifiers.contains(KeyModifiers::CONTROL)
            && key.code == KeyCode::Char('s')
        {
            return Effect::Save;
        }
        match key.code {
            KeyCode::Char('q') => Effect::Quit,
            KeyCode::Up => {
                self.selected = self.selected.saturating_sub(1);
                Effect::None
            }
            KeyCode::Down => {
                self.selected = (self.selected + 1).min(
                    (self.snapshot.fields.len() + self.snapshot.actions.len()).saturating_sub(1),
                );
                Effect::None
            }
            KeyCode::Char('r') => {
                if let Some(field) = self.selected_field() {
                    if field.editable {
                        let id = field.id.clone();
                        self.changes.insert(
                            id.clone(),
                            Change {
                                id,
                                op: "reset".into(),
                                value: None,
                            },
                        );
                    }
                }
                Effect::None
            }
            KeyCode::Enter => {
                if let Some(action) = self.selected_action() {
                    let id = action.id.clone();
                    if action.inputs.is_empty() {
                        self.actions.push(ActionRequest {
                            id,
                            values: BTreeMap::new(),
                        });
                    } else {
                        self.action_editing = Some(ActionEditor {
                            action_id: id,
                            input_index: 0,
                            values: BTreeMap::new(),
                            buffer: String::new(),
                        });
                    }
                    return Effect::None;
                }
                if let Some(field) = self.selected_field() {
                    if !field.editable {
                        return Effect::None;
                    }
                    if field.kind == "select" && !field.options.is_empty() {
                        let current = self
                            .changes
                            .get(&field.id)
                            .and_then(|change| change.value.as_deref())
                            .or(field.value.as_deref())
                            .unwrap_or_default();
                        let index = field
                            .options
                            .iter()
                            .position(|o| o.value == current)
                            .unwrap_or(field.options.len() - 1);
                        let next = field.options[(index + 1) % field.options.len()]
                            .value
                            .clone();
                        self.stage(next);
                    } else {
                        self.editing = Some(if field.kind == "secret" {
                            String::new()
                        } else {
                            self.displayed_value(field)
                        });
                    }
                }
                Effect::None
            }
            _ => Effect::None,
        }
    }
}
