namespace Singularity.Apps.Contacts {

    public class ContactsSearch : Singularity.SearchProviderService {
        private ContactsApp app;

        public ContactsSearch (ContactsApp app) {
            this.app = app;
        }

        private async void wait_ready () {
            if (app.library.started) return;
            bool done = false;
            SourceFunc resume = wait_ready.callback;
            ulong id = app.library.changed.connect (() => {
                if (!app.library.started || done) return;
                done = true;
                resume ();
            });
            uint timeout = 0;
            timeout = Timeout.add (1500, () => {
                timeout = 0;
                if (!done) {
                    done = true;
                    resume ();
                }
                return Source.REMOVE;
            });
            yield;
            app.library.disconnect (id);
            if (timeout != 0) Source.remove (timeout);
        }

        private static string key_of (Contact c) {
            return c.source_id + "/" + c.uid;
        }

        private Contact? find (string key) {
            foreach (var c in app.library.all ()) if (key_of (c) == key) return c;
            return null;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            yield wait_ready ();
            string[] ids = {};
            string[] starts = {};
            foreach (var c in app.library.all ()) {
                bool all = true;
                foreach (string t in terms) {
                    if (!c.matches (t)) {
                        all = false;
                        break;
                    }
                }
                if (!all) continue;
                string first = terms.length > 0 ? terms[0].casefold () : "";
                if (c.display_name.casefold ().has_prefix (first)) starts += key_of (c);
                else ids += key_of (c);
            }
            string[] result = {};
            foreach (string id in starts) result += id;
            foreach (string id in ids) result += id;
            return result;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            yield wait_ready ();
            Singularity.SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                var c = find (id);
                if (c == null) continue;
                var meta = new Singularity.SearchResultMeta (id, c.display_name != "" ? c.display_name : _("Unnamed"));
                string[] parts = {};
                if (c.phones.size > 0) parts += c.phones[0].value;
                if (c.emails.size > 0) parts += c.emails[0].value;
                if (parts.length == 0 && c.org != "") parts += c.org;
                if (parts.length > 0) meta.description = string.joinv ("  ", parts);
                if (c.photo != null && c.photo.length > 0) meta.icon = new BytesIcon (new Bytes (c.photo));
                if (c.phones.size > 0) meta.add_action ("copy-phone", _("Copy Phone Number"), "call-start-symbolic");
                if (c.emails.size > 0) {
                    meta.add_action ("copy-email", _("Copy Email Address"), "edit-copy-symbolic");
                    meta.add_action ("write", _("Write an Email"), "mail-send-symbolic");
                }
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            app.show_contact (id);
            return null;
        }

        public override async Singularity.SearchActivationReply? activate_action (string id, string action_id, string[] terms, uint32 timestamp) throws Error {
            yield wait_ready ();
            var c = find (id);
            if (c == null) return null;
            switch (action_id) {
                case "copy-phone":
                    if (c.phones.size > 0) return Singularity.SearchActivationReply.copy (c.phones[0].value);
                    break;
                case "copy-email":
                    if (c.emails.size > 0) return Singularity.SearchActivationReply.copy (c.emails[0].value);
                    break;
                case "write":
                    if (c.emails.size > 0) {
                        AppInfo.launch_default_for_uri ("mailto:" + Uri.escape_string (c.emails[0].value, "@", false), null);
                    }
                    break;
            }
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.activate ();
        }
    }
}
