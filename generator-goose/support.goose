// What the Zig generator gets from its standard library: an arena for text, and
// string-keyed hash maps. Goose has no heap and a Zig map as a field would make
// its struct resizable, so all maps share one global table and a map is a number.
// Nothing is ever freed: a plugin runs once and exits.

import std;

// The arena of every string that is made while generating. It only grows, so a
// view of it stays valid.
var arena: u8[>..] = [];

// A copy of s in the arena.
fn keep(s: const u8[:]) -> const u8[:] {
    let at = arena.len;
    arena.append(s);
    return arena[at..];
}

// `v` as eight lowercase hexadecimal digits: Zig's {x:0>8}.
fn hex8(v: u32) -> const u8[:] {
    var t: u8[>..] = [];
    format_uint(t, v, 16, 8, '0');
    return keep(t);
}

// A power of two, as mapBucket masks with it.
let MAP_BUCKETS = 262144;

// What a map holds for a key: `text`, `flag` and `index` mean what the map says.
struct MapEntry {
    map: u32,
    key: const u8[:],
    next: u32,       // the next entry of the bucket, as index + 1
    next_of_map: u32,   // the next entry of the map, as index + 1
    text: const u8[:],
    flag: bool,
    index: i64,
}

var map_entries: MapEntry[>..] = [];
var map_buckets: u32[MAP_BUCKETS] = [0; MAP_BUCKETS];
// The first entry of each map, as index + 1.
var map_firsts: u32[>..] = [];

fn newMap() -> u32 {
    map_firsts.push(0);
    return (map_firsts.len - 1) as! u32;
}

fn mapBucket(map: u32, key: const u8[:]) -> i64 {
    var h: u64 = 14695981039346656037;
    for c in key { h = (h ^ c) * 1099511628211; }
    h = (h ^ map) * 1099511628211;
    return ((h ^ (h >> 32)) as! i64) & (MAP_BUCKETS - 1);
}

// The entry of `key` in `map`, or null.
fn mapGet(map: u32, key: const u8[:]) -> MapEntry? {
    var at: i64 = map_buckets[mapBucket(map, key)];
    while at != 0 {
        let e .= map_entries[at - 1];
        if e.map == map && e.key == key { return e; }
        at = e.next;
    }
    return null;
}

fn mapContains(map: u32, key: const u8[:]) -> bool {
    return mapGet(map, key) != null;
}

// The index in map_entries of the entry of `key` in `map`, added empty if there is
// none: what a recursive function can keep, where it cannot keep a reference.
fn mapPutIndex(map: u32, key: const u8[:]) -> i64 {
    let b = mapBucket(map, key);
    var at: i64 = map_buckets[b];
    while at != 0 {
        let e .= map_entries[at - 1];
        if e.map == map && e.key == key { return at - 1; }
        at = e.next;
    }
    map_entries.push(MapEntry { map: map, key: key, next: map_buckets[b], next_of_map: map_firsts[map], text: "", flag: false, index: 0 });
    let added = map_entries.len as! u32;
    map_buckets[b] = added;
    map_firsts[map] = added;
    return map_entries.len - 1;
}

// The entry of `key` in `map`, added empty if there is none.
fn mapPut(map: u32, key: const u8[:]) -> MapEntry& {
    let at = mapPutIndex(map, key);
    return map_entries[at];
}
