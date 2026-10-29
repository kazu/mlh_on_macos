imports.gi.versions.Gtk = '3.0';
imports.gi.versions.Vte = '2.91';
const {Gtk, Vte, GLib} = imports.gi;
Gtk.init(null);
const window = new Gtk.Window({title: 'mlh test terminal', default_width: 800, default_height: 400});
const terminal = new Vte.Terminal();
window.add(terminal);
terminal.spawn_sync(Vte.PtyFlags.DEFAULT, GLib.get_home_dir(),
    [GLib.getenv('SHELL') || '/bin/sh', '-i'], null, GLib.SpawnFlags.DEFAULT, null, null);
window.connect('destroy', Gtk.main_quit);
terminal.connect('child-exited', () => window.destroy());
window.show_all();
terminal.grab_focus();
Gtk.main();
