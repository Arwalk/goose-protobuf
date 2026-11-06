// What the plugin needs of stdin and stdout that Goose's os module does not give.
// A request and a response are binary, and in text mode, as C starts them on Windows,
// input ends at a 0x1A byte and line endings are rewritten.

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>

void plugin_stdio_binary(void) {
    _setmode(0, _O_BINARY);
    _setmode(1, _O_BINARY);
}

int plugin_stdin_is_terminal(void) {
    return _isatty(0);
}
#else
#include <unistd.h>

void plugin_stdio_binary(void) {}

int plugin_stdin_is_terminal(void) {
    return isatty(0);
}
#endif
