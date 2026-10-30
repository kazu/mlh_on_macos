use zbus::zvariant::{OwnedValue, Value};

pub fn assert_commit_text(message: zbus::Message, expected: &str) {
    let (value,): (OwnedValue,) = message.body().deserialize().unwrap();
    let Value::Structure(value) = Value::try_from(&value).unwrap() else {
        panic!("expected IBusText")
    };
    assert_eq!(value.fields()[2], Value::new(expected));
}
