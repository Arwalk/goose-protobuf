```goose file=a.goose
fn main() { nosuchfunction(); }
```

```sh run
goose build a.goose -o a
```
