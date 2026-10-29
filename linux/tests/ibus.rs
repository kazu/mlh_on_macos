use std::collections::HashMap;
use zbus::{
    blocking::{Connection, Proxy, connection::Builder},
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

#[test]
fn replaces_surrounding_text_when_space_triggers_conversion() {
    let _service = Builder::session()
        .unwrap()
        .name("org.freedesktop.IBus.MlhTest")
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
        "org.freedesktop.IBus.MlhTest",
        "/org/freedesktop/IBus/Factory",
        "org.freedesktop.IBus.Factory",
    )
    .unwrap();
    let path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
    let engine = Proxy::new(
        &connection,
        "org.freedesktop.IBus.MlhTest",
        path,
        "org.freedesktop.IBus.Engine",
    )
    .unwrap();
    let mut deletions = engine.receive_signal("DeleteSurroundingText").unwrap();
    let mut commits = engine.receive_signal("CommitText").unwrap();
    let attributes = (
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    );
    let attributes = Value::new(attributes);
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "nihongof/",
        attributes,
    ));
    engine
        .call::<_, _, ()>("SetSurroundingText", &(text, 9_u32, 9_u32))
        .unwrap();
    let handled: bool = engine
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
    assert_eq!(value.fields().get(2).unwrap(), &Value::new("にほんご"));
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "prefix nihongof/",
        attributes,
    ));
    engine
        .call::<_, _, ()>("SetSurroundingText", &(text, 16_u32, 16_u32))
        .unwrap();
    let handled: bool = engine
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
    let attributes = Value::new((
        "IBusAttrList",
        HashMap::<String, OwnedValue>::new(),
        Vec::<OwnedValue>::new(),
    ));
    let text = Value::new((
        "IBusText",
        HashMap::<String, OwnedValue>::new(),
        "242j/",
        attributes,
    ));
    engine
        .call::<_, _, ()>("SetSurroundingText", &(text, 5_u32, 5_u32))
        .unwrap();
    let handled: bool = engine
        .call("ProcessKeyEvent", &(0x20_u32, 0_u32, 0_u32))
        .unwrap();
    assert!(handled);
}
