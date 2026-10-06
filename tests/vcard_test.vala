using Singularity.Apps.Contacts;

void test_parse () {
    string v = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:abc\r\nFN:Ada Lovelace\r\nN:Lovelace;Ada;Augusta;;\r\nNICKNAME:Countess\r\nORG:Analytical Engine;Research\r\nTITLE:Mathematician\r\nTEL;TYPE=CELL:+44 20 7946 0000\r\nTEL;TYPE=WORK,VOICE:020 1234\r\nitem1.EMAIL;TYPE=INTERNET:ada@example.org\r\nADR;TYPE=HOME:;;12 St James\\, Square;London;;SW1Y 4JH;UK\r\nURL:https://example.org\r\nBDAY:1815-12-10\r\nNOTE:First line\\nSecond\\; part\r\nCATEGORIES:starred,Friends\r\nX-CUSTOM:keep me\r\nPHOTO;ENCODING=b;TYPE=PNG:iVBORw0KGgo=\r\nEND:VCARD\r\n";
    var list = VCard.parse (v);
    assert (list.size == 1);
    var c = list[0];
    assert (c.uid == "abc" && c.display_name == "Ada Lovelace" && c.given == "Ada" && c.family == "Lovelace");
    assert (c.nickname == "Countess" && c.org == "Analytical Engine, Research" && c.title == "Mathematician");
    assert (c.phones.size == 2 && c.phones[0].kind == "cell" && c.phones[1].kind == "work");
    assert (c.emails.size == 1 && c.emails[0].value == "ada@example.org");
    assert (c.addresses.size == 1 && c.addresses[0].street == "12 St James, Square" && c.addresses[0].city == "London" && c.addresses[0].postal == "SW1Y 4JH");
    assert (c.birthday == "1815-12-10");
    assert (c.note == "First line\nSecond; part");
    assert (c.favorite && c.categories.size == 1 && c.categories[0] == "Friends");
    assert (c.photo != null && c.photo.length == 8 && c.photo_type == "png");
    assert (c.initials == "AL");
    assert (c.matches ("7946") && c.matches ("london") && c.matches ("countess") && !c.matches ("zzz"));
}

void test_round_trip () {
    var c = new Contact ();
    c.uid = "u1";
    c.given = "José";
    c.family = "Núñez";
    c.org = "Acme; Inc";
    c.phones.add (new Field ("home", "123"));
    c.emails.add (new Field ("work", "j@acme.test"));
    var a = new PostalAddress ();
    a.street = "Via Roma 1";
    a.city = "Milano";
    a.country = "Italia";
    c.addresses.add (a);
    c.note = string.nfill (200, 'x') + "é";
    c.favorite = true;
    c.birthday = "--05-21";
    string text = VCard.serialize (c);
    foreach (string line in text.split ("\r\n")) assert (line.length <= 76);
    var back = VCard.parse_one (text);
    assert (back.display_name == "José Núñez" && back.org == "Acme; Inc");
    assert (back.phones[0].kind == "home" && back.emails[0].kind == "work");
    assert (back.addresses[0].city == "Milano" && back.note == c.note && back.favorite && back.birthday == "--05-21");
}

void test_multi_and_folding () {
    string v = "BEGIN:VCARD\nVERSION:4.0\nFN:One\nEMAIL:one@x.test\nEND:VCARD\nBEGIN:VCARD\nVERSION:4.0\nFN:Two Long\n Name\nTEL;VALUE=uri;TYPE=\"voice,cell\":tel:+1-555\nBDAY:19900521\nEND:VCARD\n";
    var list = VCard.parse (v);
    assert (list.size == 2);
    assert (list[1].display_name == "Two LongName");
    assert (list[1].phones[0].value == "+1-555" && list[1].phones[0].kind == "cell");
    assert (list[1].birthday == "1990-05-21");
    assert (list[0].uid != "" && list[0].uid != list[1].uid);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/vcard/parse", test_parse);
    Test.add_func ("/vcard/round-trip", test_round_trip);
    Test.add_func ("/vcard/multi", test_multi_and_folding);
    return Test.run ();
}
