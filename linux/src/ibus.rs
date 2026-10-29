use std::{
    collections::HashMap,
    ffi::{CStr, c_char, c_void},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};
use zbus::{
    Connection, fdo,
    object_server::SignalEmitter,
    zvariant::{Dict, OwnedObjectPath, OwnedValue, Signature, StructureBuilder, Value},
};

use crate::core::{Conversion, Engine, Execution, ResultValue, TypedBuffer, edit_plan};

#[derive(Default)]
pub struct Factory {
    next_id: AtomicU64,
}

#[zbus::interface(name = "org.freedesktop.IBus.Factory")]
impl Factory {
    async fn create_engine(
        &self,
        name: &str,
        #[zbus(connection)] connection: &Connection,
    ) -> fdo::Result<OwnedObjectPath> {
        if name != "mlh" {
            return Err(fdo::Error::InvalidArgs("unknown input method".into()));
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let path = OwnedObjectPath::try_from(format!("/org/freedesktop/IBus/Engine/{id}"))
            .map_err(|err| fdo::Error::Failed(err.to_string()))?;
        connection
            .object_server()
            .at(path.clone(), InputMethod::default())
            .await
            .map_err(|err| fdo::Error::Failed(err.to_string()))?;
        connection
            .object_server()
            .at(path.clone(), EngineService)
            .await
            .map_err(|err| fdo::Error::Failed(err.to_string()))?;
        Ok(path)
    }
}

struct EngineService;

#[zbus::interface(name = "org.freedesktop.IBus.Service")]
impl EngineService {
    async fn destroy(
        &self,
        #[zbus(connection)] connection: &Connection,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        let server = connection.object_server();
        server
            .remove::<InputMethod, _>(emitter.path())
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        server
            .remove::<EngineService, _>(emitter.path())
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(())
    }
}

#[derive(Default)]
struct InputMethod {
    surrounding: Mutex<Option<(String, u32, u32)>>,
    conversion: Mutex<Option<Conversion>>,
    lookup_visible: Mutex<bool>,
    selection: Mutex<Option<Selection>>,
    typed: Arc<Mutex<TypedBuffer>>,
    executions: Arc<Mutex<Executions>>,
    app: Mutex<Option<String>>,
    content_purpose: Mutex<u32>,
}

impl Drop for InputMethod {
    fn drop(&mut self) {
        self.cancel_execution();
    }
}

#[derive(Default)]
struct Executions {
    next: u64,
    active: Option<u64>,
    running: HashMap<u64, Running>,
}

struct Running {
    handle: Option<Execution>,
    prefix: String,
    scalars: u32,
    characters: u32,
    synthetic: bool,
    terminal_delete: bool,
    queued: Vec<(u32, u32, u32)>,
    cancelled: bool,
}

struct ExecuteCallback {
    connection: zbus::blocking::Connection,
    path: OwnedObjectPath,
    executions: Arc<Mutex<Executions>>,
    typed: Arc<Mutex<TypedBuffer>>,
    id: u64,
}

extern "C" fn execute_callback(context: *mut c_void, text: *const c_char, done: i32) {
    let callback = unsafe { &*(context as *mut ExecuteCallback) };
    let text = if text.is_null() {
        None
    } else {
        Some(
            unsafe { CStr::from_ptr(text) }
                .to_string_lossy()
                .into_owned(),
        )
    };
    if let Ok(mut executions) = callback.executions.lock() {
        let active = executions.active == Some(callback.id);
        if let Some(running) = executions.running.get_mut(&callback.id) {
            if active && !running.cancelled {
                if done != 0 {
                    if let Some(text) = text.as_deref() {
                        if running.synthetic && !running.terminal_delete {
                            for _ in 0..running.characters {
                                for state in [0_u32, 1 << 30] {
                                    let _ = callback.connection.emit_signal(
                                        None::<&str>,
                                        callback.path.as_str(),
                                        "org.freedesktop.IBus.Engine",
                                        "ForwardKeyEvent",
                                        &(0xff08_u32, 14_u32, state),
                                    );
                                }
                            }
                        } else if !running.synthetic {
                            let _ = callback.connection.emit_signal(
                                None::<&str>,
                                callback.path.as_str(),
                                "org.freedesktop.IBus.Engine",
                                "DeleteSurroundingText",
                                &(-(running.scalars as i32), running.scalars),
                            );
                        }
                        if let Ok(value) = ibus_text(&commit_payload(
                            text,
                            running.characters,
                            running.terminal_delete,
                        )) {
                            let _ = callback.connection.emit_signal(
                                None::<&str>,
                                callback.path.as_str(),
                                "org.freedesktop.IBus.Engine",
                                "CommitText",
                                &(value,),
                            );
                            callback.typed.lock().unwrap().set(&running.prefix);
                            callback.typed.lock().unwrap().append(text);
                        }
                    } else if let Ok(value) = ibus_text("") {
                        let _ = callback.connection.emit_signal(
                            None::<&str>,
                            callback.path.as_str(),
                            "org.freedesktop.IBus.Engine",
                            "UpdatePreeditText",
                            &(value, 0_u32, false, 0_u32),
                        );
                    }
                    for key in &running.queued {
                        if key.2 & (1 << 30) == 0 {
                            InputMethod::track_typed(&callback.typed, key.0, key.2);
                        }
                        let _ = callback.connection.emit_signal(
                            None::<&str>,
                            callback.path.as_str(),
                            "org.freedesktop.IBus.Engine",
                            "ForwardKeyEvent",
                            key,
                        );
                    }
                } else if let Some(text) = text.as_deref() {
                    if let Ok(value) = ibus_text(text) {
                        let cursor = text.chars().count() as u32;
                        let _ = callback.connection.emit_signal(
                            None::<&str>,
                            callback.path.as_str(),
                            "org.freedesktop.IBus.Engine",
                            "UpdatePreeditText",
                            &(value, cursor, true, 0_u32),
                        );
                    }
                }
            }
        }
        if done != 0 {
            if active {
                executions.active = None;
            }
            executions.running.remove(&callback.id);
        }
    }
    if done != 0 {
        unsafe { drop(Box::from_raw(context as *mut ExecuteCallback)) }
    }
}

struct Selection {
    result: ResultValue,
    choices: Vec<isize>,
    current: usize,
}

fn dictionary_path() -> Option<String> {
    if std::env::var("MLH_TRANSLITERATOR").as_deref() == Ok("google") {
        return Some(String::new());
    }
    if let Some(path) = std::env::var_os("MLH_DICTIONARY") {
        let path = std::path::PathBuf::from(path);
        return path
            .is_dir()
            .then(|| path.into_os_string().into_string().ok())?;
    }
    let installed = std::env::current_exe()
        .ok()
        .and_then(|path| Some(path.parent()?.parent()?.join("share/mlh/Dictionary")));
    let user_data = std::env::var_os("XDG_DATA_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(".local/share"))
        })
        .map(|path| path.join("mlh/Dictionary"));
    first_existing_dictionary(user_data, installed)
}

fn first_existing_dictionary(
    user_data: Option<std::path::PathBuf>,
    installed: Option<std::path::PathBuf>,
) -> Option<String> {
    user_data
        .into_iter()
        .chain(installed)
        .find(|path| path.is_dir())?
        .into_os_string()
        .into_string()
        .ok()
}

#[cfg(test)]
mod dictionary_tests {
    use super::first_existing_dictionary;

    #[test]
    fn user_dictionary_takes_precedence_and_system_is_a_fallback() {
        let root = std::env::temp_dir().join(format!("mlh-dictionaries-{}", std::process::id()));
        let user = root.join("user");
        let system = root.join("system");
        std::fs::create_dir_all(&user).unwrap();
        std::fs::create_dir_all(&system).unwrap();
        assert_eq!(
            first_existing_dictionary(Some(user.clone()), Some(system.clone())),
            user.to_str().map(str::to_owned)
        );
        std::fs::remove_dir(&user).unwrap();
        assert_eq!(
            first_existing_dictionary(Some(user), Some(system.clone())),
            system.to_str().map(str::to_owned)
        );
        std::fs::remove_dir_all(root).unwrap();
    }
}

async fn show_selection(emitter: &SignalEmitter<'_>, selection: &Selection) -> zbus::Result<()> {
    let Some(text) = selection.result.render_marked(&selection.choices, false) else {
        return Ok(());
    };
    let text_value = ibus_text(&text)?;
    InputMethod::update_preedit_text(emitter, text_value, text.chars().count() as u32, true, 1)
        .await?;
    let candidates = selection.result.candidates(selection.current);
    let table = lookup_table(&candidates, selection.choices[selection.current] as usize)?;
    InputMethod::update_lookup_table(emitter, table, true).await
}

impl InputMethod {
    async fn finish_context(&self, emitter: &SignalEmitter<'_>) {
        *self.surrounding.lock().unwrap() = None;
        self.typed.lock().unwrap().reset();
        self.cancel_execution();
        let selection = self.selection.lock().unwrap().take();
        if selection.is_some() {
            let _ = Self::hide_lookup_table(emitter).await;
        }
        self.conversion.lock().unwrap().take();
        let visible = std::mem::take(&mut *self.lookup_visible.lock().unwrap());
        if visible {
            let _ = Self::hide_lookup_table(emitter).await;
        }
    }

    fn cancel_execution(&self) -> Option<()> {
        let mut executions = self.executions.lock().unwrap();
        let id = executions.active.take()?;
        let running = executions.running.get_mut(&id)?;
        running.cancelled = true;
        if let Some(handle) = &running.handle {
            handle.cancel();
        }
        Some(())
    }

    fn track_key(&self, keyval: u32, state: u32) {
        Self::track_typed(&self.typed, keyval, state);
    }

    fn track_typed(buffer: &Mutex<TypedBuffer>, keyval: u32, state: u32) {
        let mut typed = buffer.lock().unwrap();
        if (0xffe1..=0xffee).contains(&keyval) {
            return;
        }
        if state & (4 | 8 | (1 << 26) | (1 << 28)) != 0 {
            typed.reset();
            return;
        }
        match keyval {
            0xff08 => typed.remove(),
            0xff09 | 0xff0d | 0xff8d | 0xff1b | 0xff50..=0xff57 | 0xffff => typed.reset(),
            _ => {
                let codepoint = if keyval & 0xff00_0000 == 0x0100_0000 {
                    Some(keyval & 0x00ff_ffff)
                } else if (0x20..=0x7e).contains(&keyval) || (0xa0..=0xff).contains(&keyval) {
                    Some(keyval)
                } else {
                    None
                };
                if let Some(c) = codepoint
                    .and_then(char::from_u32)
                    .filter(|c| !c.is_control() && !('\u{f700}'..='\u{f8ff}').contains(c))
                {
                    typed.append(&c.to_string());
                } else {
                    typed.reset();
                }
            }
        }
    }

    async fn delete_before(
        emitter: &SignalEmitter<'_>,
        count: u32,
        synthetic: bool,
        terminal_delete: bool,
    ) -> zbus::Result<()> {
        if terminal_delete {
            Ok(())
        } else if synthetic {
            for _ in 0..count {
                Self::forward_key_event(emitter, 0xff08, 14, 0).await?;
                Self::forward_key_event(emitter, 0xff08, 14, 1 << 30).await?;
            }
            Ok(())
        } else {
            Self::delete_surrounding_text(emitter, -(count as i32), count).await
        }
    }
}

fn commit_payload(text: &str, characters: u32, terminal_delete: bool) -> String {
    if terminal_delete {
        format!("{}{}", "\u{7f}".repeat(characters as usize), text)
    } else {
        text.to_owned()
    }
}

fn ibus_text(text: &str) -> zbus::zvariant::Result<OwnedValue> {
    ibus_text_with_segments(text, &[])
}

fn ibus_text_with_segments(
    text: &str,
    segments: &[(u32, u32, bool)],
) -> zbus::zvariant::Result<OwnedValue> {
    let mut attributes = Vec::with_capacity(segments.len());
    for &(start, end, selected) in segments {
        let attribute = StructureBuilder::new()
            .add_field("IBusAttribute")
            .append_field(Value::from(Dict::new(&Signature::Str, &Signature::Variant)))
            .add_field(1_u32)
            .add_field(if selected { 2_u32 } else { 1_u32 })
            .add_field(start)
            .add_field(end)
            .build()?;
        attributes.push(OwnedValue::try_from(Value::from(attribute))?);
    }
    let attributes = StructureBuilder::new()
        .add_field("IBusAttrList")
        .append_field(Value::from(Dict::new(&Signature::Str, &Signature::Variant)))
        .add_field(attributes)
        .build()?;
    let text = StructureBuilder::new()
        .add_field("IBusText")
        .append_field(Value::from(Dict::new(&Signature::Str, &Signature::Variant)))
        .add_field(text)
        .add_field(OwnedValue::try_from(Value::from(attributes))?)
        .build()?;
    OwnedValue::try_from(Value::from(text))
}

fn lookup_table(candidates: &[String], selected: usize) -> zbus::zvariant::Result<OwnedValue> {
    let candidates: Vec<OwnedValue> = candidates
        .iter()
        .map(|s| ibus_text(s))
        .collect::<Result<_, _>>()?;
    let labels: Vec<OwnedValue> = Vec::new();
    let table = StructureBuilder::new()
        .add_field("IBusLookupTable")
        .append_field(Value::from(Dict::new(&Signature::Str, &Signature::Variant)))
        .add_field(9_u32)
        .add_field(selected as u32)
        .add_field(true)
        .add_field(true)
        .add_field(1_i32)
        .add_field(candidates)
        .add_field(labels)
        .build()?;
    OwnedValue::try_from(Value::from(table))
}

#[zbus::interface(name = "org.freedesktop.IBus.Engine")]
impl InputMethod {
    async fn process_key_event(
        &self,
        keyval: u32,
        keycode: u32,
        state: u32,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> bool {
        let pending = {
            let mut executions = self.executions.lock().unwrap();
            if let Some(id) = executions.active {
                let cancel = state & (1 << 30) == 0
                    && (keyval == 0xff1b
                        || (state & 4 != 0 && keyval == 0x67)
                        || state & (1 << 26) != 0);
                let running = executions.running.get_mut(&id).unwrap();
                if cancel {
                    running.cancelled = true;
                    let queued = std::mem::take(&mut running.queued);
                    if let Some(handle) = &running.handle {
                        handle.cancel();
                    }
                    executions.active = None;
                    Some((true, state & (1 << 26) == 0, queued))
                } else {
                    running.queued.push((keyval, keycode, state));
                    Some((false, true, Vec::new()))
                }
            } else {
                None
            }
        };
        if let Some((cancelled, handled, queued)) = pending {
            if cancelled {
                if let Ok(value) = ibus_text("") {
                    let _ = Self::update_preedit_text(&emitter, value, 0, false, 0).await;
                }
                for (keyval, keycode, state) in queued {
                    if state & (1 << 30) == 0 {
                        Self::track_typed(&self.typed, keyval, state);
                    }
                    let _ = Self::forward_key_event(&emitter, keyval, keycode, state).await;
                }
            }
            return handled;
        }
        if state & (1 << 30) != 0 {
            return false;
        }
        let selection = self.selection.lock().unwrap().take();
        if let Some(mut selection) = selection {
            let control = state & 4 != 0;
            let count = selection.result.candidates(selection.current).len() as isize;
            let direction = match (control, keyval) {
                (false, 0x20) | (true, 0x66) => 1,
                (false, 0xff08) | (true, 0x62) => -1,
                _ => 0,
            };
            if direction != 0 {
                selection.choices[selection.current] =
                    (selection.choices[selection.current] + direction).rem_euclid(count);
                let _ = show_selection(&emitter, &selection).await;
                *self.selection.lock().unwrap() = Some(selection);
                return true;
            }
            let slash = !control && keyval == 0x2f;
            selection.current += 1;
            if slash && selection.current < selection.choices.len() {
                let _ = show_selection(&emitter, &selection).await;
                *self.selection.lock().unwrap() = Some(selection);
                return true;
            }
            let _ = Self::hide_lookup_table(&emitter).await;
            if selection.result.needs_kanji {
                let prefix = selection
                    .result
                    .render_marked(&selection.choices, true)
                    .unwrap_or_default();
                let reading = selection
                    .result
                    .render_part(&selection.choices, true)
                    .unwrap_or_default();
                if !reading.is_empty() {
                    if let Some(conversion) =
                        dictionary_path().and_then(|path| Conversion::new(&reading, &path))
                    {
                        if let Ok(value) = ibus_text(&prefix) {
                            let _ = Self::commit_text(&emitter, value).await;
                        }
                        self.typed.lock().unwrap().append(&prefix);
                        let text = conversion.text();
                        let value = if slash {
                            ibus_text_with_segments(&text, &conversion.segments())
                        } else {
                            ibus_text(&text)
                        };
                        if let Ok(value) = value {
                            if slash {
                                let _ = Self::update_preedit_text(
                                    &emitter,
                                    value,
                                    text.chars().count() as u32,
                                    true,
                                    1,
                                )
                                .await;
                            } else {
                                let _ = Self::commit_text(&emitter, value).await;
                                self.typed.lock().unwrap().append(&text);
                            }
                        }
                        if slash {
                            *self.conversion.lock().unwrap() = Some(conversion);
                        }
                        return slash;
                    }
                }
            }
            if let Some(text) = selection.result.render_marked(&selection.choices, false) {
                if let Ok(value) = ibus_text(&text) {
                    let _ = Self::commit_text(&emitter, value).await;
                }
                self.typed.lock().unwrap().append(&text);
            }
            return slash;
        }
        let active = self.conversion.lock().unwrap().is_some();
        if active {
            let control = state & 4 != 0;
            let shift = state & 1 != 0;
            if !control && (0x31..=0x39).contains(&keyval) && *self.lookup_visible.lock().unwrap() {
                let (text, segments) = {
                    let mut conversion = self.conversion.lock().unwrap();
                    let conversion = conversion.as_mut().unwrap();
                    let (candidates, selected) = conversion.candidates();
                    let index = selected / 9 * 9 + (keyval - 0x31) as usize;
                    if index >= candidates.len() {
                        return true;
                    }
                    conversion.select(index);
                    (conversion.text(), conversion.segments())
                };
                *self.lookup_visible.lock().unwrap() = false;
                let _ = Self::hide_lookup_table(&emitter).await;
                if let Ok(value) = ibus_text_with_segments(&text, &segments) {
                    let _ = Self::update_preedit_text(
                        &emitter,
                        value,
                        text.chars().count() as u32,
                        true,
                        1,
                    )
                    .await;
                }
                return true;
            }
            let action = match (control, keyval) {
                (false, 0x20 | 0xff54) | (true, 0x6e) => Some(0),
                (false, 0xff52) | (true, 0x70) => Some(1),
                (false, 0xff53) if shift => Some(7),
                (false, 0xff51) if shift => Some(6),
                (false, 0xff53) | (true, 0x66) => Some(2),
                (false, 0xff51) | (true, 0x62) => Some(3),
                (false, 0xff09) => Some(6),
                (true, 0x61) => Some(4),
                (true, 0x65) => Some(5),
                (true, 0x69) => Some(6),
                (true, 0x6f) => Some(7),
                _ => None,
            };
            if let Some(action) = action {
                let (text, candidates, segments) = {
                    let mut conversion = self.conversion.lock().unwrap();
                    let conversion = conversion.as_mut().unwrap();
                    conversion.step(action);
                    (
                        conversion.text(),
                        conversion.candidates(),
                        conversion.segments(),
                    )
                };
                if let Ok(value) = ibus_text_with_segments(&text, &segments) {
                    let _ = Self::update_preedit_text(
                        &emitter,
                        value,
                        text.chars().count() as u32,
                        true,
                        1,
                    )
                    .await;
                }
                let show = action <= 1;
                *self.lookup_visible.lock().unwrap() = show;
                if show {
                    if let Ok(table) = lookup_table(&candidates.0, candidates.1) {
                        let _ = Self::update_lookup_table(&emitter, table, true).await;
                    }
                } else {
                    let _ = Self::hide_lookup_table(&emitter).await;
                }
                return true;
            }
            let conversion = self.conversion.lock().unwrap().take().unwrap();
            *self.lookup_visible.lock().unwrap() = false;
            let _ = Self::hide_lookup_table(&emitter).await;
            let abort = (control && matches!(keyval, 0x67 | 0x63))
                || (!control && matches!(keyval, 0xff1b | 0xff08));
            let text = if abort {
                conversion.reading()
            } else {
                conversion.text()
            };
            if let Ok(empty) = ibus_text("") {
                let _ = Self::update_preedit_text(&emitter, empty, 0, false, 0).await;
            }
            if let Ok(text) = ibus_text(&text) {
                let _ = Self::commit_text(&emitter, text).await;
            }
            self.typed.lock().unwrap().append(&text);
            return abort
                || matches!(
                    (control, keyval),
                    (false, 0xff0d | 0xff8d) | (true, 0x6d | 0x6c)
                );
        }
        if keyval != 0x20 || state & ((1 << 30) | 0x0d) != 0 {
            self.track_key(keyval, state);
            return false;
        }
        let context = self.surrounding.lock().unwrap().clone();
        let api = context.and_then(|(text, cursor, anchor)| {
            if cursor != anchor {
                return None;
            }
            let before: String = text.chars().take(cursor as usize).collect();
            let line = before
                .rsplit(['\n', '\r', '\u{2028}', '\u{2029}'])
                .next()
                .unwrap_or("")
                .to_owned();
            line.ends_with('/').then_some(line)
        });
        let (line, synthetic) = if let Some(line) = api {
            (line, false)
        } else {
            let typed = self.typed.lock().unwrap();
            let line = typed.text();
            if !line.ends_with('/') {
                drop(typed);
                self.track_key(keyval, state);
                return false;
            }
            (line, true)
        };
        let terminal_delete = synthetic && *self.content_purpose.lock().unwrap() == 10;
        let app = self.app.lock().unwrap().clone();
        let Some(result) = Engine::for_app(app.as_deref()).run(&line) else {
            return false;
        };
        if result.kind == 1 {
            return true;
        }
        if result.kind != 2 {
            self.track_key(keyval, state);
            return false;
        }
        if let Some((prefix, source, key)) = &result.execute {
            let base = format!("{prefix}{source}");
            let Some((scalars, characters, replacement)) = edit_plan(&line, &base) else {
                return false;
            };
            let Some((source_scalars, source_characters, _)) = edit_plan(source, "") else {
                return false;
            };
            let Ok(prefix_value) =
                ibus_text(&commit_payload(&replacement, characters, terminal_delete))
            else {
                return false;
            };
            if Self::delete_before(
                &emitter,
                if synthetic { characters } else { scalars },
                synthetic,
                terminal_delete,
            )
            .await
            .is_err()
            {
                return false;
            }
            if Self::commit_text(&emitter, prefix_value).await.is_err() {
                return false;
            }
            *self.surrounding.lock().unwrap() = None;
            self.typed.lock().unwrap().set(&base);
            let id = {
                let mut executions = self.executions.lock().unwrap();
                let id = executions.next;
                executions.next += 1;
                executions.active = Some(id);
                executions.running.insert(
                    id,
                    Running {
                        handle: None,
                        prefix: prefix.clone(),
                        scalars: source_scalars,
                        characters: source_characters,
                        synthetic,
                        terminal_delete,
                        queued: Vec::new(),
                        cancelled: false,
                    },
                );
                id
            };
            let callback = Box::new(ExecuteCallback {
                connection: zbus::blocking::Connection::from(emitter.connection().clone()),
                path: emitter.path().to_owned().into(),
                executions: self.executions.clone(),
                typed: self.typed.clone(),
                id,
            });
            let context = Box::into_raw(callback);
            let started = if let Some(handle) = Execution::start(
                source,
                key.as_deref(),
                app.as_deref(),
                execute_callback,
                context.cast(),
            ) {
                if let Some(running) = self.executions.lock().unwrap().running.get_mut(&id) {
                    if running.cancelled {
                        handle.cancel();
                    }
                    running.handle = Some(handle);
                }
                true
            } else {
                unsafe {
                    drop(Box::from_raw(context));
                }
                let mut executions = self.executions.lock().unwrap();
                executions.running.remove(&id);
                if executions.active == Some(id) {
                    executions.active = None;
                }
                false
            };
            let _ = started;
            return true;
        }
        if result.needs_kanji && dictionary_path().is_none() {
            self.track_key(keyval, state);
            return false;
        }
        if result.selection_count > 0 {
            let selection_count = result.selection_count as usize;
            let Some(prefix_text) = result.selection_prefix() else {
                return false;
            };
            let Some((scalars, characters, replacement)) = edit_plan(&line, &prefix_text) else {
                return false;
            };
            let Ok(prefix) = ibus_text(&commit_payload(&replacement, characters, terminal_delete))
            else {
                return false;
            };
            let selection = Selection {
                result,
                choices: vec![0; selection_count],
                current: 0,
            };
            if Self::delete_before(
                &emitter,
                if synthetic { characters } else { scalars },
                synthetic,
                terminal_delete,
            )
            .await
            .is_err()
            {
                return false;
            }
            if Self::commit_text(&emitter, prefix).await.is_err() {
                return false;
            }
            if show_selection(&emitter, &selection).await.is_err() {
                return false;
            }
            *self.selection.lock().unwrap() = Some(selection);
            *self.surrounding.lock().unwrap() = None;
            self.typed.lock().unwrap().set(&prefix_text);
            return true;
        }
        if result.needs_kanji && result.reading.as_deref().is_some_and(|s| !s.is_empty()) {
            let Some(dictionary) = dictionary_path() else {
                return false;
            };
            let Some(conversion) = Conversion::new(result.reading.as_deref().unwrap(), &dictionary)
            else {
                return false;
            };
            let Some((scalars, characters, replacement)) =
                edit_plan(&line, result.prefix.as_deref().unwrap_or(""))
            else {
                return false;
            };
            let Ok(prefix) = ibus_text(&commit_payload(&replacement, characters, terminal_delete))
            else {
                return false;
            };
            let Ok(preedit) = ibus_text_with_segments(&conversion.text(), &conversion.segments())
            else {
                return false;
            };
            if Self::delete_before(
                &emitter,
                if synthetic { characters } else { scalars },
                synthetic,
                terminal_delete,
            )
            .await
            .is_err()
            {
                return false;
            }
            if Self::commit_text(&emitter, prefix).await.is_err() {
                return false;
            }
            if Self::update_preedit_text(&emitter, preedit, 0, true, 1)
                .await
                .is_err()
            {
                return false;
            }
            *self.conversion.lock().unwrap() = Some(conversion);
            *self.surrounding.lock().unwrap() = None;
            self.typed
                .lock()
                .unwrap()
                .set(result.prefix.as_deref().unwrap_or(""));
            return true;
        }
        let Some(converted) = result.text.as_deref() else {
            return false;
        };
        let Some((scalars, characters, replacement)) = edit_plan(&line, converted) else {
            return false;
        };
        let Ok(value) = ibus_text(&commit_payload(&replacement, characters, terminal_delete))
        else {
            return false;
        };
        if Self::delete_before(
            &emitter,
            if synthetic { characters } else { scalars },
            synthetic,
            terminal_delete,
        )
        .await
        .is_err()
        {
            return false;
        }
        if Self::commit_text(&emitter, value).await.is_err() {
            return false;
        }
        *self.surrounding.lock().unwrap() = None;
        self.typed.lock().unwrap().set(converted);
        true
    }

    async fn focus_in(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let _ = Self::require_surrounding_text(&emitter).await;
    }
    async fn focus_in_id(
        &self,
        _path: &str,
        client: &str,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        *self.app.lock().unwrap() = client.split_once(':').map(|(_, app)| app.to_owned());
        let _ = Self::require_surrounding_text(&emitter).await;
    }
    async fn focus_out(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        self.finish_context(&emitter).await;
    }
    async fn focus_out_id(&self, _path: &str, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        self.finish_context(&emitter).await;
        *self.app.lock().unwrap() = None;
    }
    #[zbus(property)]
    fn focus_id(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn active_surrounding_text(&self) -> bool {
        false
    }
    fn enable(&self) {}
    fn disable(&self) {}
    async fn reset(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        self.finish_context(&emitter).await;
    }
    fn set_surrounding_text(&self, text: OwnedValue, cursor: u32, anchor: u32) {
        let Ok(Value::Structure(value)) = Value::try_from(&text) else {
            return;
        };
        let Some(Value::Str(text)) = value.fields().get(2) else {
            return;
        };
        *self.surrounding.lock().unwrap() = Some((text.to_string(), cursor, anchor));
    }
    fn set_capabilities(&self, _capabilities: u32) {}
    #[zbus(property)]
    fn set_content_type(&self, content_type: (u32, u32)) {
        *self.content_purpose.lock().unwrap() = content_type.0;
    }
    fn set_cursor_location(&self, _x: i32, _y: i32, _width: i32, _height: i32) {}

    #[zbus(signal)]
    async fn require_surrounding_text(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn delete_surrounding_text(
        emitter: &SignalEmitter<'_>,
        offset: i32,
        count: u32,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn commit_text(emitter: &SignalEmitter<'_>, text: OwnedValue) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn update_preedit_text(
        emitter: &SignalEmitter<'_>,
        text: OwnedValue,
        cursor: u32,
        visible: bool,
        mode: u32,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn update_lookup_table(
        emitter: &SignalEmitter<'_>,
        table: OwnedValue,
        visible: bool,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn hide_lookup_table(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn forward_key_event(
        emitter: &SignalEmitter<'_>,
        keyval: u32,
        keycode: u32,
        state: u32,
    ) -> zbus::Result<()>;
}
