pub use mlh_ibus::core;

#[path = "../src/ibus.rs"]
mod ibus;

use std::{sync::mpsc, thread, time::Duration};
use zbus::{
    blocking::{Connection, Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

fn assert_preedit_text(message: zbus::Message, expected: &str) {
    let (value, _, _, _): (OwnedValue, u32, bool, u32) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new(expected));
}

fn resolve_key(
    early: Result<zbus::Result<bool>, mpsc::RecvTimeoutError>,
    key_rx: &mpsc::Receiver<zbus::Result<bool>>,
) -> bool {
    match early {
        Ok(result) => result.unwrap(),
        Err(mpsc::RecvTimeoutError::Timeout) => key_rx
            .recv_timeout(Duration::from_secs(5))
            .unwrap()
            .unwrap(),
        Err(error) => panic!("key call failed: {error}"),
    }
}

#[test]
fn focus_out_does_not_leave_concurrent_input_in_next_focus() {
    let _service = Builder::session()
        .unwrap()
        .name("org.freedesktop.IBus.MlhFocusRaceTest")
        .unwrap()
        .serve_at("/org/freedesktop/IBus/Factory", ibus::Factory::default())
        .unwrap()
        .build()
        .unwrap();
    let connection = Connection::session().unwrap();
    let factory = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhFocusRaceTest",
        "/org/freedesktop/IBus/Factory",
        "org.freedesktop.IBus.Factory",
    )
    .unwrap();
    let path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
    let engine = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhFocusRaceTest",
        path,
        "org.freedesktop.IBus.Engine",
    )
    .unwrap();
    let other_path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
    let other_engine = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhFocusRaceTest",
        other_path,
        "org.freedesktop.IBus.Engine",
    )
    .unwrap();
    engine
        .call::<_, _, ()>("FocusInId", &("/test", "SDL2_Application"))
        .unwrap();
    let mut preedits = engine.receive_signal("UpdatePreeditText").unwrap();
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x61_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();

    let (entered_tx, entered_rx) = mpsc::channel();
    let (resume_tx, resume_rx) = async_channel::bounded(1);
    *ibus::FOCUS_FLUSH_HOOK.lock().unwrap() = Some((entered_tx, resume_rx));
    thread::scope(|scope| {
        let focus_out = scope.spawn(|| engine.call::<_, _, ()>("FocusOutId", &("/test",)));
        entered_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        let (other_tx, other_rx) = mpsc::channel();
        let other = scope.spawn(move || {
            let result =
                other_engine.call::<_, _, ()>("FocusInId", &("/other", "SDL2_Application"));
            other_tx.send(result).unwrap();
        });
        let other_finished = other_rx.recv_timeout(Duration::from_secs(2));
        if other_finished.is_err() {
            resume_tx.send_blocking(()).unwrap();
            focus_out.join().unwrap().unwrap();
            other.join().unwrap();
            panic!("an unrelated engine was blocked by focus out");
        }
        other_finished.unwrap().unwrap();
        other.join().unwrap();
        let (key_tx, key_rx) = mpsc::channel();
        let engine_ref = &engine;
        let key = scope.spawn(move || {
            let result =
                engine_ref.call::<_, _, bool>("ProcessKeyEvent", &(0x62_u32, 0_u32, 0_u32));
            key_tx.send(result).unwrap();
        });
        let early = key_rx.recv_timeout(Duration::from_secs(2));
        resume_tx.send_blocking(()).unwrap();
        focus_out.join().unwrap().unwrap();
        let handled = resolve_key(early, &key_rx);
        key.join().unwrap();
        assert!(
            !handled,
            "a key after focus out must not be consumed by the old context"
        );
    });
    preedits.next().unwrap();
    engine
        .call::<_, _, ()>("FocusInId", &("/test", "SDL2_Application"))
        .unwrap();
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x63_u32, 0_u32, 0_u32))
            .unwrap()
    );
    assert_preedit_text(preedits.next().unwrap(), "c");

    let (entered_tx, entered_rx) = mpsc::channel();
    let (resume_tx, resume_rx) = async_channel::bounded(1);
    *ibus::FOCUS_FLUSH_HOOK.lock().unwrap() = Some((entered_tx, resume_rx));
    thread::scope(|scope| {
        let focus_out = scope.spawn(|| engine.call::<_, _, ()>("FocusOutId", &("/test",)));
        entered_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        let (key_tx, key_rx) = mpsc::channel();
        let engine_ref = &engine;
        let new_focus = scope.spawn(move || {
            engine_ref
                .call::<_, _, ()>("FocusInId", &("/test", "SDL2_Application"))
                .unwrap();
            let result =
                engine_ref.call::<_, _, bool>("ProcessKeyEvent", &(0x62_u32, 0_u32, 0_u32));
            key_tx.send(result).unwrap();
        });
        let early = key_rx.recv_timeout(Duration::from_secs(2));
        resume_tx.send_blocking(()).unwrap();
        focus_out.join().unwrap().unwrap();
        let handled = resolve_key(early, &key_rx);
        new_focus.join().unwrap();
        assert!(handled, "the new focus must accept its key");
    });
    preedits.next().unwrap();
    preedits.next().unwrap();
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x63_u32, 0_u32, 0_u32))
            .unwrap()
    );
    assert_preedit_text(preedits.next().unwrap(), "bc");
}
