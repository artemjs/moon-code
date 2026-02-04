# Moon-code

A minimalist code editor in Zig with native Wayland rendering.

![Moon-code](docs/screenshot.png)

## Features

### Editor
- Native Wayland rendering (OpenGL ES)
- Zig syntax highlighting (built-in)
- Highlighting via WASM plugins (Python and others)
- Multiple tabs
- Undo/Redo (Ctrl+Z / Ctrl+Y)
- Search (Ctrl+F)
- Zoom (Ctrl+Plus/Minus/0)
- Smooth scrolling with inertia
- Auto-pairs (brackets, quotes)
- Smart indentation

### File Manager
- Tree explorer with animations
- Icons by file type
- Open folders (Ctrl+O)
- Drag-and-drop sidebar resize

### Terminal
- Built-in interactive terminal
- Command history (Up/Down)
- Output scrolling (PageUp/PageDown)
- Scrollbar
- Color highlighting for error/warning/success

### Plugins (WASM)
- Hot-reload (auto-loading new plugins)
- Disable/Enable without deletion
- Uninstall with confirmation
- SVG plugin icons
- Run commands
- **LSP integration** (autocomplete, diagnostics, go-to-definition)

### UI
- Dark theme
- Rounded elements
- Window controls (min/max/close)
- Dropdown menu (File/Edit/View)
- Settings popup
- Confirm dialogs

## Build

```bash
# Requires Zig 0.15.2+
zig build

# Run
./zig-out/bin/moon-code
```

### Dependencies

- Wayland + EGL
- OpenGL ES 2.0
- wasmtime (C API, included in libs/)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New file |
| Ctrl+O | Open folder |
| Ctrl+S | Save |
| Ctrl+W | Close tab |
| Ctrl+F | Search |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+Space | Autocomplete (LSP) |
| Ctrl+Plus | Zoom in |
| Ctrl+Minus | Zoom out |
| Ctrl+0 | Reset zoom |
| F5 | Run (if plugin available) |
| F11 | Fullscreen |
| Esc | Close search/dialogs |

## Plugins

Plugins are placed in `~/.mncode/plugins/`

### Installing a Plugin

```bash
cp myplugin.wasm ~/.mncode/plugins/
```

The plugin will load automatically.

### Creating a Plugin

See [docs/PLUGIN_API.md](docs/PLUGIN_API.md)

## Project Structure

```
Moon-code/
├── src/
│   ├── main.zig           # Entry point, UI, events
│   ├── editor/
│   │   ├── buffer.zig     # Gap buffer for text
│   │   └── syntax.zig     # Built-in Zig highlighting
│   ├── render/
│   │   ├── wayland.zig    # Wayland client
│   │   ├── gpu.zig        # OpenGL ES rendering
│   │   ├── font.zig       # stb_truetype fonts
│   │   └── icons.zig      # SVG icons
│   ├── plugins/
│   │   ├── loader.zig     # WASM plugin loader
│   │   └── wasm_runtime.zig # wasmtime wrapper
│   ├── lsp/
│   │   └── client.zig     # LSP client (JSON-RPC)
│   ├── terminal/
│   │   ├── shell.zig      # Interactive shell
│   │   └── pty.zig        # PTY terminal
│   └── ui/
│       ├── widgets.zig    # ConfirmDialog, Scrollbar
│       └── text_input.zig # TextFieldBuffer
├── plugins/
│   └── python/            # Example plugin
├── assets/
│   └── fonts/             # JetBrains Mono
├── libs/
│   └── wasmtime-*/        # WASM runtime
└── docs/
    └── PLUGIN_API.md      # Plugin documentation
```

## Configuration

Settings are stored in `~/.mncode/`:

```
~/.mncode/
├── settings.conf      # Editor settings
├── plugins/           # WASM plugins
└── config/
    └── disabled.txt   # Disabled plugins
```

## Roadmap

- [ ] Find & Replace
- [ ] Global project search
- [ ] Git integration
- [x] LSP support (autocomplete, diagnostics)
- [x] Create/delete files from sidebar
- [x] File renaming
- [ ] Command Palette (Ctrl+Shift+P)
- [ ] Themes (light)

## License

MIT
