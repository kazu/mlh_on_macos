use std::ffi::{CStr, c_char, c_void};
use std::io::Write;
use std::time::{Duration, Instant};

#[link(name = "gtk-4")]
unsafe extern "C" {
    fn gtk_init();
    fn gtk_window_new() -> *mut c_void;
    fn gtk_window_set_title(window: *mut c_void, title: *const c_char);
    fn gtk_entry_new() -> *mut c_void;
    fn gtk_window_set_child(window: *mut c_void, child: *mut c_void);
    fn gtk_window_present(window: *mut c_void);
    fn gtk_widget_grab_focus(widget: *mut c_void) -> i32;
    fn gtk_window_is_active(window: *mut c_void) -> i32;
    fn gtk_editable_get_text(editable: *mut c_void) -> *const c_char;
}

#[link(name = "glib-2.0")]
unsafe extern "C" {
    fn g_main_context_iteration(context: *mut c_void, may_block: i32) -> i32;
}

fn main() {
    let expected = std::env::var("MLH_EXPECT").unwrap_or_else(|_| "にほんご".to_owned());
    let focus_test = std::env::var_os("MLH_FOCUS_TEST").is_some();
    let focus_marker = std::env::var_os("MLH_FOCUS_MARKER");
    unsafe {
        gtk_init();
        let window = gtk_window_new();
        let entry = gtk_entry_new();
        gtk_window_set_child(window, entry);
        if focus_test {
            gtk_window_set_title(window, c"mlh-first".as_ptr());
            let other = gtk_window_new();
            gtk_window_set_title(other, c"mlh-second".as_ptr());
            gtk_window_set_child(other, gtk_entry_new());
            gtk_window_present(other);
        }
        gtk_window_present(window);
        gtk_widget_grab_focus(entry);
        let deadline = Instant::now() + Duration::from_secs(15);
        let mut ready = false;
        let mut saw_trigger = false;
        let mut saw_unfocus = false;
        while Instant::now() < deadline {
            while g_main_context_iteration(std::ptr::null_mut(), 0) != 0 {}
            if !ready && gtk_window_is_active(window) != 0 {
                println!("ready");
                std::io::stdout().flush().unwrap();
                ready = true;
            }
            if ready && gtk_window_is_active(window) == 0 { saw_unfocus = true; }
            let text = CStr::from_ptr(gtk_editable_get_text(entry)).to_string_lossy();
            if text.ends_with('/') { saw_trigger = true; }
            let switched = focus_marker.as_ref().is_some_and(|path| std::path::Path::new(path).exists());
            if saw_trigger && (!focus_test || (saw_unfocus && switched)) && text == expected {
                println!("{text}");
                return;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        eprintln!("unexpected text: {}", CStr::from_ptr(gtk_editable_get_text(entry)).to_string_lossy());
        std::process::exit(1);
    }
}
