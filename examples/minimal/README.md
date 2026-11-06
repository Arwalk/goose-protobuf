# Minimal

One message, encoded and decoded. From this directory:

```sh run
../../scripts/install_plugin.sh
protoc --goose_out=. greeting.proto
goose build main.goose -o main
./main
```

```text output
hi x 3 in 6 bytes
```
