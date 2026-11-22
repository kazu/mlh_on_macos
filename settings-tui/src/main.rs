use std::{io, path::PathBuf};

use crossterm::event::{self, Event};
use mlh_settings_tui::{
    app::{App, Effect},
    backend,
};
use ratatui::{
    Frame,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};

fn backend_path() -> io::Result<PathBuf> {
    Ok(std::env::current_exe()?.with_file_name("mlh-settings-backend"))
}

fn draw(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(4),
            Constraint::Length(4),
            Constraint::Length(5),
        ])
        .split(frame.area());
    let mut rows: Vec<_> = app
        .snapshot
        .fields
        .iter()
        .map(|field| {
            let section = app
                .snapshot
                .sections
                .iter()
                .find(|s| s.id == field.section)
                .map_or(field.section.as_str(), |s| s.label.as_str());
            let mark = if app.changes.contains_key(&field.id) {
                "*"
            } else {
                " "
            };
            let availability = if field.editable {
                ""
            } else {
                "（変更不可）"
            };
            let text = format!(
                "{mark} [{section}] {}: {}{availability}",
                field.label,
                app.displayed_value(field)
            );
            ListItem::new(text)
        })
        .collect();
    rows.extend(app.snapshot.actions.iter().map(|action| {
        let section = app
            .snapshot
            .sections
            .iter()
            .find(|s| s.id == action.section)
            .map_or(action.section.as_str(), |s| s.label.as_str());
        ListItem::new(format!("  [{section}] {}…", action.label))
    }));
    let list = List::new(rows)
        .block(Block::default().title("mlh 設定").borders(Borders::ALL))
        .highlight_style(
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        );
    let selected = if app.snapshot.fields.is_empty() && app.snapshot.actions.is_empty() {
        None
    } else {
        Some(app.selected)
    };
    let mut list_state = ListState::default().with_selected(selected);
    frame.render_stateful_widget(list, chunks[0], &mut list_state);
    let detail = if let Some(editor) = &app.action_editing {
        format!(
            "{}: {}\nEnter: 次へ  Esc: 取消",
            app.action_prompt().unwrap_or("入力"),
            editor.buffer
        )
    } else if let Some(value) = &app.editing {
        let text = if app.selected_field().is_some_and(|f| f.kind == "secret") {
            "•".repeat(value.chars().count())
        } else {
            value.clone()
        };
        format!("編集中: {text}\nEnter: 確定  Ctrl-N: 改行  Esc: 取消")
    } else if let Some(field) = app.selected_field() {
        format!("{}\n現在の取得元: {}", field.description, field.origin)
    } else if let Some(action) = app.selected_action() {
        format!("{} を実行します。\n保存時に適用されます。", action.label)
    } else {
        String::new()
    };
    frame.render_widget(
        Paragraph::new(detail).block(Block::default().title("詳細").borders(Borders::ALL)),
        chunks[1],
    );
    let help = if app.message.is_empty() {
        "↑↓: 選択  Enter: 編集  r: 戻す  Ctrl-S: 保存  q: 終了".to_string()
    } else {
        app.message.clone()
    };
    frame.render_widget(
        Paragraph::new(help)
            .wrap(Wrap { trim: false })
            .block(Block::default().borders(Borders::ALL)),
        chunks[2],
    );
}

fn main() -> io::Result<()> {
    let backend = backend_path()?;
    let mut app = App::new(backend::load_snapshot(&backend)?);
    ratatui::run(|terminal| {
        loop {
            terminal.draw(|frame| draw(frame, &app))?;
            if let Event::Key(key) = event::read()? {
                match app.handle_key(key) {
                    Effect::None => {}
                    Effect::Quit => break Ok(()),
                    Effect::Save => backend::save(&backend, &mut app),
                }
            }
        }
    })
}
