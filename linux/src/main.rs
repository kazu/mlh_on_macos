use mlh_ibus::ibus;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    if args.next().as_deref() == Some("--component-xml") {
        let executable = args.next().ok_or("missing executable path")?;
        let executable = format!("'{}'", executable.replace('\'', "'\\''"));
        let executable = executable
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
            .replace('\'', "&apos;");
        println!(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<component>\n  <name>org.freedesktop.IBus.Mlh</name>\n  <description>Modeless input</description>\n  <exec>{executable}</exec>\n  <version>{}</version>\n  <license>GPL-2.0-or-later</license>\n  <author>mlh contributors</author>\n  <homepage>https://github.com/kazu/mlh_on_macos</homepage>\n  <textdomain>mlh</textdomain>\n  <engines><engine>\n    <name>mlh</name><longname>mlh</longname><description>Modeless input</description>\n    <language>ja</language><license>GPL-2.0-or-later</license>\n    <author>mlh contributors</author><layout>default</layout><icon>ibus-keyboard</icon>\n  </engine></engines>\n</component>",
            env!("CARGO_PKG_VERSION")
        );
        return Ok(());
    }
    let output = std::process::Command::new("ibus").arg("address").output()?;
    if !output.status.success() {
        return Err("ibus address failed".into());
    }
    let address = String::from_utf8(output.stdout)?;
    let connection =
        zbus::blocking::connection::Builder::address(mlh_ibus::ibus_address(address.trim())?)?
            .name("org.freedesktop.IBus.Mlh")?
            .serve_at("/org/freedesktop/IBus/Factory", ibus::Factory::default())?
            .build()?;
    std::thread::spawn(move || {
        for message in zbus::blocking::MessageIterator::from(&connection) {
            if message.is_err() {
                break;
            }
        }
        std::process::exit(0);
    });
    mlh_ibus::core::run_main_loop()
}
