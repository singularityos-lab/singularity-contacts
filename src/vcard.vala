namespace Singularity.Apps.Contacts {

    public class Field : Object {
        public string kind;
        public string value;

        public Field (string kind, string value) {
            this.kind = kind;
            this.value = value;
        }
    }

    public class PostalAddress : Object {
        public string kind = "home";
        public string street = "";
        public string city = "";
        public string region = "";
        public string postal = "";
        public string country = "";

        public string format () {
            string[] lines = {};
            if (street != "") lines += street;
            string line2 = string.joinv (" ", strip_empty ({ postal, city }));
            if (region != "") line2 = line2 != "" ? line2 + ", " + region : region;
            if (line2 != "") lines += line2;
            if (country != "") lines += country;
            return string.joinv ("\n", lines);
        }

        private static string[] strip_empty (string[] items) {
            string[] out_v = {};
            foreach (string s in items) if (s.strip () != "") out_v += s.strip ();
            return out_v;
        }

        public bool is_empty () {
            return (street + city + region + postal + country).strip () == "";
        }
    }

    public class Contact : Object {
        public string uid = "";
        public string given = "";
        public string family = "";
        public string additional = "";
        public string prefix = "";
        public string suffix = "";
        public string formatted = "";
        public string nickname = "";
        public string org = "";
        public string title = "";
        public string note = "";
        public string birthday = "";
        public uint8[]? photo;
        public string photo_type = "jpeg";
        public bool favorite;
        public Gee.ArrayList<Field> phones = new Gee.ArrayList<Field> ();
        public Gee.ArrayList<Field> emails = new Gee.ArrayList<Field> ();
        public Gee.ArrayList<Field> urls = new Gee.ArrayList<Field> ();
        public Gee.ArrayList<PostalAddress> addresses = new Gee.ArrayList<PostalAddress> ();
        public Gee.ArrayList<string> categories = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> extra = new Gee.ArrayList<string> ();
        public string source_id = "";
        public string href = "";
        public string etag = "";

        public string display_name {
            owned get {
                if (formatted.strip () != "") return formatted.strip ();
                string n = string.joinv (" ", parts ({ prefix, given, additional, family, suffix }));
                if (n != "") return n;
                if (nickname != "") return nickname;
                if (org != "") return org;
                if (emails.size > 0) return emails[0].value;
                if (phones.size > 0) return phones[0].value;
                return "";
            }
        }

        public string sort_key {
            owned get {
                string k = family != "" ? family + " " + given : display_name;
                return k.casefold ().normalize (-1, NormalizeMode.ALL);
            }
        }

        public string initials {
            owned get {
                var sb = new StringBuilder ();
                string first = given != "" ? given : display_name;
                string last = family;
                if (first.strip () != "") sb.append_unichar (first.strip ().get_char (0).toupper ());
                if (last.strip () != "") sb.append_unichar (last.strip ().get_char (0).toupper ());
                else {
                    string[] words = display_name.strip ().split (" ");
                    if (words.length > 1 && words[words.length - 1] != "") sb.append_unichar (words[words.length - 1].get_char (0).toupper ());
                }
                return sb.str;
            }
        }

        private static string[] parts (string[] items) {
            string[] out_v = {};
            foreach (string s in items) if (s.strip () != "") out_v += s.strip ();
            return out_v;
        }

        public bool matches (string query) {
            string q = query.strip ().casefold ();
            if (q == "") return true;
            if (display_name.casefold ().contains (q) || nickname.casefold ().contains (q) || org.casefold ().contains (q)) return true;
            string digits = only_digits (q);
            foreach (var f in phones) {
                if (f.value.casefold ().contains (q)) return true;
                if (digits.length >= 3 && only_digits (f.value).contains (digits)) return true;
            }
            foreach (var f in emails) if (f.value.casefold ().contains (q)) return true;
            foreach (var a in addresses) if (a.format ().casefold ().contains (q)) return true;
            return note.casefold ().contains (q);
        }

        private static string only_digits (string s) {
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) if (s[i].isdigit ()) sb.append_c (s[i]);
            return sb.str;
        }

        public Contact copy () {
            var c = VCard.parse_one (VCard.serialize (this));
            c.source_id = source_id;
            c.href = href;
            c.etag = etag;
            return c;
        }

        public bool is_empty () {
            return display_name == "" && photo == null && note == "";
        }
    }

    public class VCard {
        public static string escape (string s) {
            return s.replace ("\\", "\\\\").replace ("\n", "\\n").replace (",", "\\,").replace (";", "\\;");
        }

        public static string unescape (string s) {
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '\\' && i + 1 < s.length) {
                    char n = s[++i];
                    if (n == 'n' || n == 'N') sb.append_c ('\n');
                    else sb.append_c (n);
                } else {
                    sb.append_c (c);
                }
            }
            return sb.str;
        }

        public static string[] split_escaped (string s, char sep) {
            string[] parts = {};
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '\\' && i + 1 < s.length) {
                    sb.append_c (c);
                    sb.append_c (s[++i]);
                    continue;
                }
                if (c == sep) {
                    parts += unescape (sb.str);
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            parts += unescape (sb.str);
            return parts;
        }

        private static string[] unfold (string text) {
            string[] lines = {};
            var cur = new StringBuilder ();
            foreach (string raw in text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n")) {
                if ((raw.has_prefix (" ") || raw.has_prefix ("\t")) && cur.len > 0) {
                    cur.append (raw.substring (1));
                    continue;
                }
                if (cur.len > 0) lines += cur.str;
                cur.truncate ();
                cur.append (raw);
            }
            if (cur.len > 0) lines += cur.str;
            return lines;
        }

        private static void split_line (string line, out string name, out Gee.HashMap<string, string> params, out string value) {
            params = new Gee.HashMap<string, string> ();
            int colon = -1;
            bool quote = false;
            for (int i = 0; i < line.length; i++) {
                if (line[i] == '"') quote = !quote;
                else if (line[i] == ':' && !quote) {
                    colon = i;
                    break;
                }
            }
            if (colon < 0) {
                name = line.up ();
                value = "";
                return;
            }
            string head = line.substring (0, colon);
            value = line.substring (colon + 1);
            string[] items = head.split (";");
            name = items[0].up ();
            int dot = name.index_of (".");
            if (dot >= 0) name = name.substring (dot + 1);
            for (int i = 1; i < items.length; i++) {
                string p = items[i];
                int eq = p.index_of ("=");
                string key = eq > 0 ? p.substring (0, eq).up () : "TYPE";
                string val = eq > 0 ? p.substring (eq + 1).replace ("\"", "") : p;
                if (params.has_key (key)) params[key] = params[key] + "," + val;
                else params[key] = val;
            }
        }

        private static string kind_of (Gee.HashMap<string, string> params, string fallback) {
            if (!params.has_key ("TYPE")) return fallback;
            string t = params["TYPE"].down ();
            string[] known = { "cell", "mobile", "work", "home", "fax", "pager", "main", "iphone", "other" };
            foreach (string part in t.split (",")) {
                foreach (string k in known) {
                    if (part.strip () == k) return k == "mobile" || k == "iphone" ? "cell" : k;
                }
            }
            return fallback;
        }

        public static Gee.List<Contact> parse (string text) {
            var list = new Gee.ArrayList<Contact> ();
            Contact? cur = null;
            foreach (string line in unfold (text)) {
                if (line.strip () == "") continue;
                string name, value;
                Gee.HashMap<string, string> params;
                split_line (line, out name, out params, out value);
                if (name == "BEGIN" && value.up () == "VCARD") {
                    cur = new Contact ();
                    continue;
                }
                if (cur == null) continue;
                if (name == "END") {
                    if (cur.uid == "") cur.uid = Uuid.string_random ();
                    list.add (cur);
                    cur = null;
                    continue;
                }
                apply (cur, name, params, value, line);
            }
            return list;
        }

        public static Contact parse_one (string text) {
            var l = parse (text);
            return l.size > 0 ? l[0] : new Contact ();
        }

        private static void apply (Contact c, string name, Gee.HashMap<string, string> params, string value, string raw) {
            switch (name) {
                case "VERSION":
                case "PRODID":
                case "REV":
                    break;
                case "UID":
                    c.uid = unescape (value);
                    if (c.uid.has_prefix ("urn:uuid:")) c.uid = c.uid.substring (9);
                    break;
                case "FN":
                    c.formatted = unescape (value);
                    break;
                case "N":
                    var p = split_escaped (value, ';');
                    if (p.length > 0) c.family = p[0];
                    if (p.length > 1) c.given = p[1];
                    if (p.length > 2) c.additional = p[2];
                    if (p.length > 3) c.prefix = p[3];
                    if (p.length > 4) c.suffix = p[4];
                    break;
                case "NICKNAME":
                    c.nickname = split_escaped (value, ',')[0];
                    break;
                case "ORG":
                    c.org = string.joinv (", ", strip_list (split_escaped (value, ';')));
                    break;
                case "TITLE":
                    c.title = unescape (value);
                    break;
                case "NOTE":
                    c.note = unescape (value);
                    break;
                case "BDAY":
                    c.birthday = normalize_date (unescape (value));
                    break;
                case "TEL":
                    string tel = value.has_prefix ("tel:") ? value.substring (4) : unescape (value);
                    c.phones.add (new Field (kind_of (params, "cell"), tel));
                    break;
                case "EMAIL":
                    c.emails.add (new Field (kind_of (params, "home"), unescape (value)));
                    break;
                case "URL":
                    c.urls.add (new Field (kind_of (params, "home"), unescape (value)));
                    break;
                case "ADR":
                    var a = split_escaped (value, ';');
                    var adr = new PostalAddress ();
                    adr.kind = kind_of (params, "home");
                    if (a.length > 2) adr.street = string.joinv ("\n", strip_list ({ a[0], a[1], a[2] }));
                    if (a.length > 3) adr.city = a[3];
                    if (a.length > 4) adr.region = a[4];
                    if (a.length > 5) adr.postal = a[5];
                    if (a.length > 6) adr.country = a[6];
                    if (!adr.is_empty ()) c.addresses.add (adr);
                    break;
                case "CATEGORIES":
                    foreach (string cat in split_escaped (value, ',')) {
                        string t = cat.strip ();
                        if (t == "") continue;
                        if (t.casefold () == "starred" || t.casefold () == "favorites") c.favorite = true;
                        else c.categories.add (t);
                    }
                    break;
                case "X-SINGULARITY-FAVORITE":
                    c.favorite = value.strip () == "1" || value.strip ().down () == "true";
                    break;
                case "PHOTO":
                    decode_photo (c, params, value);
                    break;
                default:
                    c.extra.add (raw);
                    break;
            }
        }

        private static string[] strip_list (string[] items) {
            string[] out_v = {};
            foreach (string s in items) if (s.strip () != "") out_v += s.strip ();
            return out_v;
        }

        public static string normalize_date (string v) {
            string s = v.strip ();
            if (s.has_prefix ("--")) {
                string md = s.substring (2).replace ("-", "");
                if (md.length == 4) return "--" + md.substring (0, 2) + "-" + md.substring (2, 2);
                return s;
            }
            int t = s.index_of ("T");
            if (t > 0) s = s.substring (0, t);
            if (s.length == 8 && !s.contains ("-")) return s.substring (0, 4) + "-" + s.substring (4, 2) + "-" + s.substring (6, 2);
            return s;
        }

        private static void decode_photo (Contact c, Gee.HashMap<string, string> params, string value) {
            string v = value;
            if (v.has_prefix ("data:")) {
                int comma = v.index_of (",");
                string meta = v.substring (5, comma - 5);
                if (meta.has_prefix ("image/")) c.photo_type = meta.substring (6, meta.index_of (";") > 0 ? meta.index_of (";") - 6 : meta.length - 6);
                c.photo = Base64.decode (v.substring (comma + 1));
                return;
            }
            string enc = params.has_key ("ENCODING") ? params["ENCODING"].up () : "";
            if (enc == "B" || enc == "BASE64") {
                if (params.has_key ("TYPE")) c.photo_type = params["TYPE"].down ().replace ("image/", "");
                c.photo = Base64.decode (v);
            }
        }

        private static string fold (string line) {
            if (line.length <= 75) return line + "\r\n";
            var sb = new StringBuilder ();
            int pos = 0;
            bool first = true;
            while (pos < line.length) {
                int take = first ? 75 : 74;
                int end = int.min (pos + take, line.length);
                while (end < line.length && end > pos && ((uchar) line[end] & 0xC0) == 0x80) end--;
                if (!first) sb.append_c (' ');
                sb.append (line.substring (pos, end - pos));
                sb.append ("\r\n");
                pos = end;
                first = false;
            }
            return sb.str;
        }

        private static string type_param (string kind) {
            switch (kind) {
                case "cell": return "CELL";
                case "work": return "WORK";
                case "home": return "HOME";
                case "fax": return "FAX";
                case "pager": return "PAGER";
                case "main": return "MAIN";
                default: return "OTHER";
            }
        }

        public static string serialize (Contact c) {
            var sb = new StringBuilder ();
            sb.append ("BEGIN:VCARD\r\nVERSION:3.0\r\n");
            sb.append (fold ("UID:" + escape (c.uid != "" ? c.uid : Uuid.string_random ())));
            sb.append (fold ("FN:" + escape (c.display_name)));
            sb.append (fold ("N:" + escape (c.family) + ";" + escape (c.given) + ";" + escape (c.additional) + ";" + escape (c.prefix) + ";" + escape (c.suffix)));
            if (c.nickname != "") sb.append (fold ("NICKNAME:" + escape (c.nickname)));
            if (c.org != "") sb.append (fold ("ORG:" + escape (c.org)));
            if (c.title != "") sb.append (fold ("TITLE:" + escape (c.title)));
            foreach (var p in c.phones) if (p.value.strip () != "") sb.append (fold ("TEL;TYPE=" + type_param (p.kind) + ":" + escape (p.value.strip ())));
            foreach (var e in c.emails) if (e.value.strip () != "") sb.append (fold ("EMAIL;TYPE=INTERNET," + type_param (e.kind) + ":" + escape (e.value.strip ())));
            foreach (var a in c.addresses) {
                if (a.is_empty ()) continue;
                sb.append (fold ("ADR;TYPE=" + type_param (a.kind) + ":;;" + escape (a.street) + ";" + escape (a.city) + ";" + escape (a.region) + ";" + escape (a.postal) + ";" + escape (a.country)));
            }
            foreach (var u in c.urls) if (u.value.strip () != "") sb.append (fold ("URL:" + escape (u.value.strip ())));
            if (c.birthday != "") sb.append (fold ("BDAY:" + c.birthday));
            if (c.note != "") sb.append (fold ("NOTE:" + escape (c.note)));
            var cats = new Gee.ArrayList<string> ();
            cats.add_all (c.categories);
            if (c.favorite) cats.add ("starred");
            if (cats.size > 0) {
                string[] esc = {};
                foreach (string s in cats) esc += escape (s);
                sb.append (fold ("CATEGORIES:" + string.joinv (",", esc)));
            }
            if (c.photo != null && c.photo.length > 0) sb.append (fold ("PHOTO;ENCODING=b;TYPE=" + c.photo_type.up () + ":" + Base64.encode (c.photo)));
            foreach (string raw in c.extra) sb.append (fold (raw));
            var now = new DateTime.now_utc ();
            sb.append ("REV:" + now.format ("%Y%m%dT%H%M%SZ") + "\r\n");
            sb.append ("END:VCARD\r\n");
            return sb.str;
        }
    }
}
