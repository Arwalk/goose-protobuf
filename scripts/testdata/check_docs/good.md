```goose file=a.goose
fn main() { print("hi"); }
```

```sh run
goose build a.goose -o a >/dev/null 2>&1
./a
```

```text output
hi
```
