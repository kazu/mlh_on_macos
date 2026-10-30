use criterion::{Criterion, Throughput, black_box, criterion_group, criterion_main};
use zbus::{
    blocking::{Connection, Proxy, connection::Builder},
    zvariant::OwnedObjectPath,
};

fn bench_keys(c: &mut Criterion) {
    let _service = Builder::session()
        .unwrap()
        .name("org.freedesktop.IBus.MlhBench")
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
        "org.freedesktop.IBus.MlhBench",
        "/org/freedesktop/IBus/Factory",
        "org.freedesktop.IBus.Factory",
    )
    .unwrap();
    let mut group = c.benchmark_group("ibus_keys");
    group.throughput(Throughput::Elements(2));
    for (name, client) in [("sdl2", "SDL2_Application"), ("other", "other")] {
        let path: OwnedObjectPath = factory.call("CreateEngine", &("mlh",)).unwrap();
        let engine = Proxy::new(
            &connection,
            "org.freedesktop.IBus.MlhBench",
            path,
            "org.freedesktop.IBus.Engine",
        )
        .unwrap();
        engine
            .call::<_, _, ()>("FocusInId", &("/bench", client))
            .unwrap();
        group.bench_function(name, |b| {
            b.iter(|| {
                for key in [0x61_u32, 0xff08] {
                    black_box(
                        engine
                            .call::<_, _, bool>("ProcessKeyEvent", &(key, 0_u32, 0_u32))
                            .unwrap(),
                    );
                }
            });
        });
    }
    group.finish();
}

criterion_group!(benches, bench_keys);
criterion_main!(benches);
