use zbus::{
    blocking::{Connection, Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

#[test]
fn converts_sdl2_preedit_without_leaving_romaji() {
    let _service = Builder::session()
        .unwrap()
        .name("org.freedesktop.IBus.MlhSdl2Test")
        .unwrap()
        .serve_at(
            "/org/freedesktop/IBus/Factory",
            mlh_ibus::ibus::Factory::default(),
        )
        .unwrap()
        .build()
        .unwrap();
    let connection = Connection::session().unwrap();
    let factory = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhSdl2Test",
        "/org/freedesktop/IBus/Factory",
        "org.freedesktop.IBus.Factory",
    )
    .unwrap();
    let path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
    let engine = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhSdl2Test",
        path,
        "org.freedesktop.IBus.Engine",
    )
    .unwrap();
    engine
        .call::<_, _, ()>("FocusInId", &("/test", "SDL2_Application"))
        .unwrap();
    engine
        .call::<_, _, ()>("SetCapabilities", &(9_u32,))
        .unwrap();
    let mut preedits = engine.receive_signal("UpdatePreeditText").unwrap();
    let mut commits = engine.receive_signal("CommitText").unwrap();
    for c in "nihongof/".chars() {
        let handled: bool = engine
            .call("ProcessKeyEvent", &(c as u32, 0_u32, 0_u32))
            .unwrap();
        assert!(handled, "{c} must remain in preedit");
        preedits.next().unwrap();
    }
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    let cleared = preedits.next().unwrap();
    let (_, _, visible, _): (OwnedValue, u32, bool, u32) = cleared.body().deserialize().unwrap();
    assert!(!visible);
    let message = commits.next().unwrap();
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("にほんご"));

    for c in "abc".chars() {
        assert!(
            engine
                .call::<_, _, bool>("ProcessKeyEvent", &(c as u32, 0_u32, 0_u32))
                .unwrap()
        );
        preedits.next().unwrap();
    }
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff08_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    assert!(
        !engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff0d_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    let (value,): (OwnedValue,) = commits.next().unwrap().body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("ab "));

    for key in [0x61_u32, 0x01000301] {
        assert!(
            engine
                .call::<_, _, bool>("ProcessKeyEvent", &(key, 0_u32, 0_u32))
                .unwrap()
        );
        preedits.next().unwrap();
    }
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff08_u32, 0_u32, 0_u32))
            .unwrap()
    );
    let (_, _, visible, _): (OwnedValue, u32, bool, u32) =
        preedits.next().unwrap().body().deserialize().unwrap();
    assert!(!visible, "backspace removes the entire grapheme");

    for c in "nihongof/".chars() {
        assert!(
            engine
                .call::<_, _, bool>("ProcessKeyEvent", &(c as u32, 0_u32, 0_u32))
                .unwrap()
        );
        preedits.next().unwrap();
    }
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    let (value,): (OwnedValue,) = commits.next().unwrap().body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("にほんご"));
    for c in "abc nihongof/".chars() {
        assert!(
            engine
                .call::<_, _, bool>("ProcessKeyEvent", &(c as u32, 0_u32, 0_u32))
                .unwrap()
        );
        preedits.next().unwrap();
    }
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    let (value,): (OwnedValue,) = commits.next().unwrap().body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new("abc にほんご"));
}
