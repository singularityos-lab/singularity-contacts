using Gtk;

namespace Singularity.Apps.Contacts {

    public class ContactsApp : Singularity.Application {
        public Library library;
        private string? pending_action;

        public ContactsApp () {
            Object (application_id: "dev.sinty.contacts", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new-contact", 0, OptionFlags.NONE, OptionArg.NONE, _("Start a new contact"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new-contact")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("contacts: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("new-contact", null);
                return 0;
            }
            pending_action = "new-contact";
            return -1;
        }

        protected override void startup () {
            base.startup ();
            library = new Library ();
            library.start.begin ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("New Contact"), "win.new");
            f1.append (_("Import…"), "win.import");
            f1.append (_("Export All…"), "win.export-all");
            file.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Save Contact as vCard…"), "win.save-vcard");
            file.append_section (null, f2);
            var f3 = new GLib.Menu ();
            f3.append (_("Close Window"), "win.close");
            f3.append (_("Quit"), "app.quit");
            file.append_section (null, f3);
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Copy as Text"), "win.copy-text");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Edit Contact"), "win.edit");
            e2.append (_("Favorite"), "win.favorite");
            e2.append (_("Delete Contact…"), "win.delete");
            edit.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Find"), "win.find");
            edit.append_section (null, e3);
            var e4 = new GLib.Menu ();
            e4.append (_("Settings"), "app.settings");
            edit.append_section (null, e4);
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            var all_item = new GLib.MenuItem (_("All Contacts"), null);
            all_item.set_action_and_target_value ("win.source", new Variant.string ("all"));
            v1.append_item (all_item);
            var fav_item = new GLib.MenuItem (_("Favorites"), null);
            fav_item.set_action_and_target_value ("win.source", new Variant.string ("favorites"));
            v1.append_item (fav_item);
            view.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Toggle Sidebar"), "win.toggle-sidebar");
            view.append_section (null, v2);
            var v3 = new GLib.Menu ();
            v3.append (_("Refresh Online Contacts"), "win.refresh");
            v3.append (_("Online Accounts"), "win.online-accounts");
            view.append_section (null, v3);
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => quit_app ());
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.contacts");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var new_action = new SimpleAction ("new-contact", null);
            new_action.activate.connect (() => main_window ().start_new_contact ());
            add_action (new_action);
            var show_action = new SimpleAction ("show-contact", VariantType.STRING);
            show_action.activate.connect ((param) => show_contact (param.get_string ()));
            add_action (show_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.new", { "<Control>n" });
            set_accels_for_action ("win.import", { "<Control>o" });
            set_accels_for_action ("win.export-all", { "<Control><Shift>s" });
            set_accels_for_action ("win.save-vcard", { "<Control>s" });
            set_accels_for_action ("win.edit", { "<Control>e" });
            set_accels_for_action ("win.favorite", { "<Control>d" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.delete", { "<Control>Delete" });
            set_accels_for_action ("win.refresh", { "<Control>r" });
            set_accels_for_action ("win.source::all", { "<Control>1" });
            set_accels_for_action ("win.source::favorites", { "<Control>2" });
            set_accels_for_action ("win.toggle-sidebar", { "F9" });
        }

        private void quit_app () {
            foreach (var w in get_windows ()) w.close ();
        }

        private ContactsWindow main_window () {
            var w = get_active_window () as ContactsWindow;
            if (w == null) {
                foreach (var win in get_windows ()) {
                    if (win is ContactsWindow) w = (ContactsWindow) win;
                }
            }
            if (w == null) w = new ContactsWindow (this);
            w.present ();
            return w;
        }

        public void show_contact (string key) {
            main_window ().show_contact_key (key);
        }

        public override void activate () {
            if (pending_action != null) {
                string action = pending_action;
                pending_action = null;
                activate_action (action, null);
                return;
            }
            main_window ();
        }

        public override void open (File[] files, string hint) {
            var w = main_window ();
            foreach (var f in files) w.import_vcards.begin (f);
        }

        private const string CSS = """
.contacts-list-pane {
    padding-top: 56px;
}

.contacts-list {
    background: transparent;
    padding: 0 8px 8px 8px;
}

.contacts-list > row {
    border-radius: 10px;
    padding: 6px 8px;
    margin: 1px 0;
}

.contacts-list > row:selected {
    background-color: @hover_btn_bg;
    color: @hover_btn_fg;
}

.contacts-letter {
    font-size: 12px;
    font-weight: 800;
    opacity: 0.55;
    padding: 12px 10px 4px 10px;
}

.contacts-row-name {
    font-weight: 600;
}

.contacts-star {
    color: @warning_color;
}

.contacts-count {
    font-size: 12px;
    font-feature-settings: "tnum";
    opacity: 0.55;
}

.contacts-section {
    font-weight: 700;
    font-size: 15px;
    margin-top: 4px;
}

.contacts-action {
    border-radius: 99px;
    padding: 6px 16px;
    background-color: alpha(@window_fg_color, 0.07);
    border: none;
    box-shadow: none;
}

.contacts-action:hover {
    background-color: alpha(@window_fg_color, 0.12);
}

.contacts-fav-on {
    background-color: @hover_btn_bg;
    color: @hover_btn_fg;
}

.contacts-note {
    padding: 12px 14px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.05);
}

.contacts-note-edit {
    padding: 10px;
    border-radius: 12px;
    border: 1px solid alpha(@borders, 0.8);
}

.contacts-photo-button {
    border-radius: 999px;
    padding: 4px;
    background: transparent;
    box-shadow: none;
}

.contacts-photo-button:hover {
    background-color: alpha(@accent_bg_color, 0.15);
}

.contacts-add-field {
    border-radius: 99px;
    padding: 4px 14px;
}

.contacts-field-row {
    padding: 6px 10px;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-contacts", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-contacts", "UTF-8");
        Intl.textdomain ("singularity-contacts");
        var app = new ContactsApp ();
        new ContactsSearch (app).export (app);
        return app.run (args);
    }
}
