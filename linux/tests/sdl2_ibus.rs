mod support;

use support::assert_commit_text;
use zbus::{
    blocking::{Connection, Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue},
};

fn enter_preedit_keys(
    engine: &Proxy<'_>,
    preedits: &mut zbus::blocking::proxy::SignalIterator<'_>,
    keys: impl IntoIterator<Item = u32>,
) {
    for key in keys {
        assert!(
            engine
                .call::<_, _, bool>("ProcessKeyEvent", &(key, 0_u32, 0_u32))
                .unwrap(),
            "{key} must remain in preedit"
        );
        preedits.next().unwrap();
    }
}

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
    assert!(
        !engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x01000020_u32, 0_u32, 0_u32))
            .unwrap()
    );
    enter_preedit_keys(&engine, &mut preedits, "nihongof/".chars().map(u32::from));
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    let cleared = preedits.next().unwrap();
    let (_, _, visible, _): (OwnedValue, u32, bool, u32) = cleared.body().deserialize().unwrap();
    assert!(!visible);
    assert_commit_text(commits.next().unwrap(), "にほんご");

    enter_preedit_keys(&engine, &mut preedits, "abc".chars().map(u32::from));
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
    assert_commit_text(commits.next().unwrap(), "ab ");

    enter_preedit_keys(&engine, &mut preedits, [0x61_u32, 0x01000301]);
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0xff08_u32, 0_u32, 0_u32))
            .unwrap()
    );
    let (_, _, visible, _): (OwnedValue, u32, bool, u32) =
        preedits.next().unwrap().body().deserialize().unwrap();
    assert!(!visible, "backspace removes the entire grapheme");

    enter_preedit_keys(&engine, &mut preedits, "nihongof/".chars().map(u32::from));
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    assert_commit_text(commits.next().unwrap(), "にほんご");
    enter_preedit_keys(
        &engine,
        &mut preedits,
        "abc nihongof/".chars().map(u32::from),
    );
    assert!(
        engine
            .call::<_, _, bool>("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
            .unwrap()
    );
    preedits.next().unwrap();
    assert_commit_text(commits.next().unwrap(), "abc にほんご");
}
