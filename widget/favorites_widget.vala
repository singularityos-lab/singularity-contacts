using Gtk;
using Singularity;
using Singularity.Apps.Contacts;

namespace SingularityContactsWidget {

    public class FavoritesProvider : Object, OverviewWidgetProvider {
        public string id { get { return "contacts.favorites"; } }
        public string provider_id { get { return "dev.sinty.contacts"; } }
        public string display_name { get { return _("Favorite Contacts"); } }
        public string icon_name { get { return "starred-symbolic"; } }
        private WidgetSize[] _sizes;
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) _sizes = { WidgetSize (2, 1), WidgetSize (2, 2), WidgetSize (4, 1), WidgetSize (4, 2) };
                return _sizes;
            }
        }

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new FavoritesInstance (size);
        }
    }

    public class FavoritesInstance : Box {
        private WidgetSize size;
        private FlowBox grid;
        private Label empty;
        private Gee.ArrayList<FileMonitor> monitors = new Gee.ArrayList<FileMonitor> ();
        private uint reload_id;

        public FavoritesInstance (WidgetSize size) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.size = size;
            add_css_class ("overview-widget-card");
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;
            grid = new FlowBox ();
            grid.selection_mode = SelectionMode.NONE;
            grid.homogeneous = true;
            grid.min_children_per_line = 1;
            grid.max_children_per_line = size.w * 2;
            grid.column_spacing = 4;
            grid.row_spacing = 4;
            grid.valign = Align.CENTER;
            grid.vexpand = true;
            grid.margin_start = grid.margin_end = 10;
            grid.margin_top = grid.margin_bottom = 8;
            append (grid);
            empty = new Label (_("Star people in Contacts to see them here"));
            empty.add_css_class ("dim-label");
            empty.wrap = true;
            empty.justify = Justification.CENTER;
            empty.valign = Align.CENTER;
            empty.vexpand = true;
            empty.margin_start = empty.margin_end = 16;
            append (empty);
            watch (local_dir ());
            watch (cache_dir ());
            reload ();
            destroy.connect (() => {
                if (reload_id != 0) Source.remove (reload_id);
                reload_id = 0;
                foreach (var m in monitors) m.cancel ();
            });
        }

        private static string local_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "contacts");
        }

        private static string cache_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-contacts");
        }

        private void watch (string dir) {
            try {
                var m = File.new_for_path (dir).monitor_directory (FileMonitorFlags.NONE);
                m.changed.connect (() => {
                    if (reload_id != 0) Source.remove (reload_id);
                    reload_id = Timeout.add (400, () => {
                        reload_id = 0;
                        reload ();
                        return Source.REMOVE;
                    });
                });
                monitors.add (m);
            } catch (Error e) {
            }
        }

        private static void read_dir (string dir, bool per_file_source, Gee.List<Contact> into) {
            Dir d;
            try {
                d = Dir.open (dir);
            } catch (FileError e) {
                return;
            }
            string? n;
            while ((n = d.read_name ()) != null) {
                if (!n.has_suffix (".vcf")) continue;
                string text;
                try {
                    FileUtils.get_contents (Path.build_filename (dir, n), out text);
                } catch (FileError e) {
                    continue;
                }
                foreach (var c in VCard.parse (text)) {
                    if (!c.favorite || c.uid == "") continue;
                    c.source_id = per_file_source ? n.substring (0, n.length - 4) : "local";
                    into.add (c);
                }
            }
        }

        private void reload () {
            var list = new Gee.ArrayList<Contact> ();
            read_dir (local_dir (), false, list);
            read_dir (cache_dir (), true, list);
            list.sort ((a, b) => strcmp (a.sort_key, b.sort_key));
            Widget? child;
            while ((child = grid.get_first_child ()) != null) grid.remove (child);
            int limit = size.w * 2 * size.h;
            int shown = 0;
            foreach (var c in list) {
                if (shown >= limit) break;
                grid.append (make_item (c));
                shown++;
            }
            grid.visible = shown > 0;
            empty.visible = shown == 0;
        }

        private Widget make_item (Contact c) {
            var button = new Button ();
            button.add_css_class ("flat");
            button.tooltip_text = c.display_name;
            var box = new Box (Orientation.VERTICAL, 4);
            var avatar = new ContactAvatar (size.h > 1 ? 56 : 44);
            avatar.set_contact (c);
            avatar.halign = Align.CENTER;
            box.append (avatar);
            string first = c.given != "" ? c.given : c.display_name;
            var name = new Label (first);
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 10;
            name.add_css_class ("caption");
            box.append (name);
            button.child = box;
            string key = c.source_id + "/" + c.uid;
            button.clicked.connect (() => open_contact (key));
            return button;
        }

        private static void open_contact (string key) {
            Bus.get.begin (BusType.SESSION, null, (o, res) => {
                try {
                    var bus = Bus.get.end (res);
                    var args = new VariantBuilder (new VariantType ("av"));
                    args.add ("v", new Variant.string (key));
                    bus.call.begin ("dev.sinty.contacts", "/dev/sinty/contacts", "org.freedesktop.Application", "ActivateAction",
                        new Variant ("(s@av@a{sv})", "show-contact", args.end (), new VariantBuilder (VariantType.VARDICT).end ()),
                        null, DBusCallFlags.NONE, 5000, null);
                } catch (Error e) {
                    warning ("contacts widget: %s", e.message);
                }
            });
        }
    }

    [CCode (cname = "singularity_contacts_widget_new")]
    public static Object singularity_contacts_widget_new () {
        return new FavoritesProvider ();
    }
}
