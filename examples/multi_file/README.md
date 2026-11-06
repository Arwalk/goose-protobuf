# Several proto files

`api/book.proto` imports `api/person.proto`, and they are in different packages. Give
`protoc` both files, from the directory that their import paths start from:

```sh run
../../scripts/install_plugin.sh
protoc --goose_out=. api/person.proto api/book.proto
goose build main.goose -o main
./main
```

```text output
friends
Ada ada@example.org
Linus linus@example.org
```

`protoc` writes `api/person.goose` and `api/book.goose`, next to `main.goose`, which is
where Goose resolves their imports from. Each package is a namespace, so `api.books` is
`api_books::`.
