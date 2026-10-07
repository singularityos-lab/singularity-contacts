using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Contacts {

    public class MailRef : Object {
        public int64 id;
        public string subject = "";
        public int64 date;
        public bool from_them;
    }

    public class EventRef : Object {
        public string title = "";
        public string key = "";
        public DateTime start;
        public bool all_day;
    }

    public class ContactHub : Object {
        public static string mail_db () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-lettere", "cache.db");
        }

        public static Gee.List<MailRef> recent_mail (string[] emails, int limit = 5) {
            var result = new Gee.ArrayList<MailRef> ();
            if (emails.length == 0 || !FileUtils.test (mail_db (), FileTest.EXISTS)) return result;
            Sqlite.Database db;
            if (Sqlite.Database.open_v2 (mail_db (), out db, Sqlite.OPEN_READONLY) != Sqlite.OK) return result;
            var where = new StringBuilder ();
            for (int i = 0; i < emails.length; i++) {
                if (i > 0) where.append (" OR ");
                where.append ("lower(sender_email) = ? OR lower(to_list) LIKE ? OR lower(cc_list) LIKE ?");
            }
            string sql = "SELECT id, subject, date, sender_email FROM messages WHERE %s ORDER BY date DESC LIMIT %d".printf (where.str, limit * 3);
            Sqlite.Statement st;
            if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) return result;
            int n = 1;
            foreach (string e in emails) {
                string low = e.down ();
                st.bind_text (n++, low);
                st.bind_text (n++, "%" + low + "%");
                st.bind_text (n++, "%" + low + "%");
            }
            var seen = new Gee.HashSet<string> ();
            while (st.step () == Sqlite.ROW && result.size < limit) {
                var m = new MailRef ();
                m.id = st.column_int64 (0);
                m.subject = st.column_text (1) ?? "";
                m.date = st.column_int64 (2);
                string sender = (st.column_text (3) ?? "").down ();
                m.from_them = false;
                foreach (string e in emails) if (e.down () == sender) m.from_them = true;
                string key = m.subject + m.date.to_string ();
                if (seen.contains (key)) continue;
                seen.add (key);
                result.add (m);
            }
            return result;
        }

        public static async Gee.List<EventRef> upcoming_together (string[] emails, int days = 60) {
            var result = new Gee.ArrayList<EventRef> ();
            string[] wanted = {};
            foreach (string mail in emails) wanted += mail.down ();
            if (wanted.length == 0) return result;
            var mgr = Singularity.Calendar.CalendarManager.get_default ();
            Singularity.Calendar.LocalProvider.register_all (mgr);
            var now = new DateTime.now_local ();
            var events = yield mgr.get_events (now, now.add_days (days));
            for (int i = 0; i < events.size; i++) {
                Singularity.Calendar.CalendarEvent? e = events[i];
                if (e == null) continue;
                bool hit = false;
                foreach (string low in wanted) {
                    if (e.organizer != null && e.organizer.down ().replace ("mailto:", "") == low) hit = true;
                    if (e.attendees != null) {
                        foreach (var a in e.attendees) if (a.email.down ().replace ("mailto:", "") == low) hit = true;
                    }
                }
                if (!hit) continue;
                var r = new EventRef ();
                r.title = e.title ?? "";
                r.start = e.start_time;
                r.all_day = e.all_day;
                r.key = "%s\t%s\t%s".printf (e.calendar_id ?? "", e.id ?? "", e.start_time.to_unix ().to_string ());
                result.add (r);
            }
            result.sort ((a, b) => a.start.compare (b.start));
            while (result.size > 5) result.remove_at (result.size - 1);
            return result;
        }
    }
}
