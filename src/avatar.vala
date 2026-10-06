using Gtk;

namespace Singularity.Apps.Contacts {

    public class ContactAvatar : Widget {
        private Gdk.Texture? texture;
        private string initials = "";
        private string seed = "";
        private int size;

        private const string[] COLORS = { "#3584e4", "#2190a4", "#3a944a", "#c88800", "#ed5b00", "#e62d42", "#d56199", "#9141ac", "#6f8396", "#986a44" };

        public ContactAvatar (int size) {
            this.size = size;
            add_css_class ("contact-avatar");
        }

        public void set_contact (Contact? c) {
            texture = null;
            initials = c != null ? c.initials : "";
            seed = c != null ? c.display_name : "";
            if (c != null && c.photo != null && c.photo.length > 0) {
                try {
                    texture = Gdk.Texture.from_bytes (new Bytes (c.photo));
                } catch (Error e) {
                    texture = null;
                }
            }
            queue_draw ();
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            minimum = natural = size;
            mb = nb = -1;
        }

        public override void snapshot (Snapshot snap) {
            float s = (float) int.min (get_width (), get_height ());
            var rect = Graphene.Rect ().init ((get_width () - s) / 2, (get_height () - s) / 2, s, s);
            var clip = Gsk.RoundedRect ().init_from_rect (rect, s / 2);
            snap.push_rounded_clip (clip);
            if (texture != null) {
                float tw = texture.width, th = texture.height;
                float scale = float.max (s / tw, s / th);
                var tr = Graphene.Rect ().init (rect.origin.x + (s - tw * scale) / 2, rect.origin.y + (s - th * scale) / 2, tw * scale, th * scale);
                snap.append_texture (texture, tr);
            } else {
                var bg = Gdk.RGBA ();
                bg.parse (COLORS[(seed.hash () % COLORS.length)]);
                snap.append_color (bg, rect);
                var layout = create_pango_layout (initials != "" ? initials : "?");
                var fd = new Pango.FontDescription ();
                fd.set_family ("Sans");
                fd.set_weight (Pango.Weight.BOLD);
                fd.set_absolute_size (s * 0.38 * Pango.SCALE);
                layout.set_font_description (fd);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                snap.save ();
                snap.translate (Graphene.Point () { x = rect.origin.x + (s - lw) / 2, y = rect.origin.y + (s - lh) / 2 });
                var white = Gdk.RGBA ();
                white.parse ("#ffffff");
                snap.append_layout (layout, white);
                snap.restore ();
            }
            snap.pop ();
        }
    }
}
