# Examples

Complete programs to copy. Each directory says how to run it, and CI runs them all.

| Example | Shows |
|---|---|
| [minimal](minimal/) | One message, encoded and decoded |
| [multi_file](multi_file/) | Proto files that import each other, in a directory of their own |
| [wkt_and_maps](wkt_and_maps/) | Well-known types, and maps with number and message values |

They import the runtime from this repository, as `import pb_wire from "../..";`. In
your own project, use one of the ways in [the install guide](../docs/install.md).
