const gtk4 = imports.gi.GLib.getenv('MLH_VTE_GTK4') === '1';
imports.gi.versions.Gtk = gtk4 ? '4.0' : '3.0';
imports.gi.versions.Vte = gtk4 ? '3.91' : '2.91';
const {Gtk, Vte, GLib} = imports.gi;
if (gtk4) Gtk.init();
else Gtk.init(null);
const window = new Gtk.Window({title: 'mlh-vte-test'});
const terminal = new Vte.Terminal();
if (gtk4) window.set_child(terminal); else window.add(terminal);
terminal.spawn_sync(Vte.PtyFlags.DEFAULT, null, ['/bin/cat'], null,
    GLib.SpawnFlags.DEFAULT, null, null);
if (gtk4) window.present(); else window.show_all();
terminal.grab_focus();
print('ready');
const loop = new GLib.MainLoop(null, false);
let tries = 0;
let success = false;
const expected = GLib.getenv('MLH_VTE_EXPECT') || '日本語';
const forbidden = GLib.getenv('MLH_VTE_FORBIDDEN') || 'nihongo/';
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
    const text = terminal.get_text_format(Vte.Format.TEXT);
    if (text.includes(expected)) {
        print(JSON.stringify(text));
        success = !text.includes(forbidden);
        loop.quit();
        return GLib.SOURCE_REMOVE;
    }
    if (++tries >= 120) {
        printerr('unexpected terminal text: ' + JSON.stringify(text));
        loop.quit();
        return GLib.SOURCE_REMOVE;
    }
    return GLib.SOURCE_CONTINUE;
});
loop.run();
if (!success) imports.system.exit(1);
