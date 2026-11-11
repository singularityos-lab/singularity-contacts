namespace Singularity.Apps.Contacts {

    internal class ContactsIntents : Object {
        private const string FIELDS = "\"given\":{\"type\":\"string\"},\"family\":{\"type\":\"string\"},\"nickname\":{\"type\":\"string\"},\"organization\":{\"type\":\"string\"},\"title\":{\"type\":\"string\"},\"birthday\":{\"type\":\"string\"},\"note\":{\"type\":\"string\"},\"favorite\":{\"type\":\"boolean\"},\"phones\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"emails\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}";

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static async void ready(ContactsApp app) {
            int waited = 0;
            while (!app.library.started && waited < 100) {
                Timeout.add(50, ready.callback);
                yield;
                waited++;
            }
        }

        private static void fields(Json.Builder b, string name, Gee.List<Field> list) {
            b.set_member_name(name).begin_array();
            foreach (var f in list) {
                b.begin_object();
                b.set_member_name("kind").add_string_value(f.kind);
                b.set_member_name("value").add_string_value(f.value);
                b.end_object();
            }
            b.end_array();
        }

        private static void summary(Json.Builder b, Contact c, ContactsApp app, bool full) {
            b.begin_object();
            b.set_member_name("id").add_string_value(c.uid);
            b.set_member_name("name").add_string_value(c.display_name);
            var book = app.library.book(c.source_id);
            b.set_member_name("book").add_string_value(book != null ? book.full_name : c.source_id);
            if (c.org != "") b.set_member_name("organization").add_string_value(c.org);
            if (c.title != "") b.set_member_name("title").add_string_value(c.title);
            if (c.birthday != "") b.set_member_name("birthday").add_string_value(c.birthday);
            if (c.favorite) b.set_member_name("favorite").add_boolean_value(true);
            fields(b, "phones", c.phones);
            fields(b, "emails", c.emails);
            if (full) {
                if (c.given != "") b.set_member_name("given").add_string_value(c.given);
                if (c.family != "") b.set_member_name("family").add_string_value(c.family);
                if (c.nickname != "") b.set_member_name("nickname").add_string_value(c.nickname);
                fields(b, "urls", c.urls);
                b.set_member_name("addresses").begin_array();
                foreach (var a in c.addresses) {
                    b.begin_object();
                    b.set_member_name("kind").add_string_value(a.kind);
                    b.set_member_name("text").add_string_value(a.format());
                    b.end_object();
                }
                b.end_array();
                if (c.note != "") b.set_member_name("note").add_string_value(c.note);
                b.set_member_name("has_photo").add_boolean_value(c.photo != null);
            }
            b.end_object();
        }

        private static Contact find(ContactsApp app, string id) throws Error {
            if (id == "") throw new IOError.INVALID_ARGUMENT("give the contact id");
            foreach (var c in app.library.all()) if (c.uid == id) return c;
            Contact? match = null;
            foreach (var c in app.library.all()) {
                if (c.display_name.casefold() == id.casefold()) {
                    if (match != null) throw new IOError.INVALID_ARGUMENT("more than one contact is called %s: use the id", id);
                    match = c;
                }
            }
            if (match == null) throw new IOError.NOT_FOUND("no contact %s; find it with contacts_search", id);
            return match;
        }

        private static void apply(Contact c, Json.Object args) {
            if (args.has_member("given")) c.given = text(args, "given");
            if (args.has_member("family")) c.family = text(args, "family");
            if (args.has_member("nickname")) c.nickname = text(args, "nickname");
            if (args.has_member("organization")) c.org = text(args, "organization");
            if (args.has_member("title")) c.title = text(args, "title");
            if (args.has_member("birthday")) c.birthday = VCard.normalize_date(text(args, "birthday"));
            if (args.has_member("note")) c.note = args.get_string_member("note");
            if (args.has_member("favorite")) c.favorite = args.get_boolean_member("favorite");
            if (args.has_member("given") || args.has_member("family")) c.formatted = "";
            if (args.has_member("phones")) {
                c.phones.clear();
                foreach (var e in args.get_array_member("phones").get_elements()) {
                    string v = e.get_string().strip();
                    if (v != "") c.phones.add(new Field("cell", v));
                }
            }
            if (args.has_member("emails")) {
                c.emails.clear();
                foreach (var e in args.get_array_member("emails").get_elements()) {
                    string v = e.get_string().strip();
                    if (v != "") c.emails.add(new Field("home", v));
                }
            }
        }

        private static async void search(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            string q = text(args, "query");
            int64 limit = args.has_member("limit") ? args.get_int_member("limit").clamp(1, 200) : 20;
            bool favorites = args.has_member("favorites") && args.get_boolean_member("favorites");
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("contacts").begin_array();
            int total = 0;
            foreach (var c in app.library.all()) {
                if (favorites && !c.favorite) continue;
                if (!c.matches(q)) continue;
                if (total++ < limit) summary(b, c, app, false);
            }
            b.end_array();
            b.set_member_name("total").add_int_value(total);
            b.end_object();
            reply(b.get_root(), null);
        }

        private static async void get_one(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            try {
                var c = find(app, text(args, "id"));
                var b = new Json.Builder();
                summary(b, c, app, true);
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            }
        }

        private static async void add(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            app.hold();
            try {
                string book_id = text(args, "book");
                var book = app.library.book(book_id != "" ? book_id : "local");
                if (book == null) throw new IOError.NOT_FOUND("no address book %s", book_id);
                if (book.read_only) throw new IOError.PERMISSION_DENIED("%s is read only", book.full_name);
                Contact c;
                if (text(args, "vcard") != "") {
                    c = VCard.parse_one(args.get_string_member("vcard"));
                    c.href = "";
                    c.etag = "";
                } else {
                    c = new Contact();
                }
                apply(c, args);
                if (c.is_empty()) throw new IOError.INVALID_ARGUMENT("give at least a name, a phone or an email");
                foreach (var other in app.library.all()) {
                    if (c.uid != "" && other.uid == c.uid) throw new IOError.EXISTS("a contact with id %s already exists", c.uid);
                }
                yield book.save(c);
                Contact? saved = null;
                foreach (var x in book.contacts) if (x.uid == c.uid) saved = x;
                if (saved == null) throw new IOError.FAILED("the contact was not saved");
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("contact");
                summary(b, saved, app, true);
                b.set_member_name("undo").add_string_value("contacts_delete with id " + saved.uid);
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void update(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            app.hold();
            try {
                var original = find(app, text(args, "id"));
                var book = app.library.book(original.source_id);
                if (book == null || book.read_only) throw new IOError.PERMISSION_DENIED("this contact cannot be changed");
                string before = VCard.serialize(original);
                var c = original.copy();
                apply(c, args);
                if (c.is_empty()) throw new IOError.INVALID_ARGUMENT("the contact would be empty");
                yield book.save(c);
                var after = find(app, c.uid);
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("contact");
                summary(b, after, app, true);
                b.set_member_name("previous_vcard").add_string_value(before);
                b.set_member_name("undo").add_string_value("contacts_restore with id %s and previous_vcard".printf(c.uid));
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void restore(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            app.hold();
            try {
                var original = find(app, text(args, "id"));
                var book = app.library.book(original.source_id);
                if (book == null || book.read_only) throw new IOError.PERMISSION_DENIED("this contact cannot be changed");
                var c = VCard.parse_one(text(args, "vcard"));
                if (c.uid != original.uid) throw new IOError.INVALID_ARGUMENT("the vCard belongs to another contact");
                c.source_id = original.source_id;
                c.href = original.href;
                c.etag = original.etag;
                yield book.save(c);
                var b = new Json.Builder();
                summary(b, find(app, c.uid), app, true);
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void delete_one(ContactsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            yield ready(app);
            app.hold();
            try {
                var c = find(app, text(args, "id"));
                var book = app.library.book(c.source_id);
                if (book == null || book.read_only) throw new IOError.PERMISSION_DENIED("this contact cannot be deleted");
                string card = VCard.serialize(c);
                yield book.remove(c);
                foreach (var x in book.contacts) if (x.uid == c.uid) throw new IOError.FAILED("the contact is still there");
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("deleted").add_string_value(c.display_name);
                b.set_member_name("book").add_string_value(book.id);
                b.set_member_name("vcard").add_string_value(card);
                b.set_member_name("undo").add_string_value("contacts_add with book %s and this vcard".printf(book.id));
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        internal static void install(ContactsApp app) {
            var agent = app.agent;
            agent.add_intent("contacts_books", "List the address books: this computer and every account that syncs contacts.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_array();
                    foreach (var book in app.library.books) {
                        b.begin_object();
                        b.set_member_name("id").add_string_value(book.id);
                        b.set_member_name("name").add_string_value(book.full_name);
                        b.set_member_name("read_only").add_boolean_value(book.read_only);
                        b.set_member_name("contacts").add_int_value(book.contacts.size);
                        if (book.status != "") b.set_member_name("status").add_string_value(book.status);
                        b.end_object();
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_async_intent("contacts_search", "Find contacts by name, organization, phone digits, email, address or note. An empty query lists everyone.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"favorites\":{\"type\":\"boolean\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    search.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("contacts_get", "Every detail of one contact, by id or exact name.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    get_one.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("contacts_add", "Create a contact in an address book (this computer unless book is given). A vcard brings back a deleted contact.",
                "{\"type\":\"object\",\"properties\":{" + FIELDS + ",\"book\":{\"type\":\"string\"},\"vcard\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    add.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("contacts_update", "Change fields of a contact. phones and emails replace the whole list.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}," + FIELDS + "},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    update.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("contacts_restore", "Put a contact back as it was, from the previous_vcard a contacts_update returned.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"vcard\":{\"type\":\"string\"}},\"required\":[\"id\",\"vcard\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    restore.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("contacts_delete", "Delete a contact. The answer carries its vCard so contacts_add can bring it back.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    delete_one.begin(app, args, (owned) reply);
                });
        }
    }
}
