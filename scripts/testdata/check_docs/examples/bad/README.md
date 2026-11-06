```sh run
test -f ../../pb_wire.goose
goose build main.goose -o main >/dev/null 2>&1
./main
```

```text output
something else
```
