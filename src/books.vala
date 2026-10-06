namespace Singularity.Apps.Contacts {

    public errordomain BookError {
        READ_ONLY,
        CONFLICT,
        FAILED
    }

    public abstract class AddressBook : Object {
        public string id { get; protected set; }
        public string name { get; protected set; }
        public string icon { get; protected set; default = "x-office-address-book-symbolic"; }
        public bool read_only { get; protected set; }
        public string status { get; protected set; default = ""; }
        public string account_name { get; protected set; default = ""; }
        public Gee.ArrayList<Contact> contacts = new Gee.ArrayList<Contact> ();

        public signal void changed ();

        public string full_name {
            owned get { return account_name != "" ? _("%s, %s").printf (name, account_name) : name; }
        }

        public abstract async void load ();
        public abstract async void save (Contact c) throws Error;
        public abstract async void remove (Contact c) throws Error;

        protected void replace (Contact c) {
            for (int i = 0; i < contacts.size; i++) {
                if (contacts[i].uid == c.uid) {
                    contacts[i] = c;
                    return;
                }
            }
            contacts.add (c);
        }
    }

    public class LocalBook : AddressBook {
        private string dir;
        private FileMonitor? monitor;
        private uint reload_id;
        private bool writing;

        public LocalBook (string? directory = null) {
            dir = directory ?? Path.build_filename (Environment.get_user_data_dir (), "singularity", "contacts");
            id = "local";
            name = _("On This Computer");
            icon = "computer-symbolic";
            DirUtils.create_with_parents (dir, 0700);
            try {
                monitor = File.new_for_path (dir).monitor_directory (FileMonitorFlags.NONE);
                monitor.changed.connect (() => {
                    if (writing) return;
                    if (reload_id != 0) Source.remove (reload_id);
                    reload_id = Timeout.add (300, () => {
                        reload_id = 0;
                        load.begin ();
                        return Source.REMOVE;
                    });
                });
            } catch (Error e) {
            }
        }

        public override async void load () {
            var list = new Gee.ArrayList<Contact> ();
            try {
                var d = Dir.open (dir);
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
                        c.source_id = id;
                        c.href = n;
                        list.add (c);
                    }
                }
            } catch (FileError e) {
            }
            contacts = list;
            changed ();
        }

        private static string safe (string uid) {
            var sb = new StringBuilder ();
            for (int i = 0; i < uid.length; i++) {
                char c = uid[i];
                sb.append_c (c.isalnum () || c == '-' || c == '_' ? c : '_');
            }
            return sb.str;
        }

        public override async void save (Contact c) throws Error {
            if (c.uid == "") c.uid = Uuid.string_random ();
            c.source_id = id;
            if (c.href == "") c.href = safe (c.uid) + ".vcf";
            writing = true;
            try {
                FileUtils.set_contents (Path.build_filename (dir, c.href), VCard.serialize (c));
            } finally {
                Timeout.add (500, () => {
                    writing = false;
                    return Source.REMOVE;
                });
            }
            replace (c);
            changed ();
        }

        public override async void remove (Contact c) throws Error {
            writing = true;
            FileUtils.remove (Path.build_filename (dir, c.href != "" ? c.href : safe (c.uid) + ".vcf"));
            Timeout.add (500, () => {
                writing = false;
                return Source.REMOVE;
            });
            for (int i = 0; i < contacts.size; i++) {
                if (contacts[i].uid == c.uid) {
                    contacts.remove_at (i);
                    break;
                }
            }
            changed ();
        }
    }

    public class Library : Object {
        public Gee.ArrayList<AddressBook> books = new Gee.ArrayList<AddressBook> ();
        public LocalBook local;
        private Singularity.Accounts.CollectionTracker? tracker;
        public bool started;

        public signal void changed ();

        public Library () {
            local = new LocalBook ();
            add_book (local);
        }

        private void add_book (AddressBook b) {
            books.add (b);
            b.changed.connect (() => changed ());
        }

        public async void start () {
            yield local.load ();
            tracker = new Singularity.Accounts.CollectionTracker (Singularity.Accounts.ContentKind.CONTACTS);
            tracker.set_added.connect ((cs) => sync_set (cs));
            tracker.collections_changed.connect ((cs) => sync_set (cs));
            tracker.set_removed.connect ((cs) => drop_account (cs.account.id));
            yield tracker.start ();
            foreach (var cs in tracker.get_sets ()) sync_set (cs);
            started = true;
            changed ();
        }

        private void sync_set (Singularity.Accounts.CollectionSet cs) {
            var ids = new Gee.HashSet<string> ();
            foreach (var col in cs.collections) {
                string bid = AccountBook.id_for (cs.account, col);
                ids.add (bid);
                if (book (bid) != null) continue;
                var b = new AccountBook (cs.account, col);
                add_book (b);
                b.reload ();
            }
            foreach (var b in books.to_array ()) {
                var ab = b as AccountBook;
                if (ab != null && ab.account.id == cs.account.id && !ids.contains (ab.id)) remove_book (ab);
            }
            books.sort ((a, b) => {
                if (a == local || b == local) return a == local ? -1 : (b == local ? 1 : 0);
                int r = strcmp (a.account_name.casefold (), b.account_name.casefold ());
                return r != 0 ? r : strcmp (a.name.casefold (), b.name.casefold ());
            });
            changed ();
        }

        private void drop_account (string account_id) {
            foreach (var b in books.to_array ()) {
                var ab = b as AccountBook;
                if (ab != null && ab.account.id == account_id) remove_book (ab);
            }
            changed ();
        }

        private void remove_book (AccountBook b) {
            b.detach ();
            books.remove (b);
        }

        public AddressBook? book (string id) {
            foreach (var b in books) if (b.id == id) return b;
            return null;
        }

        public Gee.List<Contact> all () {
            var list = new Gee.ArrayList<Contact> ();
            foreach (var b in books) list.add_all (b.contacts);
            list.sort ((a, b) => strcmp (a.sort_key, b.sort_key));
            return list;
        }

        public async void refresh () {
            yield local.load ();
            if (tracker != null) yield tracker.refresh_all ();
        }
    }
}
