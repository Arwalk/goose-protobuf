# Well-known types and maps

The well-known types come with `pb_wire`, in the namespace `google_protobuf`, and need
no `protoc` step of their own. Generated code imports what it uses.

```sh run
../../scripts/install_plugin.sh
protoc --goose_out=. event.proto
goose build main.goose -o main
./main
```

```text output
starts at 1700000000 for 90 s
host Ada
front has 12 seats
back has 40 seats
back: 40 true
main is in Oslo
```
