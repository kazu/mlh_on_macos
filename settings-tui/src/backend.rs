use std::{
    io::{self, Write},
    path::Path,
    process::{Command, Stdio},
};

use crate::{app::App, model::Snapshot};

pub fn load_snapshot(backend: &Path) -> io::Result<Snapshot> {
    let output = Command::new(backend).arg("snapshot").output()?;
    if !output.status.success() {
        return Err(io::Error::other(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ));
    }
    let data: Snapshot = serde_json::from_slice(&output.stdout)?;
    if data.schema != 1 {
        return Err(io::Error::other("unsupported settings schema"));
    }
    Ok(data)
}

fn apply(backend: &Path, app: &App) -> io::Result<()> {
    let mut process = Command::new(backend)
        .arg("apply")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let request = serde_json::to_vec(&app.request())?;
    process
        .stdin
        .take()
        .ok_or_else(|| io::Error::other("settings stdin unavailable"))?
        .write_all(&request)?;
    let output = process.wait_with_output()?;
    if output.status.success() {
        Ok(())
    } else {
        Err(io::Error::other(
            String::from_utf8_lossy(&output.stderr).into_owned(),
        ))
    }
}

pub fn save(backend: &Path, app: &mut App) {
    if app.save_disabled || (app.changes.is_empty() && app.actions.is_empty()) {
        return;
    }
    let result = apply(backend, app);
    match (result, load_snapshot(backend)) {
        (Ok(()), Ok(settings)) => {
            *app = App::new(settings);
            app.message = "保存しました".into();
        }
        (Err(error), Ok(settings)) => {
            *app = App::new(settings);
            app.message =
                format!("保存に失敗。未保存の入力は消えました。\n状態を読み直しました。\n{error}");
        }
        (result, Err(reload_error)) => {
            app.changes.clear();
            app.actions.clear();
            app.save_disabled = true;
            app.message = format!(
                "保存後の状態を確認できません。未保存の入力は消えました。\n終了して開き直してください。\n{reload_error}{}",
                result
                    .err()
                    .map_or(String::new(), |error| format!(" / {error}"))
            );
        }
    }
}
