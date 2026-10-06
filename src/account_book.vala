using Singularity.Accounts;

namespace Singularity.Apps.Contacts {

    public class AccountBook : AddressBook {
        public Account account { get; private set; }
        public SyncedCollection collection { get; private set; }
        private ulong items_handler;
        private ulong offline_handler;
        private ulong error_handler;
        private ulong account_handler;

        private const string[] MANAGED = {
            "FN", "N", "NICKNAME", "ORG", "TITLE", "TEL", "EMAIL", "URL", "ADR", "BDAY", "NOTE",
            "CATEGORIES", "PHOTO", "REV", "X-SINGULARITY-FAVORITE"
        };

        private const string[] KEPT = { "VERSION", "UID", "PRODID" };

        private const string[] MATCHED = { "TEL", "EMAIL", "URL", "ADR" };

        public AccountBook (Account account, SyncedCollection collection) {
            this.account = account;
            this.collection = collection;
            id = id_for (account, collection);
            name = collection.name != "" ? collection.name : _("Contacts");
            account_name = account.display_name;
            icon = account.symbolic_icon_name;
            read_only = collection.read_only;
            items_handler = collection.changed.connect (() => reload ());
            offline_handler = collection.notify["offline"].connect (() => update_status ());
            error_handler = collection.notify["last-error"].connect (() => update_status ());
            account_handler = account.changed.connect (() => {
                account_name = account.display_name;
                update_status ();
                changed ();
            });
            update_status ();
        }

        public static string id_for (Account account, SyncedCollection collection) {
            string hash = Checksum.compute_for_string (ChecksumType.SHA1, collection.remote.id);
            return "account-" + account.id + "-" + hash.substring (0, 12);
        }

        public void detach () {
            if (items_handler != 0) collection.disconnect (items_handler);
            if (offline_handler != 0) collection.disconnect (offline_handler);
            if (error_handler != 0) collection.disconnect (error_handler);
            if (account_handler != 0) account.disconnect (account_handler);
            items_handler = offline_handler = error_handler = account_handler = 0;
        }

        private void update_status () {
            string s = "";
            if (!account.healthy) s = _("Sign in again in Settings");
            else if (collection.offline) s = _("Offline, changes will sync later");
            else if (collection.last_error != "") s = _("Could not sync: %s").printf (collection.last_error);
            if (s == status) return;
            status = s;
            changed ();
        }

        public void reload () {
            var list = new Gee.ArrayList<Contact> ();
            foreach (var item in collection.items ()) {
                if (!item.data.contains ("BEGIN:VCARD")) continue;
                var c = VCard.parse_one (item.data);
                c.source_id = id;
                c.href = item.uid;
                c.etag = item.etag;
                list.add (c);
            }
            contacts = list;
            read_only = collection.read_only;
            update_status ();
            changed ();
        }

        public override async void load () {
            reload ();
            yield collection.sync ();
        }

        private string key_of (Contact c) {
            return c.href != "" ? c.href : c.uid;
        }

        public override async void save (Contact c) throws Error {
            if (collection.read_only) throw new BookError.READ_ONLY (_("This address book is read-only."));
            if (c.uid == "") c.uid = Uuid.string_random ();
            string key = key_of (c);
            var previous = collection.get_item (key);
            string text = compose (c, previous != null ? previous.data : null);
            c.source_id = id;
            c.href = key;
            collection.put (key, text);
        }

        public override async void remove (Contact c) throws Error {
            if (collection.read_only) throw new BookError.READ_ONLY (_("This address book is read-only."));
            collection.remove (key_of (c));
        }

        private static string types_of (ContentLine line) {
            var parts = new Gee.TreeSet<string> ();
            foreach (string p in (line.param ("TYPE") ?? "").down ().split (",")) {
                string t = p.strip ();
                if (t == "mobile" || t == "iphone") t = "cell";
                if (t == "" || t == "internet" || t == "voice" || t == "pref" || t == "other") continue;
                parts.add (t);
            }
            return string.joinv (",", parts.to_array ());
        }

        public static string compose (Contact c, string? previous) {
            string fresh = VCard.serialize (c);
            if (previous == null || previous == "") return fresh;
            var old_card = Component.parse (previous);
            var new_card = Component.parse (fresh);
            if (old_card == null || new_card == null || old_card.name != "VCARD") return fresh;
            var before = VCard.parse_one (previous);
            bool keep_photo = before.photo == null && c.photo == null;
            var replaced = new Gee.HashSet<string> ();
            foreach (var line in new_card.lines) if (!(line.name in KEPT)) replaced.add (line.name);
            foreach (string n in MANAGED) if (n != "PHOTO" || !keep_photo) replaced.add (n);
            var old_lines = new Gee.ArrayList<ContentLine> ();
            old_lines.add_all (old_card.lines);
            var result = new Gee.ArrayList<ContentLine> ();
            foreach (var line in old_card.lines) if (!replaced.contains (line.name)) result.add (line);
            foreach (var line in new_card.lines) {
                if (line.name in KEPT) {
                    if (old_card.get_line (line.name) == null) result.add (line);
                    continue;
                }
                if (line.name == "PHOTO" && keep_photo) continue;
                ContentLine? same = null;
                if (line.name in MATCHED) {
                    foreach (var o in old_lines) {
                        if (o.name == line.name && o.text.strip () == line.text.strip () && types_of (o) == types_of (line)) {
                            same = o;
                            break;
                        }
                    }
                }
                if (same != null) {
                    old_lines.remove (same);
                    result.add (same);
                } else {
                    result.add (line);
                }
            }
            old_card.lines = result;
            return old_card.to_string ();
        }
    }
}
