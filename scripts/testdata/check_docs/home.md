```sh run
# As a guide's reader has it: a home of their own, with ~/.local/bin on PATH.
[ "$HOME" != "$REAL_HOME" ]
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho installed\n' > "$HOME/.local/bin/a-tool"
chmod +x "$HOME/.local/bin/a-tool"
a-tool
```

```text output
installed
```
