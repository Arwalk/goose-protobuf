import pb_wire from "../..";
import api.book;
import api.person;

fn add_person(b: api_books::Book&, name: const u8[:], email: const u8[:]) {
    let p .= api_books::Book_add_people(b);
    api_people::Person_set_name(p, name);
    api_people::Person_add_emails(p, email);
}

fn main() {
    var book = api_books::Book { .. };
    api_books::Book_set_title(book, "friends");
    add_person(book, "Ada", "ada@example.org");
    add_person(book, "Linus", "linus@example.org");

    var bytes: u8[>..] = [];
    api_books::Book_encode(book, bytes);
    api_books::Book_clear(book);

    var back = api_books::Book { .. };
    let err = api_books::Book_decode(bytes, back);
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
    print(api_books::Book_title(back));
    for i in api_books::Book_people_len(back) {
        let p .= api_books::Book_people_at(back, i);
        print(api_people::Person_name(p), " ", api_people::Person_emails_at(p, 0));
    }
    api_books::Book_clear(back);
}
