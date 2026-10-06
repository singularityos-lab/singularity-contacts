using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Contacts {

    public class Editor : Box {
        private Contact contact;
        private unowned Gtk.Window parent_window;
        private Library library;
        private ContactAvatar avatar;
        private EntryRow given;
        private EntryRow family;
        private EntryRow nickname;
        private EntryRow org;
        private EntryRow job;
        private EntryRow birthday;
        private TextView note;
        private DropDown? book_drop;
        private Gee.ArrayList<AddressBook> writable = new Gee.ArrayList<AddressBook> ();
        private FieldList phones;
        private FieldList emails;
        private FieldList urls;
        private Box addresses_box;
        private Gee.ArrayList<AddressEditor> address_editors = new Gee.ArrayList<AddressEditor> ();

        public const string[] KINDS = { "cell", "home", "work", "main", "fax", "other" };

        public static string[] kind_labels () {
            return { _("Mobile"), _("Home"), _("Work"), _("Main"), _("Fax"), _("Other") };
        }

        public static int kind_index (string k) {
            for (int i = 0; i < KINDS.length; i++) if (KINDS[i] == k) return i;
            return 5;
        }

        private class FieldList : Box {
            private PreferencesGroup group;
            private Gee.ArrayList<Box> rows = new Gee.ArrayList<Box> ();
            private string placeholder;
            private InputPurpose purpose;
            private bool with_kind;
            private string default_kind;

            public FieldList (string title, string placeholder, InputPurpose purpose, bool with_kind, string default_kind) {
                Object (orientation: Orientation.VERTICAL, spacing: 6);
                this.placeholder = placeholder;
                this.purpose = purpose;
                this.with_kind = with_kind;
                this.default_kind = default_kind;
                group = new PreferencesGroup (title);
                append (group);
                var add = new Button.with_label (_("Add %s").printf (title));
                add.add_css_class ("contacts-add-field");
                add.halign = Align.START;
                add.clicked.connect (() => {
                    var e = add_field (new Field (default_kind, ""));
                    e.grab_focus ();
                });
                append (add);
            }

            public Entry add_field (Field f) {
                var row = new Box (Orientation.HORIZONTAL, 8);
                row.add_css_class ("contacts-field-row");
                DropDown? kind = null;
                if (with_kind) {
                    var model = new StringList (null);
                    foreach (string l in Editor.kind_labels ()) model.append (l);
                    kind = new DropDown (model, null);
                    kind.selected = Editor.kind_index (f.kind);
                    kind.valign = Align.CENTER;
                    row.append (kind);
                }
                var entry = new Entry ();
                entry.text = f.value;
                entry.placeholder_text = placeholder;
                entry.input_purpose = purpose;
                entry.hexpand = true;
                entry.input_hints = InputHints.NO_SPELLCHECK;
                row.append (entry);
                var del = new Button.from_icon_name ("list-remove-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Remove");
                del.clicked.connect (() => {
                    rows.remove (row);
                    group.remove_row (row);
                });
                row.append (del);
                row.set_data<Entry> ("entry", entry);
                if (kind != null) row.set_data<DropDown> ("kind", kind);
                rows.add (row);
                group.add_row (row);
                return entry;
            }

            public Gee.ArrayList<Field> collect () {
                var list = new Gee.ArrayList<Field> ();
                foreach (var r in rows) {
                    var e = r.get_data<Entry> ("entry");
                    if (e.text.strip () == "") continue;
                    var k = r.get_data<DropDown> ("kind");
                    list.add (new Field (k != null ? Editor.KINDS[k.selected] : default_kind, e.text.strip ()));
                }
                return list;
            }
        }

        private class AddressEditor : Box {
            public DropDown kind;
            public EntryRow street;
            public EntryRow postal;
            public EntryRow city;
            public EntryRow region;
            public EntryRow country;

            public AddressEditor (PostalAddress a) {
                Object (orientation: Orientation.VERTICAL, spacing: 6);
                var g = new PreferencesGroup ();
                var model = new StringList (null);
                foreach (string l in Editor.kind_labels ()) model.append (l);
                kind = new DropDown (model, null);
                kind.selected = Editor.kind_index (a.kind);
                var head = new ActionRow (_("Address"));
                kind.valign = Align.CENTER;
                head.add_suffix (kind);
                var del = new Button.from_icon_name ("list-remove-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Remove");
                del.clicked.connect (() => {
                    var p = get_parent () as Box;
                    if (p != null) p.remove (this);
                    removed ();
                });
                head.add_suffix (del);
                g.add_row (head);
                street = new EntryRow (_("Street"));
                street.text = a.street.replace ("\n", ", ");
                postal = new EntryRow (_("Postal Code"));
                postal.text = a.postal;
                city = new EntryRow (_("City"));
                city.text = a.city;
                region = new EntryRow (_("Region"));
                region.text = a.region;
                country = new EntryRow (_("Country"));
                country.text = a.country;
                g.add_row (street);
                g.add_row (postal);
                g.add_row (city);
                g.add_row (region);
                g.add_row (country);
                append (g);
            }

            public signal void removed ();

            public PostalAddress collect () {
                var a = new PostalAddress ();
                a.kind = Editor.KINDS[kind.selected];
                a.street = street.text.strip ();
                a.postal = postal.text.strip ();
                a.city = city.text.strip ();
                a.region = region.text.strip ();
                a.country = country.text.strip ();
                return a;
            }
        }

        public Editor (Gtk.Window parent, Contact contact, Library library) {
            Object (orientation: Orientation.VERTICAL, spacing: 18);
            this.parent_window = parent;
            this.contact = contact;
            this.library = library;
            add_css_class ("contacts-editor");

            var photo_box = new Box (Orientation.VERTICAL, 8);
            photo_box.halign = Align.CENTER;
            avatar = new ContactAvatar (112);
            avatar.set_contact (contact);
            var photo_btn = new Button ();
            photo_btn.add_css_class ("contacts-photo-button");
            photo_btn.child = avatar;
            photo_btn.tooltip_text = _("Change Photo");
            photo_btn.clicked.connect (() => photo_menu (photo_btn));
            photo_box.append (photo_btn);
            append (photo_box);

            var names = new PreferencesGroup (_("Name"));
            given = new EntryRow (_("First Name"));
            given.text = contact.given;
            family = new EntryRow (_("Last Name"));
            family.text = contact.family;
            nickname = new EntryRow (_("Nickname"));
            nickname.text = contact.nickname;
            names.add_row (given);
            names.add_row (family);
            names.add_row (nickname);
            if (contact.given == "" && contact.family == "" && contact.formatted != "") {
                string[] w = contact.formatted.strip ().split (" ");
                given.text = w[0];
                if (w.length > 1) family.text = string.joinv (" ", w[1:w.length]);
            }
            given.entry_changed.connect (() => refresh_avatar ());
            family.entry_changed.connect (() => refresh_avatar ());
            append (names);

            var work = new PreferencesGroup (_("Work"));
            org = new EntryRow (_("Company"));
            org.text = contact.org;
            job = new EntryRow (_("Job Title"));
            job.text = contact.title;
            work.add_row (org);
            work.add_row (job);
            append (work);

            phones = new FieldList (_("Phone"), _("Number"), InputPurpose.PHONE, true, "cell");
            foreach (var f in contact.phones) phones.add_field (f);
            if (contact.phones.size == 0) phones.add_field (new Field ("cell", ""));
            append (phones);
            emails = new FieldList (_("Email"), _("Address"), InputPurpose.EMAIL, true, "home");
            foreach (var f in contact.emails) emails.add_field (f);
            if (contact.emails.size == 0) emails.add_field (new Field ("home", ""));
            append (emails);

            addresses_box = new Box (Orientation.VERTICAL, 10);
            foreach (var a in contact.addresses) add_address (a);
            append (addresses_box);
            var add_adr = new Button.with_label (_("Add Address"));
            add_adr.add_css_class ("contacts-add-field");
            add_adr.halign = Align.START;
            add_adr.clicked.connect (() => add_address (new PostalAddress ()));
            append (add_adr);

            urls = new FieldList (_("Website"), "https://", InputPurpose.URL, false, "home");
            foreach (var f in contact.urls) urls.add_field (f);
            append (urls);

            var more = new PreferencesGroup (_("More"));
            birthday = new EntryRow (_("Birthday, for example 1990-05-21"));
            birthday.text = contact.birthday;
            more.add_row (birthday);
            append (more);

            var note_title = new Label (_("Notes"));
            note_title.xalign = 0;
            note_title.add_css_class ("contacts-section");
            append (note_title);
            note = new TextView ();
            note.wrap_mode = WrapMode.WORD_CHAR;
            note.add_css_class ("contacts-note-edit");
            note.buffer.text = contact.note;
            note.set_size_request (-1, 90);
            append (note);

            if (contact.href == "") {
                foreach (var b in library.books) if (!b.read_only) writable.add (b);
                if (writable.size > 1) {
                    var model = new StringList (null);
                    uint sel = 0;
                    for (int i = 0; i < writable.size; i++) {
                        model.append (writable[i].full_name);
                        if (writable[i].id == contact.source_id) sel = i;
                    }
                    book_drop = new DropDown (model, null);
                    book_drop.selected = sel;
                    var g = new PreferencesGroup ();
                    var r = new ActionRow (_("Save In"));
                    book_drop.valign = Align.CENTER;
                    r.add_suffix (book_drop);
                    g.add_row (r);
                    append (g);
                }
            }
        }

        private void add_address (PostalAddress a) {
            var ed = new AddressEditor (a);
            ed.removed.connect (() => address_editors.remove (ed));
            address_editors.add (ed);
            addresses_box.append (ed);
        }

        public void focus_first () {
            given.grab_focus ();
        }

        private void refresh_avatar () {
            var tmp = new Contact ();
            tmp.given = given.text;
            tmp.family = family.text;
            tmp.photo = contact.photo;
            avatar.set_contact (tmp);
        }

        private void photo_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Choose Picture…"), "image-x-generic-symbolic", () => choose_photo ());
            if (contact.photo != null) menu.add_item (_("Remove Picture"), "user-trash-symbolic", () => {
                contact.photo = null;
                refresh_avatar ();
            });
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void choose_photo () {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Picture");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Images");
            f.add_mime_type ("image/*");
            filters.append (f);
            dialog.filters = filters;
            dialog.open.begin (parent_window, null, (o, res) => {
                try {
                    var file = dialog.open.end (res);
                    var pix = new Gdk.Pixbuf.from_file (file.get_path ());
                    int side = int.min (pix.width, pix.height);
                    var square = new Gdk.Pixbuf.subpixbuf (pix, (pix.width - side) / 2, (pix.height - side) / 2, side, side);
                    var scaled = square.scale_simple (int.min (side, 256), int.min (side, 256), Gdk.InterpType.HYPER);
                    uint8[] buffer;
                    scaled.save_to_buffer (out buffer, "jpeg", "quality", "88");
                    contact.photo = buffer;
                    contact.photo_type = "jpeg";
                    refresh_avatar ();
                } catch (Error e) {
                }
            });
        }

        public Contact result () {
            var c = contact;
            c.given = given.text.strip ();
            c.family = family.text.strip ();
            c.formatted = "";
            c.nickname = nickname.text.strip ();
            c.org = org.text.strip ();
            c.title = job.text.strip ();
            c.phones = phones.collect ();
            c.emails = emails.collect ();
            c.urls = urls.collect ();
            var adrs = new Gee.ArrayList<PostalAddress> ();
            foreach (var ed in address_editors) {
                var a = ed.collect ();
                if (!a.is_empty ()) adrs.add (a);
            }
            c.addresses = adrs;
            c.birthday = parse_birthday (birthday.text);
            c.note = note.buffer.text.strip ();
            if (book_drop != null && book_drop.selected < writable.size) c.source_id = writable[(int) book_drop.selected].id;
            if (c.source_id == "") c.source_id = "local";
            return c;
        }

        public static string parse_birthday (string text) {
            string t = text.strip ();
            if (t == "") return "";
            if (t.has_prefix ("--")) return VCard.normalize_date (t);
            var parts = t.replace (".", "-").replace ("/", "-").split ("-");
            if (parts.length == 3) {
                int a = int.parse (parts[0]), b = int.parse (parts[1]), c = int.parse (parts[2]);
                int y, m, d;
                if (parts[0].length == 4) {
                    y = a;
                    m = b;
                    d = c;
                } else {
                    d = a;
                    m = b;
                    y = c < 100 ? (c > 30 ? 1900 + c : 2000 + c) : c;
                }
                if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && y > 1800) return "%04d-%02d-%02d".printf (y, m, d);
            }
            if (parts.length == 2) {
                int d = int.parse (parts[0]), m = int.parse (parts[1]);
                if (m >= 1 && m <= 12 && d >= 1 && d <= 31) return "--%02d-%02d".printf (m, d);
            }
            return t;
        }
    }
}
