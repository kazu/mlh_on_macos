mod support;

use std::collections::HashMap;
use support::assert_commit_text;
use zbus::{
    blocking::{Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

fn send_command(context: &Proxy<'_>, command: &[u8]) {
    for key in command.iter().copied().chain([b' ']) {
        assert!(
            context
                .call::<_, _, bool>("ProcessKeyEvent", &(u32::from(key), 0_u32, 0_u32))
                .unwrap()
        );
    }
}

fn send_q_press_and_release(context: &Proxy<'_>) {
    for state in [0_u32, 1 << 30] {
        assert!(
            context
                .call::<_, _, bool>("ProcessKeyEvent", &(0x71_u32, 24_u32, state))
                .unwrap()
        );
    }
}

#[test]
#[ignore = "requires the isolated IBus daemon from isolated-ibus.sh"]
fn converts_sdl2_input_context() {
    let address = std::env::var("IBUS_TEST_ADDRESS").unwrap();
    let connection = Builder::address(mlh_ibus::ibus_address(&address).unwrap())
        .unwrap()
        .build()
        .unwrap();
    let bus = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        "/org/freedesktop/IBus",
        "org.freedesktop.IBus",
    )
    .unwrap();
    let path: OwnedObjectPath = bus
        .call("CreateInputContext", &("SDL2_Application",))
        .unwrap();
    let context = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        path,
        "org.freedesktop.IBus.InputContext",
    )
    .unwrap();
    context
        .call::<_, _, ()>("SetCapabilities", &(0x09_u32,))
        .unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut preedits = context.receive_signal("UpdatePreeditText").unwrap();
    for key in b"nihongo/" {
        assert!(
            context
                .call::<_, _, bool>("ProcessKeyEvent", &(u32::from(*key), 0_u32, 0_u32))
                .unwrap()
        );
        preedits.next().unwrap();
    }
    assert!(
        context
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    loop {
        let message = preedits.next().unwrap();
        let (value, _, visible): (OwnedValue, u32, bool) = message.body().deserialize().unwrap();
        if visible {
            let Value::Structure(value) = Value::try_from(&value).unwrap() else {
                panic!("expected IBusText")
            };
            assert_eq!(value.fields()[2], Value::new("日本語"));
            break;
        }
    }
    let mut commits = context.receive_signal("CommitText").unwrap();
    assert!(
        context
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff0d_u32, 0_u32, 0_u32))
            .unwrap()
    );
    assert_commit_text(commits.next().unwrap(), "日本語");
    context.call::<_, _, ()>("FocusOut", &()).unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut commits = context.receive_signal("CommitText").unwrap();
    send_command(&context, b"hello3x/");
    assert_commit_text(commits.next().unwrap(), "ABC");
    context.call::<_, _, ()>("FocusOut", &()).unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut commits = context.receive_signal("CommitText").unwrap();
    send_command(&context, b"hello7x/");
    send_q_press_and_release(&context);
    let release = std::path::PathBuf::from(std::env::var_os("XDG_CONFIG_HOME").unwrap())
        .join("mlh/queue-release");
    std::fs::write(&release, "").unwrap();
    for expected in ["HELLO", "q"] {
        assert_commit_text(commits.next().unwrap(), expected);
    }
    std::fs::remove_file(release).unwrap();
    context.call::<_, _, ()>("FocusOut", &()).unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut commits = context.receive_signal("CommitText").unwrap();
    send_command(&context, b"hello2x/");
    send_q_press_and_release(&context);
    assert!(
        context
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff1b_u32, 0_u32, 0_u32))
            .unwrap()
    );
    for expected in ["hello", "q"] {
        assert_commit_text(commits.next().unwrap(), expected);
    }
    context.call::<_, _, ()>("FocusOut", &()).unwrap();
}

#[test]
#[ignore = "requires the isolated IBus daemon from isolated-ibus.sh"]
fn converts_through_ibus_input_context() {
    let address = std::env::var("IBUS_TEST_ADDRESS").unwrap();
    let connection = Builder::address(mlh_ibus::ibus_address(&address).unwrap())
        .unwrap()
        .build()
        .unwrap();
    let bus = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        "/org/freedesktop/IBus",
        "org.freedesktop.IBus",
    )
    .unwrap();
    let path: OwnedObjectPath = bus
        .call("CreateInputContext", &("gtk4-im:mlh-test",))
        .unwrap();
    let context = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        path,
        "org.freedesktop.IBus.InputContext",
    )
    .unwrap();
    context
        .call::<_, _, ()>("SetCapabilities", &(0x2d_u32,))
        .unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut deletions = context.receive_signal("DeleteSurroundingText").unwrap();
    let mut commits = context.receive_signal("CommitText").unwrap();
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "nihongof/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 9_u32, 9_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    assert_eq!(
        deletions
            .next()
            .unwrap()
            .body()
            .deserialize::<(i32, u32)>()
            .unwrap(),
        (-9, 9)
    );
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("にほんご"));

    let mut preedits = context.receive_signal("UpdatePreeditText").unwrap();
    let mut lookups = context.receive_signal("UpdateLookupTable").unwrap();
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "nihongo/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    let preedit = preedits.next().unwrap();
    let (text, _, visible): (OwnedValue, u32, bool) = preedit.body().deserialize().unwrap();
    assert!(visible);
    let Value::Structure(text) = Value::try_from(&text).unwrap() else {
        panic!("expected IBusText")
    };
    assert_ne!(text.fields()[2], Value::new(""));
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    let lookup = lookups.next().unwrap();
    let (_, visible): (OwnedValue, bool) = lookup.body().deserialize().unwrap();
    assert!(visible);
    let handled: bool = context
        .call("ProcessKeyEvent", &(0xff0d_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    preedits.next().unwrap();
    let cleared = preedits.next().unwrap();
    let (_, _, visible): (OwnedValue, u32, bool) = cleared.body().deserialize().unwrap();
    assert!(
        !visible,
        "preedit must be cleared before committing conversion"
    );
    commits.next().unwrap();
    commits.next().unwrap();

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "prefix imed/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 12_u32, 12_u32))
        .unwrap();
    let mut selection_deletions = context.receive_signal("DeleteSurroundingText").unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    assert_eq!(
        selection_deletions
            .next()
            .unwrap()
            .body()
            .deserialize::<(i32, u32)>()
            .unwrap(),
        (-5, 5)
    );
    commits.next().unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x2f_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("input method"));

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello1x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("HELLO"));

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello2x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let mut cancelled_preedit = context.receive_signal("UpdatePreeditText").unwrap();
    let mut cancelled_keys = context.receive_signal("ForwardKeyEvent").unwrap();
    for state in [0_u32, 1 << 30] {
        let handled: bool = context
            .call("ProcessKeyEvent", &(0x71_u32, 24_u32, state))
            .unwrap();
        assert!(handled);
    }
    let handled: bool = context
        .call("ProcessKeyEvent", &(0xff1b_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    let message = cancelled_preedit.next().unwrap();
    let (_, _, visible): (OwnedValue, u32, bool) = message.body().deserialize().unwrap();
    assert!(!visible);
    for state in [0_u32, 1 << 30] {
        let key: (u32, u32, u32) = cancelled_keys.next().unwrap().body().deserialize().unwrap();
        assert_eq!(key, (0x71, 24, state));
    }
    drop(cancelled_keys);

    let mut progress = context.receive_signal("UpdatePreeditText").unwrap();
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello3x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let partial = progress.next().unwrap();
    let (value, _, _): (OwnedValue, u32, bool) = partial.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("AB"));
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("ABC"));

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello6x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("mlh-test"));

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hellox/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 7_u32, 7_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("ABC"));

    let mut queued = context.receive_signal("ForwardKeyEvent").unwrap();
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello7x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    for _ in 0..35 {
        for state in [0_u32, 1 << 30] {
            let handled: bool = context
                .call("ProcessKeyEvent", &(0x71_u32, 24_u32, state))
                .unwrap();
            assert!(handled);
        }
    }
    let release = std::path::PathBuf::from(std::env::var_os("XDG_CONFIG_HOME").unwrap())
        .join("mlh/queue-release");
    std::fs::write(release, "").unwrap();
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("HELLO"));
    for _ in 0..35 {
        let down: (u32, u32, u32) = queued.next().unwrap().body().deserialize().unwrap();
        let up: (u32, u32, u32) = queued.next().unwrap().body().deserialize().unwrap();
        assert_eq!((down.0, up.0), (0x71, 0x71));
        assert_eq!(down.2 & (1 << 30), 0);
        assert_ne!(up.2 & (1 << 30), 0);
    }

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let mut failure_preedit = context.receive_signal("UpdatePreeditText").unwrap();
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "hello5x/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    let message = failure_preedit.next().unwrap();
    let (_, _, visible): (OwnedValue, u32, bool) = message.body().deserialize().unwrap();
    assert!(!visible);

    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "nihongo/",
        attributes,
    ));
    context
        .call::<_, _, ()>("SetSurroundingText", &(text, 8_u32, 8_u32))
        .unwrap();
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    commits.next().unwrap();
    context.call::<_, _, ()>("Reset", &()).unwrap();
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("日本語"));

    context.call::<_, _, ()>("FocusOut", &()).unwrap();
    context
        .call::<_, _, ()>("SetCapabilities", &(0x0d_u32,))
        .unwrap();
    context.call::<_, _, ()>("FocusIn", &()).unwrap();
    let mut forwarded = context.receive_signal("ForwardKeyEvent").unwrap();
    for key in b"nihongof/" {
        let handled: bool = context
            .call("ProcessKeyEvent", &(u32::from(*key), 0_u32, 0_u32))
            .unwrap();
        assert!(!handled);
    }
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled, "conversion should work without surrounding text");
    for _ in 0..9 {
        let down: (u32, u32, u32) = forwarded.next().unwrap().body().deserialize().unwrap();
        let up: (u32, u32, u32) = forwarded.next().unwrap().body().deserialize().unwrap();
        assert_eq!(down.0, 0xff08);
        assert_eq!(up.0, 0xff08);
        assert_eq!((down.1, up.1), (14, 14));
        assert_eq!(down.2 & (1 << 30), 0);
        assert_ne!(up.2 & (1 << 30), 0);
    }
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("にほんご"));
    for key in b" nihongof/" {
        let handled: bool = context
            .call("ProcessKeyEvent", &(u32::from(*key), 0_u32, 0_u32))
            .unwrap();
        assert!(!handled);
    }
    let handled: bool = context
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    for _ in 0..9 {
        let down: (u32, u32, u32) = forwarded.next().unwrap().body().deserialize().unwrap();
        let up: (u32, u32, u32) = forwarded.next().unwrap().body().deserialize().unwrap();
        assert_eq!((down.0, up.0), (0xff08, 0xff08));
    }
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("にほんご"));

    let source_path: OwnedObjectPath = bus
        .call("CreateInputContext", &("gtk4-im:source",))
        .unwrap();
    let source = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        source_path,
        "org.freedesktop.IBus.InputContext",
    )
    .unwrap();
    let mut required = source.receive_signal("RequireSurroundingText").unwrap();
    let mut source_commits = source.receive_signal("CommitText").unwrap();
    let mut source_preedits = source.receive_signal("UpdatePreeditText").unwrap();
    source
        .call::<_, _, ()>("SetCapabilities", &(0x2d_u32,))
        .unwrap();
    source.call::<_, _, ()>("FocusIn", &()).unwrap();
    required.next().unwrap();
    for key in b"nihongo/" {
        let handled: bool = source
            .call("ProcessKeyEvent", &(u32::from(*key), 0_u32, 0_u32))
            .unwrap();
        assert!(!handled);
    }
    let handled: bool = source
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
    source_commits.next().unwrap();
    loop {
        let message = source_preedits.next().unwrap();
        let (_, _, visible): (OwnedValue, u32, bool) = message.body().deserialize().unwrap();
        if visible {
            break;
        }
    }
    let other_path: OwnedObjectPath = bus.call("CreateInputContext", &("gtk4-im:other",)).unwrap();
    let other = Proxy::new(
        &connection,
        "org.freedesktop.IBus",
        other_path,
        "org.freedesktop.IBus.InputContext",
    )
    .unwrap();
    other
        .call::<_, _, ()>("SetCapabilities", &(0x2d_u32,))
        .unwrap();
    source.call::<_, _, ()>("FocusOut", &()).unwrap();
    other.call::<_, _, ()>("FocusIn", &()).unwrap();
    let message = source_commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("日本語"));

    let factory = Proxy::new(
        &connection,
        "org.freedesktop.IBus.Mlh",
        "/org/freedesktop/IBus/Factory",
        "org.freedesktop.IBus.Factory",
    )
    .unwrap();
    let engine_path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
    let service = Proxy::new(
        &connection,
        "org.freedesktop.IBus.Mlh",
        engine_path.clone(),
        "org.freedesktop.IBus.Service",
    )
    .unwrap();
    service.call::<_, _, ()>("Destroy", &()).unwrap();
    let engine = Proxy::new(
        &connection,
        "org.freedesktop.IBus.Mlh",
        engine_path,
        "org.freedesktop.IBus.Engine",
    )
    .unwrap();
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x71_u32, 24_u32, 0_u32))
            .is_err()
    );
}
