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
        public static async Gee.List<MailRef> recent_mail (string[] emails, int limit = 5) {
            var result = new Gee.ArrayList<MailRef> ();
            if (emails.length == 0 || !Capabilities.available (Contracts.MAIL)) return result;
            try {
                var reply = yield Capabilities.call (Contracts.MAIL, "RecentMessagesWith", new Variant ("(^asi)", emails, limit), new VariantType ("(a(xsxb))"), 10000);
                var iter = reply.get_child_value (0).iterator ();
                int64 id, date;
                string subject;
                bool from_them;
                while (iter.next ("(xsxb)", out id, out subject, out date, out from_them)) {
                    var m = new MailRef ();
                    m.id = id;
                    m.subject = subject;
                    m.date = date;
                    m.from_them = from_them;
                    result.add (m);
                }
            } catch (Error e) {
                debug ("Contacts: recent mail: %s", e.message);
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
