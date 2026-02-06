# Moon-code FIXME

## Bugs

### Rendering
- [x] SVG not rendering correctly - FIXED: icons now load from ~/.mncode/icons/

### Terminal
- [ ] No scrollbar in terminal panel - can't scroll through long output

## Architecture Issues

### UI Rendering (Low Priority)
- [ ] ~50% of UI is drawn manually instead of using a proper widget system
  - Titlebar, menus, dialogs all hand-coded
  - Not a blocker, just makes UI changes tedious

### Code Structure
- [ ] main.zig is 7345 lines - needs splitting into modules
- [ ] 80+ global variables - need encapsulation
- [ ] 50+ `catch {}` - errors silently ignored

## Performance Notes
- Token cache limited to 10000 lines
- Tab limit: 16 tabs max
- Line index: 100000 lines max
