using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Contacts {

    public class ContactsWindow : Singularity.Widgets.Window {
        private ContactsApp app;
        private Library library;
        private AppSidebar sidebar;
        private Stack stack;
        private ListBox list;
        private Singularity.Animation.ListAnimator animator;
        private ScrolledWindow detail_scroll;
        private Box detail;
        private Label list_status;
        private string filter_source = "all";
        private string query = "";
        private Contact? current;
        private bool editing;
        private Button new_bubble;
        private Button edit_bubble;
        private Button more_bubble;
        private Button save_bubble;
        private Button cancel_bubble;
        private SearchBubble search;
        private Gee.HashMap<string, SidebarRow> source_rows = new Gee.HashMap<string, SidebarRow> ();
        private Editor? editor;
        private string? pending_key;

        public ContactsWindow (ContactsApp app) {
            Object (application: app);
            this.app = app;
            this.library = app.library;
            set_default_size (1060, 720);
            set_title (_("Contacts"));

            sidebar = new AppSidebar (230);
            set_sidebar (sidebar);
            set_sidebar_visible (true);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.add_named (build_welcome (), "welcome");
            stack.add_named (build_main (), "main");
            set_content (stack);

            search = add_bubble_search (_("Search Contacts"), (t) => {
                query = t;
                list.invalidate_filter ();
                update_list_status ();
            });
            new_bubble = add_bubble_icon ("list-add-symbolic", _("New Contact (Ctrl+N)"), () => new_contact ());
            edit_bubble = add_bubble_icon ("document-edit-symbolic", _("Edit"), () => start_edit ());
            more_bubble = add_bubble_icon ("view-more-symbolic", _("More"), () => show_more ());
            cancel_bubble = add_bubble_text (_("Cancel"), () => stop_edit (false));
            save_bubble = add_bubble_suggested (_("Done"), () => stop_edit (true));
            sync_bubbles ();

            library.changed.connect (() => rebuild ());
            install_actions ();
            rebuild ();
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.contacts";
            wp.title = _("Contacts");
            wp.subtitle = _("The people you know, on this computer and in your online accounts");
            wp.add_action ("avatar-default", _("New Contact"), _("Add someone by hand"), () => new_contact ());
            wp.add_action ("text-x-vcard", _("Import"), _("Contacts from a vCard file"), () => import_file ());
            wp.add_action ("network-workgroup", _("Online Accounts"), _("Show the contacts of Google, Nextcloud and more"), () => open_accounts ());
            return wp;
        }

        private Widget build_main () {
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.add_css_class ("contacts-main");
            var left = new Box (Orientation.VERTICAL, 0);
            left.add_css_class ("contacts-list-pane");
            left.set_size_request (310, -1);
            left.hexpand = false;
            list = new ListBox ();
            animator = new Singularity.Animation.ListAnimator (list);
            list.add_css_class ("contacts-list");
            list.selection_mode = SelectionMode.SINGLE;
            list.set_filter_func ((row) => {
                var c = row.get_data<Contact> ("contact");
                if (c == null) return false;
                if (filter_source == "favorites" && !c.favorite) return false;
                if (filter_source != "all" && filter_source != "favorites" && c.source_id != filter_source) return false;
                return c.matches (query);
            });
            list.set_header_func ((row, before) => {
                var c = row.get_data<Contact> ("contact");
                string letter = initial_of (c);
                string prev = before != null ? initial_of (before.get_data<Contact> ("contact")) : "";
                if (letter != prev) {
                    var l = new Label (letter);
                    l.add_css_class ("contacts-letter");
                    l.xalign = 0;
                    row.set_header (l);
                } else {
                    row.set_header (null);
                }
            });
            list.row_selected.connect ((row) => {
                if (row == null) return;
                if (editing) stop_edit (true);
                show_contact (row.get_data<Contact> ("contact"));
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = list;
            list_status = new Label ("");
            list_status.add_css_class ("dim-label");
            list_status.add_css_class ("caption");
            list_status.margin_top = list_status.margin_bottom = 8;
            list_status.wrap = true;
            left.append (scroll);
            left.append (list_status);
            box.append (left);
            box.append (new Separator (Orientation.VERTICAL));
            detail_scroll = new ScrolledWindow ();
            detail_scroll.hscrollbar_policy = PolicyType.NEVER;
            detail_scroll.hexpand = true;
            detail_scroll.vexpand = true;
            detail_scroll.add_css_class ("contacts-detail-scroll");
            box.append (detail_scroll);
            return box;
        }

        private static string initial_of (Contact? c) {
            if (c == null) return "";
            string k = c.family != "" ? c.family : c.display_name;
            k = k.strip ();
            if (k == "") return "#";
            unichar ch = k.normalize (-1, NormalizeMode.ALL).get_char (0);
            if (!ch.isalpha ()) return "#";
            string d = ch.toupper ().to_string ().normalize (-1, NormalizeMode.NFD);
            return d.substring (0, d.index_of_nth_char (1));
        }

        public void show_contact_key (string key) {
            if (editing) stop_edit (true);
            pending_key = key;
            if (filter_source != "all") select_source ("all");
            if (query != "") search.clear ();
            rebuild ();
        }

        public void start_new_contact () {
            if (!editing) new_contact ();
        }

        private void rebuild () {
            animator.rebuild (rebuild_now);
        }

        private void rebuild_now () {
            string? keep = current != null ? current.source_id + "/" + current.uid : null;
            bool pending = false;
            if (pending_key != null) {
                foreach (var c in library.all ()) {
                    if (c.source_id + "/" + c.uid == pending_key) {
                        keep = pending_key;
                        pending = true;
                        break;
                    }
                }
                if (pending || library.started) pending_key = null;
            }
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            var all = library.all ();
            ListBoxRow? select = null;
            foreach (var c in all) {
                var row = make_row (c);
                list.append (row);
                if (keep != null && c.source_id + "/" + c.uid == keep) select = row;
            }
            rebuild_sidebar (all);
            stack.visible_child_name = all.size == 0 && !editing ? "welcome" : "main";
            if (select != null) list.select_row (select);
            else if (!editing) {
                var first = first_visible ();
                if (first != null) list.select_row (first);
                else show_contact (null);
            }
            update_list_status ();
            sync_bubbles ();
        }

        private ListBoxRow? first_visible () {
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) return null;
                if (row.get_child_visible ()) return row;
            }
        }

        private ListBoxRow make_row (Contact c) {
            var row = new ListBoxRow ();
            row.set_data<Contact> ("contact", c);
            row.add_css_class ("contacts-row");
            var box = new Box (Orientation.HORIZONTAL, 12);
            var av = new ContactAvatar (36);
            av.set_contact (c);
            box.append (av);
            var texts = new Box (Orientation.VERTICAL, 1);
            texts.valign = Align.CENTER;
            texts.hexpand = true;
            var name = new Label (c.display_name != "" ? c.display_name : _("Unnamed"));
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.add_css_class ("contacts-row-name");
            texts.append (name);
            string sub = c.org != "" ? c.org : (c.emails.size > 0 ? c.emails[0].value : (c.phones.size > 0 ? c.phones[0].value : ""));
            if (sub != "" && sub != c.display_name) {
                var s = new Label (sub);
                s.xalign = 0;
                s.ellipsize = Pango.EllipsizeMode.END;
                s.add_css_class ("dim-label");
                s.add_css_class ("caption");
                texts.append (s);
            }
            box.append (texts);
            if (c.favorite) {
                var star = new Image.from_icon_name ("starred-symbolic");
                star.add_css_class ("contacts-star");
                box.append (star);
            }
            row.child = Singularity.Animation.ListAnimator.wrap (box);
            Singularity.Animation.ListAnimator.set_key (row, c.source_id + "/" + c.uid);
            return row;
        }

        private void rebuild_sidebar (Gee.List<Contact> all) {
            Widget? child;
            while ((child = sidebar.box.get_first_child ()) != null) sidebar.box.remove (child);
            source_rows.clear ();
            int favs = 0;
            foreach (var c in all) if (c.favorite) favs++;
            add_source_row ("all", "system-users-symbolic", _("All Contacts"), all.size);
            add_source_row ("favorites", "starred-symbolic", _("Favorites"), favs);
            sidebar.box.append (new SidebarSectionLabel (_("Address Books")));
            string section = "";
            foreach (var b in library.books) {
                if (b.account_name != "" && b.account_name != section) {
                    section = b.account_name;
                    sidebar.box.append (new SidebarSectionLabel (section));
                }
                add_source_row (b.id, b.icon, b.name, b.contacts.size, b.status);
            }
            var add = new SidebarRow ("list-add-symbolic", _("Add Online Account"));
            add.add_css_class ("contacts-add-account");
            add.clicked.connect (open_accounts);
            sidebar.box.append (add);
            if (!source_rows.has_key (filter_source)) {
                filter_source = "all";
                list.invalidate_filter ();
            }
            foreach (var e in source_rows.entries) e.value.set_active (e.key == filter_source);
            var source = lookup_action ("source") as SimpleAction;
            if (source != null) source.set_state (new Variant.string (filter_source));
        }

        private void add_source_row (string id, string icon, string title, int count, string status = "") {
            var row = new SidebarRow (icon, title);
            var badge = new Label (count.to_string ());
            badge.add_css_class ("contacts-count");
            var inner = row.get_child () as Box;
            if (inner != null) inner.append (badge);
            if (status != "") row.tooltip_text = status;
            row.clicked.connect (() => select_source (id));
            source_rows[id] = row;
            sidebar.box.append (row);
        }

        private void update_list_status () {
            int visible = 0;
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i);
                if (row == null) break;
                var c = row.get_data<Contact> ("contact");
                if (filter_source == "favorites" && !c.favorite) continue;
                if (filter_source != "all" && filter_source != "favorites" && c.source_id != filter_source) continue;
                if (!c.matches (query)) continue;
                visible++;
            }
            string status = "";
            var b = library.book (filter_source);
            if (b != null && b.status != "") status = b.status;
            list_status.label = status;
            list_status.visible = status != "";
            if (editing) return;
            if (visible == 0) {
                current = null;
                list.unselect_all ();
                detail_scroll.child = build_empty_state ();
                sync_bubbles ();
            } else if (current == null) {
                var first = first_visible ();
                if (first != null) list.select_row (first);
            }
        }

        private Widget build_empty_state () {
            if (query != "") {
                var none = new StatusPage ();
                none.icon_name = "system-search";
                none.title = _("No Contacts Found");
                none.description = _("No contacts match your search.");
                var clear = new Button.with_label (_("Clear Search"));
                clear.halign = Align.CENTER;
                clear.add_css_class ("pill");
                clear.add_css_class ("suggested-action");
                clear.clicked.connect (() => search.clear ());
                none.child = clear;
                return none;
            }
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.embedded = true;
            wp.app_icon_name = "dev.sinty.contacts";
            if (filter_source == "favorites") {
                wp.title = _("Favorites");
                wp.subtitle = _("Mark people you contact often with the star");
                wp.add_action ("x-office-addressbook", _("All Contacts"), _("Pick someone to mark as a favorite"), () => select_source ("all"));
                wp.add_action ("avatar-default", _("New Contact"), _("Add someone by hand"), () => new_contact ());
                return wp;
            }
            var b = library.book (filter_source);
            wp.title = b != null ? b.name : _("All Contacts");
            wp.subtitle = _("No contacts here yet");
            wp.add_action ("avatar-default", _("New Contact"), _("Add someone by hand"), () => new_contact ());
            wp.add_action ("text-x-vcard", _("Import"), _("Contacts from a vCard file"), () => import_file ());
            wp.add_action ("network-workgroup", _("Online Accounts"), _("Show the contacts of Google, Nextcloud and more"), () => open_accounts ());
            return wp;
        }

        private void sync_bubbles () {
            edit_bubble.visible = !editing && current != null;
            more_bubble.visible = !editing && current != null;
            save_bubble.visible = editing;
            cancel_bubble.visible = editing;
            search.visible = !editing;
            new_bubble.visible = !editing;
            sync_actions ();
        }

        private void sync_actions () {
            bool has = current != null && !editing;
            string[] contact_actions = { "edit", "delete", "favorite", "copy-text", "save-vcard" };
            foreach (string n in contact_actions) {
                var a = lookup_action (n) as SimpleAction;
                if (a != null) a.set_enabled (has);
            }
            string[] idle_actions = { "new", "import", "find" };
            foreach (string n in idle_actions) {
                var a = lookup_action (n) as SimpleAction;
                if (a != null) a.set_enabled (!editing);
            }
            var export_all = lookup_action ("export-all") as SimpleAction;
            if (export_all != null) export_all.set_enabled (!editing && library.all ().size > 0);
            var fav = lookup_action ("favorite") as SimpleAction;
            if (fav != null) fav.set_state (new Variant.boolean (current != null && current.favorite));
        }

        private void select_source (string id) {
            if (!source_rows.has_key (id)) return;
            filter_source = id;
            foreach (var e in source_rows.entries) e.value.set_active (e.key == id);
            var source = lookup_action ("source") as SimpleAction;
            if (source != null) source.set_state (new Variant.string (id));
            list.invalidate_filter ();
            update_list_status ();
            var first = first_visible ();
            if (first != null) list.select_row (first);
        }

        private Label section_title (string t) {
            var l = new Label (t);
            l.xalign = 0;
            l.add_css_class ("contacts-section");
            return l;
        }

        private Widget copy_button (string value) {
            var b = new Button.from_icon_name ("edit-copy-symbolic");
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            b.tooltip_text = _("Copy");
            b.clicked.connect (() => get_clipboard ().set_text (value));
            return b;
        }

        private static string kind_label (string k) {
            switch (k) {
                case "cell": return _("Mobile");
                case "work": return _("Work");
                case "home": return _("Home");
                case "fax": return _("Fax");
                case "pager": return _("Pager");
                case "main": return _("Main");
                default: return _("Other");
            }
        }

        private void launch (string uri) {
            var l = new UriLauncher (uri);
            l.launch.begin (this, null);
        }

        private void show_contact (Contact? c) {
            current = c;
            sync_bubbles ();
            detail = new Box (Orientation.VERTICAL, 18);
            detail.add_css_class ("contacts-detail");
            apply_view_edge (detail);
            detail.margin_bottom = 32;
            detail.margin_start = 24;
            detail.margin_end = 24;
            detail_scroll.child = new Clamp (detail) { maximum = 560 };
            if (c == null) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.embedded = true;
                wp.app_icon_name = "dev.sinty.contacts";
                wp.title = _("No Contact Selected");
                wp.subtitle = _("Pick someone from the list to see their details");
                wp.add_action ("avatar-default", _("New Contact"), _("Add someone by hand"), () => new_contact ());
                wp.add_action ("text-x-vcard", _("Import"), _("Contacts from a vCard file"), () => import_file ());
                wp.add_action ("system-search", _("Search"), _("Find someone by name, email or phone"), () => search.grab_focus_entry ());
                detail_scroll.child = wp;
                return;
            }
            var head = new Box (Orientation.VERTICAL, 8);
            head.halign = Align.CENTER;
            var av = new ContactAvatar (112);
            av.set_contact (c);
            av.halign = Align.CENTER;
            head.append (av);
            var name = new Label (c.display_name != "" ? c.display_name : _("Unnamed"));
            name.add_css_class ("title-1");
            name.wrap = true;
            name.justify = Justification.CENTER;
            head.append (name);
            string sub = string.joinv (" · ", non_empty ({ c.title, c.org }));
            if (c.nickname != "" && c.nickname != c.display_name) sub = sub != "" ? "“%s” · %s".printf (c.nickname, sub) : "“%s”".printf (c.nickname);
            if (sub != "") {
                var s = new Label (sub);
                s.add_css_class ("dim-label");
                s.wrap = true;
                s.justify = Justification.CENTER;
                head.append (s);
            }
            detail.append (head);

            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.halign = Align.CENTER;
            if (c.emails.size > 0) actions.append (action_pill ("mail-send-symbolic", _("Email"), () => launch ("mailto:" + c.emails[0].value)));
            if (c.phones.size > 0) actions.append (action_pill ("call-start-symbolic", _("Call"), () => launch ("tel:" + c.phones[0].value.replace (" ", ""))));
            var fav = action_pill (c.favorite ? "starred-symbolic" : "non-starred-symbolic", c.favorite ? _("Favorite") : _("Add to Favorites"), () => toggle_favorite ());
            if (c.favorite) fav.add_css_class ("contacts-fav-on");
            actions.append (fav);
            actions.append (action_pill ("singularity-share-symbolic", _("Share"), () => share_contact (c)));
            detail.append (actions);

            if (c.phones.size > 0) {
                var g = new PreferencesGroup (_("Phone"));
                foreach (var p in c.phones) {
                    var r = new ActionRow (p.value, kind_label (p.kind));
                    r.add_css_class ("contacts-value-row");
                    string num = p.value;
                    var call = new Button.from_icon_name ("call-start-symbolic");
                    call.add_css_class ("flat");
                    call.valign = Align.CENTER;
                    call.tooltip_text = _("Call");
                    call.clicked.connect (() => launch ("tel:" + num.replace (" ", "")));
                    r.add_suffix (call);
                    r.add_suffix (copy_button (num));
                    g.add_row (r);
                }
                detail.append (g);
            }
            if (c.emails.size > 0) {
                var g = new PreferencesGroup (_("Email"));
                foreach (var e in c.emails) {
                    var r = new ActionRow (e.value, kind_label (e.kind));
                    string addr = e.value;
                    var send = new Button.from_icon_name ("mail-send-symbolic");
                    send.add_css_class ("flat");
                    send.valign = Align.CENTER;
                    send.tooltip_text = _("Send Email");
                    send.clicked.connect (() => launch ("mailto:" + addr));
                    r.add_suffix (send);
                    r.add_suffix (copy_button (addr));
                    g.add_row (r);
                }
                detail.append (g);
            }
            if (c.addresses.size > 0) {
                var g = new PreferencesGroup (_("Address"));
                foreach (var a in c.addresses) {
                    string text = a.format ();
                    var r = new ActionRow (text, kind_label (a.kind));
                    var map = new Button.from_icon_name ("mark-location-symbolic");
                    map.add_css_class ("flat");
                    map.valign = Align.CENTER;
                    map.tooltip_text = _("Show on Map");
                    map.clicked.connect (() => launch ("geo:0,0?q=" + Uri.escape_string (text.replace ("\n", ", "), null, false)));
                    r.add_suffix (map);
                    r.add_suffix (copy_button (text));
                    g.add_row (r);
                }
                detail.append (g);
            }
            string[] mails = {};
            foreach (var e in c.emails) mails += e.value;
            var recent = ContactHub.recent_mail (mails);
            if (recent.size > 0) {
                var g = new PreferencesGroup (_("Recent Mail"));
                string first = c.display_name.split (" ")[0];
                foreach (var m in recent) {
                    int64 id = m.id;
                    string when = new DateTime.from_unix_local (m.date).format ("%-d %b %Y");
                    var r = new ActionRow (m.subject != "" ? m.subject : _("No Subject"), m.from_them ? _("From %s, %s").printf (first, when) : _("You wrote, %s").printf (when));
                    r.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                    r.activated.connect (() => ShareTargets.activate_app_action.begin ("dev.sinty.lettere", "show-message", new Variant.int64 (id)));
                    g.add_row (r);
                }
                detail.append (g);
            }
            var together = new PreferencesGroup (_("Upcoming Together"));
            together.visible = false;
            detail.append (together);
            ContactHub.upcoming_together.begin (mails, 60, (o, res) => {
                var events = ContactHub.upcoming_together.end (res);
                foreach (var e in events) {
                    string key = e.key;
                    string when = e.all_day ? e.start.format ("%A %-d %B") : e.start.format ("%A %-d %B, %H:%M");
                    var r = new ActionRow (e.title, when);
                    r.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                    r.activated.connect (() => ShareTargets.activate_app_action.begin ("dev.sinty.calendar", "open-event", new Variant.string (key)));
                    together.add_row (r);
                }
                together.visible = events.size > 0;
            });
            if (c.urls.size > 0 || c.birthday != "") {
                var g = new PreferencesGroup (_("More"));
                foreach (var u in c.urls) {
                    string link = u.value;
                    var r = new ActionRow (link, _("Website"));
                    var open = new Button.from_icon_name ("web-browser-symbolic");
                    open.add_css_class ("flat");
                    open.valign = Align.CENTER;
                    open.tooltip_text = _("Open");
                    open.clicked.connect (() => launch (link.contains ("://") ? link : "https://" + link));
                    r.add_suffix (open);
                    g.add_row (r);
                }
                if (c.birthday != "") g.add_row (new ActionRow (format_birthday (c.birthday), _("Birthday")));
                detail.append (g);
            }
            if (c.note != "") {
                detail.append (section_title (_("Notes")));
                var note = new Label (c.note);
                note.wrap = true;
                note.xalign = 0;
                note.selectable = true;
                note.add_css_class ("contacts-note");
                detail.append (note);
            }
            var book = library.book (c.source_id);
            if (book != null) {
                var from = new Label (_("Saved in %s").printf (book.full_name));
                from.add_css_class ("dim-label");
                from.add_css_class ("caption");
                detail.append (from);
            }
        }

        private void share_contact (Contact c) {
            string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity", "contacts-share");
            DirUtils.create_with_parents (dir, 0700);
            string name = (c.display_name != "" ? c.display_name : _("Contact")).replace ("/", "-");
            string path = Path.build_filename (dir, name + ".vcf");
            try {
                FileUtils.set_contents (path, VCard.serialize (c));
                FileUtils.chmod (path, 0600);
                Singularity.Share.files (this, { File.new_for_path (path) });
            } catch (Error e) {
                warning ("Contacts: share failed: %s", e.message);
            }
        }

        private static string[] non_empty (string[] items) {
            string[] out_v = {};
            foreach (string s in items) if (s.strip () != "") out_v += s.strip ();
            return out_v;
        }

        public static string format_birthday (string b) {
            int y = 0, m = 0, d = 0;
            if (b.has_prefix ("--") && b.length >= 7) {
                m = int.parse (b.substring (2, 2));
                d = int.parse (b.substring (5, 2));
            } else if (b.length >= 10) {
                y = int.parse (b.substring (0, 4));
                m = int.parse (b.substring (5, 2));
                d = int.parse (b.substring (8, 2));
            }
            if (m < 1 || m > 12 || d < 1 || d > 31) return b;
            var dt = new DateTime.local (y > 0 ? y : 2000, m, d, 0, 0, 0);
            if (dt == null) return b;
            if (y <= 0) return dt.format ("%e %B").strip ();
            var now = new DateTime.now_local ();
            int age = now.get_year () - y - ((now.get_month () < m || (now.get_month () == m && now.get_day_of_month () < d)) ? 1 : 0);
            return _("%s (%d years)").printf (dt.format ("%e %B %Y").strip (), age);
        }

        public delegate void Click ();

        private Button action_pill (string icon, string label, owned Click click) {
            Click f = (owned) click;
            var b = new Button ();
            b.add_css_class ("contacts-action");
            var box = new Box (Orientation.HORIZONTAL, 6);
            box.append (new Image.from_icon_name (icon));
            box.append (new Label (label));
            b.child = box;
            b.clicked.connect (() => f ());
            return b;
        }

        private void toggle_favorite () {
            if (current == null) return;
            var c = current.copy ();
            c.favorite = !c.favorite;
            save_contact.begin (c);
        }

        private async void save_contact (Contact c) {
            var book = library.book (c.source_id) ?? library.local;
            try {
                yield book.save (c);
                current = c;
                rebuild ();
            } catch (Error e) {
                show_error (_("Could Not Save the Contact"), e.message);
            }
        }

        private void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message (app, title, "dialog-error-symbolic", message);
            dlg.transient_for = this;
            dlg.present ();
        }

        private void new_contact () {
            if (editing) stop_edit (false);
            var c = new Contact ();
            c.source_id = "local";
            var b = library.book (filter_source);
            if (b != null && !b.read_only) c.source_id = filter_source;
            current = c;
            stack.visible_child_name = "main";
            list.unselect_all ();
            start_edit ();
        }

        private void start_edit () {
            if (current == null) return;
            editing = true;
            editor = new Editor (this, current.copy (), library);
            var box = new Box (Orientation.VERTICAL, 0);
            apply_view_edge (box);
            box.margin_bottom = 32;
            box.margin_start = 24;
            box.margin_end = 24;
            box.append (editor);
            detail_scroll.child = new Clamp (box) { maximum = 560 };
            sync_bubbles ();
            editor.focus_first ();
        }

        private void stop_edit (bool save) {
            if (!editing) return;
            editing = false;
            var ed = editor;
            editor = null;
            sync_bubbles ();
            if (save && ed != null) {
                var c = ed.result ();
                if (c.is_empty ()) {
                    rebuild ();
                    return;
                }
                save_contact.begin (c);
            } else {
                if (current != null && current.uid == "" ) current = null;
                rebuild ();
            }
        }

        private void show_more () {
            if (current == null) return;
            var menu = new ContextMenu (stack);
            Graphene.Rect bounds;
            if (more_bubble.compute_bounds (stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                menu.pointing_to = rect;
            }
            menu.position = PositionType.BOTTOM;
            var c = current;
            menu.add_item (c.favorite ? _("Remove from Favorites") : _("Add to Favorites"), c.favorite ? "non-starred-symbolic" : "starred-symbolic", () => toggle_favorite ());
            menu.add_item (_("Copy as Text"), "edit-copy-symbolic", () => get_clipboard ().set_text (plain_text (c)));
            menu.add_item (_("Save as vCard…"), "document-save-symbolic", () => export_contacts.begin (single (c), c.display_name));
            var moves = new Gee.ArrayList<AddressBook> ();
            foreach (var b in library.books) if (b.id != c.source_id && !b.read_only) moves.add (b);
            if (moves.size > 0) {
                var sub = menu.add_submenu (_("Move To"), "folder-symbolic");
                foreach (var b in moves) {
                    var target = b;
                    sub.add_item (b.full_name, null, () => move_contact.begin (c, target));
                }
            }
            menu.add_separator ();
            menu.add_item (_("Delete"), "user-trash-symbolic", () => confirm_delete (c), "destructive-action");
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private static Gee.List<Contact> single (Contact c) {
            var l = new Gee.ArrayList<Contact> ();
            l.add (c);
            return l;
        }

        private static string plain_text (Contact c) {
            var sb = new StringBuilder (c.display_name);
            if (c.org != "") sb.append ("\n" + c.org);
            foreach (var p in c.phones) sb.append ("\n" + p.value);
            foreach (var e in c.emails) sb.append ("\n" + e.value);
            foreach (var a in c.addresses) sb.append ("\n" + a.format ());
            return sb.str;
        }

        private async void move_contact (Contact c, AddressBook target) {
            var src = library.book (c.source_id);
            var copy = c.copy ();
            copy.source_id = target.id;
            copy.href = "";
            copy.etag = "";
            try {
                yield target.save (copy);
                if (src != null) yield src.remove (c);
                current = copy;
                rebuild ();
            } catch (Error e) {
                show_error (_("Could Not Move the Contact"), e.message);
            }
        }

        private void confirm_delete (Contact c) {
            var dlg = new ConfirmDialog (app, _("Delete %s?").printf (c.display_name != "" ? c.display_name : _("this contact")), "user-trash-symbolic",
                _("The contact is removed from %s.").printf (library.book (c.source_id) != null ? library.book (c.source_id).full_name : _("this address book")),
                _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                var book = library.book (c.source_id);
                if (book == null) return;
                ListBoxRow? gone = null;
                for (var child = list.get_first_child (); child != null; child = child.get_next_sibling ()) {
                    if (child.get_data<Contact> ("contact") == c) gone = child as ListBoxRow;
                }
                if (gone != null) animator.remove (gone, () => {});
                book.remove.begin (c, (o, res) => {
                    try {
                        book.remove.end (res);
                        current = null;
                        rebuild ();
                    } catch (Error e) {
                        show_error (_("Could Not Delete the Contact"), e.message);
                    }
                });
            });
            dlg.present ();
        }

        public void import_file () {
            var dialog = new FileDialog ();
            dialog.title = _("Import Contacts");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("vCard Files");
            f.add_pattern ("*.vcf");
            f.add_pattern ("*.vcard");
            f.add_mime_type ("text/vcard");
            f.add_mime_type ("text/x-vcard");
            filters.append (f);
            dialog.filters = filters;
            dialog.open_multiple.begin (this, null, (o, res) => {
                try {
                    var files = dialog.open_multiple.end (res);
                    for (uint i = 0; i < files.get_n_items (); i++) import_vcards.begin ((File) files.get_item (i));
                } catch (Error e) {
                }
            });
        }

        public async void import_vcards (File file) {
            try {
                uint8[] data;
                yield file.load_contents_async (null, out data, null);
                string text = (string) data;
                if (!text.validate ()) text = convert (text, -1, "UTF-8", "WINDOWS-1252");
                var parsed = VCard.parse (text);
                int n = 0;
                foreach (var c in parsed) {
                    bool exists = false;
                    foreach (var e in library.local.contacts) if (e.uid == c.uid) exists = true;
                    if (exists) c.uid = Uuid.string_random ();
                    c.href = "";
                    yield library.local.save (c);
                    n++;
                }
                rebuild ();
                list_status.label = ngettext ("%d contact imported", "%d contacts imported", n).printf (n);
                list_status.visible = true;
            } catch (Error e) {
                show_error (_("Could Not Import"), e.message);
            }
        }

        public async void export_contacts (Gee.List<Contact> items, string name) {
            var dialog = new FileDialog ();
            dialog.title = _("Save Contacts");
            dialog.initial_name = (name != "" ? name : _("Contacts")) + ".vcf";
            try {
                var file = yield dialog.save (this, null);
                var sb = new StringBuilder ();
                foreach (var c in items) sb.append (VCard.serialize (c));
                yield file.replace_contents_async (sb.str.data, null, false, FileCreateFlags.REPLACE_DESTINATION, null, null);
            } catch (Error e) {
                if (!(e is Gtk.DialogError)) show_error (_("Could Not Save"), e.message);
            }
        }

        private void open_accounts () {
            try {
                Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                shell.open_settings ("accounts");
            } catch (Error e) {
                show_error (_("Settings Are Not Available"), e.message);
            }
        }

        public delegate void Handler ();

        private void install_actions () {
            string[] names = { "new", "import", "export-all", "edit", "delete", "find", "refresh", "copy-text", "save-vcard", "online-accounts", "toggle-sidebar", "close" };
            foreach (string n in names) {
                var a = new SimpleAction (n, null);
                string name = n;
                a.activate.connect (() => {
                    switch (name) {
                        case "new": new_contact (); break;
                        case "import": import_file (); break;
                        case "export-all": export_contacts.begin (library.all (), _("Contacts")); break;
                        case "edit": start_edit (); break;
                        case "delete": if (current != null && !editing) confirm_delete (current); break;
                        case "favorite": toggle_favorite (); break;
                        case "find": search.grab_focus_entry (); break;
                        case "refresh": library.refresh.begin (); break;
                        case "copy-text": if (current != null) get_clipboard ().set_text (plain_text (current)); break;
                        case "save-vcard": if (current != null) export_contacts.begin (single (current), current.display_name); break;
                        case "online-accounts": open_accounts (); break;
                        case "toggle-sidebar": set_sidebar_visible (!get_sidebar_visible ()); break;
                        case "close": close (); break;
                    }
                });
                add_action (a);
            }
            var favorite = new SimpleAction.stateful ("favorite", null, new Variant.boolean (false));
            favorite.activate.connect (() => toggle_favorite ());
            add_action (favorite);
            var source = new SimpleAction.stateful ("source", VariantType.STRING, new Variant.string (filter_source));
            source.activate.connect ((v) => select_source (v.get_string ()));
            add_action (source);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Escape && editing) {
                    stop_edit (false);
                    return true;
                }
                if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) && (state & Gdk.ModifierType.CONTROL_MASK) != 0 && editing) {
                    stop_edit (true);
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
        }
    }
}
