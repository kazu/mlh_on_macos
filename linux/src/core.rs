use std::ffi::{CStr, CString, c_char, c_void};

unsafe extern "C" {
    fn mlh_engine_new(dictionary: *const c_char, app: *const c_char) -> *mut c_void;
    fn mlh_engine_free(engine: *mut c_void);
    fn mlh_engine_run(engine: *mut c_void, text: *const c_char) -> *mut c_void;
    fn mlh_result_free(result: *mut c_void);
    fn mlh_result_kind(result: *mut c_void) -> i32;
    fn mlh_result_text(result: *mut c_void) -> *mut c_char;
    fn mlh_result_henkan_begin(result: *mut c_void) -> isize;
    fn mlh_result_needs_kanji(result: *mut c_void) -> bool;
    fn mlh_result_selection_count(result: *mut c_void) -> isize;
    fn mlh_result_selection_candidates(result: *mut c_void, selection: isize) -> isize;
    fn mlh_result_selection_candidate(
        result: *mut c_void,
        selection: isize,
        candidate: isize,
    ) -> *mut c_char;
    fn mlh_result_render_part(
        result: *mut c_void,
        choices: *const isize,
        count: isize,
        suffix: bool,
    ) -> *mut c_char;
    fn mlh_result_selection_prefix(result: *mut c_void) -> *mut c_char;
    fn mlh_result_render_marked(
        result: *mut c_void,
        choices: *const isize,
        count: isize,
        before_kanji: bool,
    ) -> *mut c_char;
    fn mlh_result_execute_part(result: *mut c_void, part: i32) -> *mut c_char;
    fn mlh_result_part(result: *mut c_void, suffix: bool) -> *mut c_char;
    fn mlh_string_free(text: *mut c_char);
    fn mlh_typed_new() -> *mut c_void;
    fn mlh_typed_free(typed: *mut c_void);
    fn mlh_typed_append(typed: *mut c_void, text: *const c_char);
    fn mlh_typed_set(typed: *mut c_void, text: *const c_char);
    fn mlh_typed_remove(typed: *mut c_void);
    fn mlh_typed_reset(typed: *mut c_void);
    fn mlh_typed_text(typed: *mut c_void) -> *mut c_char;
    fn mlh_edit_plan(
        old: *const c_char,
        new: *const c_char,
        scalars: *mut isize,
        characters: *mut isize,
    ) -> *mut c_char;
    fn mlh_conversion_new(source: *const c_char, dictionary: *const c_char) -> *mut c_void;
    fn mlh_conversion_free(conversion: *mut c_void);
    fn mlh_conversion_text(conversion: *mut c_void) -> *mut c_char;
    fn mlh_conversion_reading(conversion: *mut c_void) -> *mut c_char;
    fn mlh_conversion_step(conversion: *mut c_void, action: i32);
    fn mlh_conversion_candidate_count(conversion: *mut c_void) -> isize;
    fn mlh_conversion_candidate_index(conversion: *mut c_void) -> isize;
    fn mlh_conversion_candidate(conversion: *mut c_void, index: isize) -> *mut c_char;
    fn mlh_conversion_select(conversion: *mut c_void, index: isize);
    fn mlh_conversion_segment_count(conversion: *mut c_void) -> isize;
    fn mlh_conversion_segment_length(conversion: *mut c_void, index: isize) -> isize;
    fn mlh_conversion_segment_current(conversion: *mut c_void) -> isize;
    fn mlh_run_main_loop() -> !;
    fn mlh_execute_start(
        source: *const c_char,
        key: *const c_char,
        app: *const c_char,
        callback: extern "C" fn(*mut c_void, *const c_char, i32),
        context: *mut c_void,
    ) -> *mut c_void;
    fn mlh_execute_cancel(execution: *mut c_void);
    fn mlh_execute_free(execution: *mut c_void);
}

pub struct Engine(*mut c_void);

pub struct TypedBuffer(*mut c_void);

// Access to each buffer is serialized by its input context.
unsafe impl Send for TypedBuffer {}

impl Default for TypedBuffer {
    fn default() -> Self {
        Self(unsafe { mlh_typed_new() })
    }
}

impl TypedBuffer {
    pub fn append(&mut self, text: &str) {
        if let Ok(text) = CString::new(text) {
            unsafe { mlh_typed_append(self.0, text.as_ptr()) }
        }
    }
    pub fn set(&mut self, text: &str) {
        if let Ok(text) = CString::new(text) {
            unsafe { mlh_typed_set(self.0, text.as_ptr()) }
        }
    }
    pub fn remove(&mut self) {
        unsafe { mlh_typed_remove(self.0) }
    }
    pub fn reset(&mut self) {
        unsafe { mlh_typed_reset(self.0) }
    }
    pub fn text(&self) -> String {
        unsafe { take_string(mlh_typed_text(self.0)) }.unwrap_or_default()
    }
}

impl Drop for TypedBuffer {
    fn drop(&mut self) {
        unsafe { mlh_typed_free(self.0) }
    }
}

#[derive(Debug)]
pub struct ResultValue {
    raw: *mut c_void,
    pub kind: i32,
    pub text: Option<String>,
    pub henkan_begin: isize,
    pub needs_kanji: bool,
    pub selection_count: isize,
    pub prefix: Option<String>,
    pub reading: Option<String>,
    pub execute: Option<(String, String, Option<String>)>,
}

// IBus serializes access to each result through its context mutex.
unsafe impl Send for ResultValue {}
// The wrapped Swift result is immutable after creation.
unsafe impl Sync for ResultValue {}

impl ResultValue {
    pub fn candidates(&self, selection: usize) -> Vec<String> {
        let count = unsafe { mlh_result_selection_candidates(self.raw, selection as isize) };
        (0..count)
            .filter_map(|i| unsafe {
                take_string(mlh_result_selection_candidate(
                    self.raw,
                    selection as isize,
                    i,
                ))
            })
            .collect()
    }

    pub fn render_part(&self, choices: &[isize], suffix: bool) -> Option<String> {
        unsafe {
            take_string(mlh_result_render_part(
                self.raw,
                choices.as_ptr(),
                choices.len() as isize,
                suffix,
            ))
        }
    }

    pub fn selection_prefix(&self) -> Option<String> {
        unsafe { take_string(mlh_result_selection_prefix(self.raw)) }
    }

    pub fn render_marked(&self, choices: &[isize], before_kanji: bool) -> Option<String> {
        unsafe {
            take_string(mlh_result_render_marked(
                self.raw,
                choices.as_ptr(),
                choices.len() as isize,
                before_kanji,
            ))
        }
    }
}

impl Drop for ResultValue {
    fn drop(&mut self) {
        unsafe { mlh_result_free(self.raw) }
    }
}

unsafe fn take_string(value: *mut c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    let text = unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .into_owned();
    unsafe { mlh_string_free(value) };
    Some(text)
}

impl Engine {
    pub fn new() -> Self {
        Self::for_app(None)
    }

    pub fn for_app(app: Option<&str>) -> Self {
        let path = std::env::var_os("MLH_USER_DICTIONARY").or_else(|| {
            let base = std::env::var_os("XDG_CONFIG_HOME")
                .map(std::path::PathBuf::from)
                .or_else(|| {
                    std::env::var_os("HOME")
                        .map(|home| std::path::PathBuf::from(home).join(".config"))
                })?;
            Some(base.join("mlh/userdict.txt").into_os_string())
        });
        let path = path.and_then(|p| CString::new(p.as_encoded_bytes()).ok());
        let app = app.and_then(|app| CString::new(app).ok());
        Self(unsafe {
            mlh_engine_new(
                path.as_ref().map_or(std::ptr::null(), |p| p.as_ptr()),
                app.as_ref().map_or(std::ptr::null(), |p| p.as_ptr()),
            )
        })
    }

    pub fn run(&mut self, text: &str) -> Option<ResultValue> {
        let text = CString::new(text).ok()?;
        let result = unsafe { mlh_engine_run(self.0, text.as_ptr()) };
        let kind = unsafe { mlh_result_kind(result) };
        let text = unsafe { take_string(mlh_result_text(result)) };
        let value = ResultValue {
            raw: result,
            kind,
            text,
            henkan_begin: unsafe { mlh_result_henkan_begin(result) },
            needs_kanji: unsafe { mlh_result_needs_kanji(result) },
            selection_count: unsafe { mlh_result_selection_count(result) },
            prefix: unsafe { take_string(mlh_result_part(result, false)) },
            reading: unsafe { take_string(mlh_result_part(result, true)) },
            execute: unsafe { take_string(mlh_result_execute_part(result, 0)) }.map(|prefix| {
                let source =
                    unsafe { take_string(mlh_result_execute_part(result, 1)) }.unwrap_or_default();
                let key = unsafe { take_string(mlh_result_execute_part(result, 2)) };
                (prefix, source, key)
            }),
        };
        Some(value)
    }
}

pub fn run_main_loop() -> ! {
    unsafe { mlh_run_main_loop() }
}

pub fn edit_plan(old: &str, new: &str) -> Option<(u32, u32, String)> {
    let old = CString::new(old).ok()?;
    let new = CString::new(new).ok()?;
    let mut scalars = 0;
    let mut characters = 0;
    let text = unsafe {
        take_string(mlh_edit_plan(
            old.as_ptr(),
            new.as_ptr(),
            &mut scalars,
            &mut characters,
        ))
    }?;
    Some((scalars.try_into().ok()?, characters.try_into().ok()?, text))
}

pub struct Execution(*mut c_void);
unsafe impl Send for Execution {}

impl Execution {
    pub fn start(
        source: &str,
        key: Option<&str>,
        app: Option<&str>,
        callback: extern "C" fn(*mut c_void, *const c_char, i32),
        context: *mut c_void,
    ) -> Option<Self> {
        let source = CString::new(source).ok()?;
        let key = key.map(CString::new).transpose().ok()?;
        let app = app.map(CString::new).transpose().ok()?;
        let ptr = unsafe {
            mlh_execute_start(
                source.as_ptr(),
                key.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
                app.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
                callback,
                context,
            )
        };
        (!ptr.is_null()).then_some(Self(ptr))
    }
    pub fn cancel(&self) {
        unsafe { mlh_execute_cancel(self.0) }
    }
}

impl Drop for Execution {
    fn drop(&mut self) {
        unsafe { mlh_execute_free(self.0) }
    }
}

pub struct Conversion(*mut c_void);

// IBus serializes access to a conversion through its context mutex.
unsafe impl Send for Conversion {}

impl Conversion {
    pub fn new(source: &str, dictionary: &str) -> Option<Self> {
        let source = CString::new(source).ok()?;
        let dictionary = CString::new(dictionary).ok()?;
        Some(Self(unsafe {
            mlh_conversion_new(source.as_ptr(), dictionary.as_ptr())
        }))
    }

    pub fn text(&self) -> String {
        unsafe { take_string(mlh_conversion_text(self.0)) }.unwrap_or_default()
    }

    pub fn reading(&self) -> String {
        unsafe { take_string(mlh_conversion_reading(self.0)) }.unwrap_or_default()
    }

    pub fn step(&mut self, action: i32) {
        unsafe { mlh_conversion_step(self.0, action) };
    }

    pub fn candidates(&self) -> (Vec<String>, usize) {
        let count = unsafe { mlh_conversion_candidate_count(self.0) };
        let index = unsafe { mlh_conversion_candidate_index(self.0) };
        let candidates = (0..count)
            .filter_map(|i| unsafe { take_string(mlh_conversion_candidate(self.0, i)) })
            .collect();
        (candidates, index as usize)
    }

    pub fn select(&mut self, index: usize) {
        unsafe { mlh_conversion_select(self.0, index as isize) };
    }

    pub fn segments(&self) -> Vec<(u32, u32, bool)> {
        let count = unsafe { mlh_conversion_segment_count(self.0) };
        let current = unsafe { mlh_conversion_segment_current(self.0) };
        let mut start = 0;
        (0..count)
            .map(|i| {
                let end = start + (unsafe { mlh_conversion_segment_length(self.0, i) }) as u32;
                let span = (start, end, i == current);
                start = end;
                span
            })
            .collect()
    }
}

impl Drop for Conversion {
    fn drop(&mut self) {
        unsafe { mlh_conversion_free(self.0) };
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        unsafe { mlh_engine_free(self.0) };
    }
}
