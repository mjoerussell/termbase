# termbase

Termbase is a database scratchpad. It's intended to enable quick exploration of databases without
requiring heavyweight database consoles or editors.

## Getting Started

First, clone this repository and all submodules with the following command:

```sh
git clone --recursive https://github.com/mjoerussell/termbase
```

Next, follow the setup instructions for [SDL.zig](https://github.com/MasterQ32/SDL.zig/tree/0b9a4d73fced0cd3d713a8ff3ad67c27a6507abd) and [zdb](https://github.com/mjoerussell/zdb/tree/d15066fe1e3d209564aeb0093101d497ad482f0f).

Once you've installed an ODBC driver/driver manager and SDL2, you should be able to start Termbase by running `zig build run`.

## Controls

| Key Combo                | Effect                                                                                             |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| Click anywhere           | Create a new text area where you can start entering SQL statements                                 |
| Click inside a text area | Start using that text area                                                                         |
| Ctrl+Enter               | Evaluate the current active text area as a SQL statement and print the result in a child text area |
| Ctrl+Tab                 | Navigate from a text area to its child (if it has a child)                                         |
| Ctrl+Shift+Tab           | Navigate from a text area to its parent (if it has a parent)                                       |
| Ctrl+D                   | Duplicate the current text area                                                                    |

More info TBA.
