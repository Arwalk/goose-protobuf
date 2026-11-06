# Generated code reference

What `protoc-gen-goose` generates for a `.proto` file, and how long what it returns
stays valid. [The usage guide](usage.md) shows the same names in a running program.
Everything here is public, as [the version rules](versions.md) define it: anything in a generated file that this page does not list may change in any
release.

In the tables, `M` is a message, `f` a field and `o` a oneof. `S` is a sub-message's
type, `T` a repeated field's element, and `K` and `V` a map's key and value. Goose
types of numbers follow protobuf's: `int32` is `i32`, `sint64` is `i64`, `fixed32` is
`u32`, `float` is `f32`, and so on. A `bool` is `bool` and an enum is `i32`.

## Names

| In the `.proto` | In Goose | Example |
|---|---|---|
| Package | One namespace, with dots turned into `_`. No package means the global namespace. | `foo.bar` is `foo_bar::` |
| Message | A struct, with nested names joined by `_` | `Outer.Inner` is `Outer_Inner` |
| Enum value | An `i32` constant, `<enum>_<VALUE>`, with no prefix removed | `Outer.Color.COLOR_RED` is `Outer_Color_COLOR_RED` |
| Function of a message | `<message>_<operation>` | `Node_decode` |
| Function of a field | `<message>_<field>` with the operation | `Node_set_name`, `Node_children_at` |
| Record field | The field's name | `m.age` |
| File | Each path segment, with what an identifier cannot hold turned into `_` | `api/foo.v1.proto` is `api/foo_v1.goose`, imported as `import api.foo_v1;` |

A name a Goose program cannot use gets a trailing `_`: keywords, builtins such as
`print` and `str`, and names that start with `pb_` or `PB_`, which belong to the
runtime. So a field `type` is `m.type_`, and a message `type` is `type_`, while its
functions are `type_decode` and so on, as those names are free.

A nested type with the name of a generated function gets a `_` too, so `Outer.decode`
is `Outer_decode_`. When that cannot work, the plugin refuses the file, and `protoc`
prints which two names clash. This happens if `A.B` sits beside a top-level `A_B`, or a
field `f_len` beside a `repeated f`. Rename one of the two. A package keeps your names
out of each other's way, so use one.

## Every message

Make one with `var m = M { .. };`, as a local, a global or an array element.

<!-- golden: maps Maps -->
| Function | What it does |
|---|---|
| `M_decode(buf, m) -> i32` | Merges `buf` into `m`, and returns `PB_OK` or a `PB_ERR_*` code. After an error, `m` holds part of a message. |
| `M_encode(m, out)` | Appends the encoding of `m` to `out` |
| `M_size_of(m) -> i64` | The size `M_encode` would append |
| `M_clear(m)` | Frees what `m` owns and empties it |
| `M_copy(dst, src)` | Makes `dst` a deep copy of `src`. Neither may be a sub-message of the other. |

A message that can reach a map, through any of its fields, also has:

<!-- golden: maps Maps -->
| Function | What it does |
|---|---|
| `M_fold_maps(m)` | Settles the keys that `M_f_append` repeated: the last value wins, in the place of the first |

A message that can reach a proto2 `required` field also has:

<!-- golden: required Uses -->
| Function | What it does |
|---|---|
| `M_is_initialized(m) -> bool` | True if every required field in reach is set. `M_decode` already checks this, and returns `PB_ERR_REQUIRED`. |

`pb_error_text(err)` gives an error code's meaning, for a message to a person. The
codes are in [the usage guide](usage.md#decode).

## Numbers, bools and enums

With no presence, which is a plain proto3 field, the field is only a record field:
read `m.f` and write `m.f = v`.

With presence, read `m.f`, which gives the default if the field is unset, and write
through the setter, which marks it set:

<!-- golden: optional Opt o_int32 -->
| Function | What it does |
|---|---|
| `M_set_f(m, v)` | Sets it, so it is encoded even when 0 |
| `M_has_f(m) -> bool` | Whether it is set |
| `M_clear_f(m)` | Unsets it |

## Strings and bytes

<!-- golden: strings Text s -->
| Function | What it does |
|---|---|
| `M_f(m) -> u8[:]` | A view of its contents |
| `M_set_f(m, v)` | Sets it to a copy of `v` |

With presence, there is also:

<!-- golden: strings Text os -->
| Function | What it does |
|---|---|
| `M_f(m) -> u8[:]` | A view of its contents |
| `M_set_f(m, v)` | Sets it to a copy of `v`, so it is encoded even when empty |
| `M_has_f(m) -> bool` | Whether it is set |
| `M_clear_f(m)` | Unsets it |

With a proto2 `[default]`, the view is read-only, as it may be the default:

<!-- golden: defaults All v_string -->
| Function | What it does |
|---|---|
| `M_f(m) -> const u8[:]` | Its contents, or the default if it is unset |
| `M_set_f(m, v)` | Sets it to a copy of `v` |
| `M_has_f(m) -> bool` | Whether it is set |
| `M_clear_f(m)` | Unsets it, so it reads as the default |

`M_set_f` may take a view of the same field, as in `M_set_f(m, M_f(m)[1..])`.

## Sub-messages

<!-- golden: submessages Outer inner -->
| Function | What it does |
|---|---|
| `M_f(m) -> S&?` | The sub-message, or null if it is not set |
| `M_mutable_f(m) -> S&` | The sub-message, set to an empty one first if it is not set |
| `M_has_f(m) -> bool` | Whether it is set |
| `M_clear_f(m)` | Frees it and everything it owns |

**Bind what returns a message with `.=`**, as in `let s .= M_mutable_f(m);`. With `=`
you change a copy, and the message never sees it.

## Repeated numbers, bools and enums

<!-- golden: repeated Packed f_int32 -->
| Function | What it does |
|---|---|
| `M_f(m) -> T[:]` | A view of all the values |
| `M_f_len(m) -> i64` | How many there are |
| `M_f_at(m, i) -> T` | Value `i` |
| `M_add_f(m, v)` | Adds a value. This may move the values, so `M_set_f` is better for many. |
| `M_set_f(m, v)` | Replaces all the values with a copy of the slice `v` |
| `M_clear_f(m)` | Removes them all |

## Repeated strings and bytes

<!-- golden: lists Lists names -->
| Function | What it does |
|---|---|
| `M_f_len(m) -> i64` | How many there are |
| `M_f_at(m, i) -> u8[:]` | A view of the contents of value `i` |
| `M_add_f(m, v)` | Adds a copy of `v` |
| `M_set_f(m, i, v)` | Sets value `i` to a copy of `v` |
| `M_clear_f(m)` | Removes them all |

There is no getter of all the values. Loop from 0 to `M_f_len(m)`.

## Repeated messages

<!-- golden: lists Lists items -->
| Function | What it does |
|---|---|
| `M_f_len(m) -> i64` | How many there are |
| `M_f_at(m, i) -> S&` | Message `i` |
| `M_add_f(m) -> S&` | Adds an empty message and returns it |
| `M_clear_f(m)` | Frees them all and everything they own |

There is no getter of all the values, and no setter.

## Maps

Entries stay in insertion order. A key is `const u8[:]` when you pass it for a string
key, and `u8[:]` when `M_f_key_at` returns it.

Values that are numbers, bools or enums:

<!-- golden: maps Maps si -->
| Function | What it does |
|---|---|
| `M_f_len(m) -> i64` | How many entries there are |
| `M_f_key_at(m, i) -> K` | The key of entry `i` |
| `M_f_value_at(m, i) -> V` | The value of entry `i` |
| `M_f_get(m, k) -> V, bool` | The value with key `k` and true, or the default and false |
| `M_f_put(m, k, v)` | Sets the value with key `k`, adding an entry if there is none |
| `M_f_append(m, k, v)` | Adds an entry without looking for `k`, much faster for many. Call `M_fold_maps` before reading. |
| `M_f_remove(m, k) -> bool` | Removes the entry with key `k`. False if there is none. Later entries keep their order. |
| `M_clear_f(m)` | Frees all the entries |

Values that are strings or bytes:

<!-- golden: maps Maps ss -->
| Function | What it does |
|---|---|
| `M_f_len(m) -> i64` | How many entries there are |
| `M_f_key_at(m, i) -> K` | The key of entry `i` |
| `M_f_value_at(m, i) -> u8[:]` | A view of the value of entry `i` |
| `M_f_get(m, k) -> u8[:], bool` | A view of the value with key `k` and true, or an empty view and false |
| `M_f_put(m, k, v)` | Sets the value with key `k` to a copy of `v`, adding an entry if there is none |
| `M_f_append(m, k, v)` | As above, without looking for `k` |
| `M_f_remove(m, k) -> bool` | Removes the entry with key `k`. False if there is none. |
| `M_clear_f(m)` | Frees all the entries |

Values that are messages:

<!-- golden: maps Maps sm -->
| Function | What it does |
|---|---|
| `M_f_len(m) -> i64` | How many entries there are |
| `M_f_key_at(m, i) -> K` | The key of entry `i` |
| `M_f_value_at(m, i) -> S&` | The value of entry `i`, which is never null |
| `M_f_get(m, k) -> S&?` | The value with key `k`, or null if there is none |
| `M_f_put(m, k) -> S&` | The value with key `k`, added empty if there is none |
| `M_f_append(m, k) -> S&` | As above, without looking for `k` |
| `M_f_remove(m, k) -> bool` | Removes the entry with key `k`. False if there is none. |
| `M_clear_f(m)` | Frees all the entries and everything they own |

There is no getter of all the entries. Loop from 0 to `M_f_len(m)`.

## Oneofs

The record field `m.o` says which member is set. Match on its member names, and read
the value with the member's function:

```goose
match m.contact {
    phone => { print(Person_phone(m)); },
    pb_none => { print("none is set"); },
    _ => {},
}
```

The whole oneof has:

<!-- golden: oneofs Choice pick -->
| Function | What it does |
|---|---|
| `M_clear_o(m)` | Unsets whichever member is set |

Each member that is a number, bool, enum, string or bytes has:

<!-- golden: oneofs Choice p_int32 -->
| Function | What it does |
|---|---|
| `M_f(m) -> T` | Its value, or the default if another member is set |
| `M_set_f(m, v)` | Sets it and makes it the member set |
| `M_has_f(m) -> bool` | Whether it is the member set |
| `M_clear_f(m)` | Unsets it, if it is the member set |

For a string or bytes member, `M_f(m)` returns a view, and `M_set_f` copies. Each
member that is a message has:

<!-- golden: oneofs Choice p_sub -->
| Function | What it does |
|---|---|
| `M_f(m) -> S&?` | The message, or null if another member is set |
| `M_mutable_f(m) -> S&` | The message, made the member set and empty if it was not |
| `M_has_f(m) -> bool` | Whether it is the member set |
| `M_clear_f(m)` | Frees it, if it is the member set |

## proto2 and editions

Which fields have presence depends on the syntax:

| Field | Presence |
|---|---|
| proto3, no label | None |
| proto3, `optional` | Yes |
| proto2, `optional` or `required` | Yes |
| Editions | Yes, unless `features.field_presence` is `IMPLICIT` |

Sub-messages and oneof members always have it. Repeated fields and maps have no
presence, whatever the syntax.

- **`required`** is stored like `optional`, and `M_decode` fails with `PB_ERR_REQUIRED`
  if one is unset.
- **`[default]`** is what an unset field reads as.
- **Groups**, and `features.message_encoding = DELIMITED`, have the functions of a
  sub-message or a repeated message. A group `One` in `G` is the field `one` of type
  `G_One`.
- **A value that a closed enum does not declare** is kept as an unknown field when
  decoding, and the field stays as it was.
- **Extensions** are kept as unknown fields, with no functions.

Fields a message does not know are kept, and `M_encode` writes them back after the
known ones.

## How long things stay valid

Messages keep what varies in size in global pools, which `M_clear` gives back. A record
holds only positions in those pools.

| What you hold | Valid until |
|---|---|
| A view: a `u8[:]` or `T[:]` that a function returned | The next change to any message, as a change may reuse or move what it points at. Copy what you want to keep with `str(...)` or into your own buffer. |
| A message: an `S&` or `S&?` that a function returned | It or a message that holds it is cleared. Adding other messages does not move it. A map's message value also ends when its entry is removed. |

**Assigning a record copies positions, not contents.** After `let b = a;`, the two share
their contents, and clearing one leaves the other wrong. Use `M_copy`. Clear a message
you are done with: a local that goes out of scope frees nothing in the pools.

**Do not decode from a view of a message's contents**, as decoding allocates in the
pool that holds them. Copy such bytes into a buffer of their own first.

Messages are single-threaded, as the pools are global ([limitations](limitations.md)).
