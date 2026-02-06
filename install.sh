#!/bin/bash

# Moon-code installer
# Creates ~/.mncode/icons/ with all required SVG icons

MNCODE_DIR="$HOME/.mncode"
ICONS_DIR="$MNCODE_DIR/icons"

echo "Installing Moon-code assets..."

# Create directories
mkdir -p "$ICONS_DIR"

# Function to create SVG if it doesn't exist
create_svg() {
    local name="$1"
    local content="$2"
    local path="$ICONS_DIR/$name"

    if [ ! -f "$path" ]; then
        echo "$content" > "$path"
        echo "  Created $name"
    fi
}

# Create all icons
create_svg "files.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="1" y="5" width="14" height="9" rx="2" fill="#808080"/>
  <rect x="1" y="2" width="6" height="4" rx="1" fill="#808080"/>
</svg>'

create_svg "search.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="6" cy="6" r="5" stroke="#808080" stroke-width="2" fill="none"/>
  <rect x="10" y="9" width="5" height="2" rx="1" transform="rotate(45 10 9)" fill="#808080"/>
</svg>'

create_svg "git-branch.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="4" cy="4" r="2" fill="#808080"/>
  <circle cx="4" cy="12" r="2" fill="#808080"/>
  <circle cx="12" cy="4" r="2" fill="#808080"/>
  <rect x="3" y="4" width="2" height="8" fill="#808080"/>
  <rect x="4" y="3" width="8" height="2" fill="#808080"/>
</svg>'

create_svg "file-code.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="1" fill="#808080"/>
  <rect x="4" y="5" width="4" height="1" fill="#1a1a1a"/>
  <rect x="4" y="8" width="6" height="1" fill="#1a1a1a"/>
  <rect x="4" y="11" width="3" height="1" fill="#1a1a1a"/>
</svg>'

create_svg "folder.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="1" y="4" width="14" height="10" rx="2" fill="#808080"/>
  <rect x="1" y="2" width="6" height="4" rx="1" fill="#808080"/>
</svg>'

create_svg "close.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M4 4l8 8M12 4l-8 8" stroke="#808080" stroke-width="2" stroke-linecap="round"/>
</svg>'

create_svg "plus.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="7" y="3" width="2" height="10" rx="1" fill="#808080"/>
  <rect x="3" y="7" width="10" height="2" rx="1" fill="#808080"/>
</svg>'

create_svg "window-minimize.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="4" y="8" width="8" height="2" rx="1" fill="#808080"/>
</svg>'

create_svg "window-maximize.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="3" y="3" width="10" height="10" rx="1" stroke="#808080" stroke-width="2" fill="none"/>
</svg>'

create_svg "window-restore.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="5" width="8" height="8" rx="1" stroke="#808080" stroke-width="1.5" fill="none"/>
  <rect x="6" y="2" width="8" height="8" rx="1" stroke="#808080" stroke-width="1.5" fill="none"/>
</svg>'

create_svg "window-close.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M4 4l8 8M12 4l-8 8" stroke="#808080" stroke-width="2" stroke-linecap="round"/>
</svg>'

create_svg "plugin.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="6" width="12" height="8" rx="2" ry="2" fill="#808080"/>
  <rect x="4" y="2" width="3" height="5" rx="1" ry="1" fill="#808080"/>
  <rect x="9" y="2" width="3" height="5" rx="1" ry="1" fill="#808080"/>
</svg>'

create_svg "play.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M4 2l10 6-10 6V2z" fill="#808080"/>
</svg>'

create_svg "terminal.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="1" y="2" width="14" height="12" rx="2" fill="#808080"/>
  <rect x="2" y="5" width="12" height="8" rx="1" fill="#1a1a1a"/>
  <path d="M4 8l2 2-2 2" stroke="#808080" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <rect x="8" y="11" width="4" height="1.5" rx="0.5" fill="#808080"/>
</svg>'

create_svg "error.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="8" cy="8" r="7" fill="#e74c3c"/>
  <path d="M5 5l6 6M11 5l-6 6" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>
</svg>'

create_svg "warning.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M8 1L1 14h14L8 1z" fill="#f39c12"/>
  <rect x="7" y="5" width="2" height="5" rx="1" fill="#1a1a1a"/>
  <rect x="7" y="11" width="2" height="2" rx="1" fill="#1a1a1a"/>
</svg>'

# Language file icons
create_svg "c.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#555988"/>
  <text x="8" y="11" font-size="8" font-family="sans-serif" fill="#fff" text-anchor="middle">C</text>
</svg>'

create_svg "cpp.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#004482"/>
  <text x="8" y="11" font-size="6" font-family="sans-serif" fill="#fff" text-anchor="middle">C++</text>
</svg>'

create_svg "h.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#6a5acd"/>
  <text x="8" y="11" font-size="8" font-family="sans-serif" fill="#fff" text-anchor="middle">H</text>
</svg>'

create_svg "zig.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#f7a41d"/>
  <rect x="4" y="4" width="8" height="2" fill="#1a1a1a"/>
  <rect x="7" y="5" width="2" height="4" fill="#1a1a1a"/>
  <rect x="4" y="9" width="8" height="2" fill="#1a1a1a"/>
</svg>'

create_svg "json.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#cbcb41"/>
  <text x="8" y="11" font-size="5" font-family="sans-serif" fill="#1a1a1a" text-anchor="middle">{}</text>
</svg>'

create_svg "yaml.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#cb4b16"/>
  <text x="8" y="11" font-size="5" font-family="sans-serif" fill="#fff" text-anchor="middle">yml</text>
</svg>'

create_svg "js.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#f7df1e"/>
  <text x="8" y="11" font-size="6" font-family="sans-serif" fill="#1a1a1a" text-anchor="middle">JS</text>
</svg>'

create_svg "ts.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#3178c6"/>
  <text x="8" y="11" font-size="6" font-family="sans-serif" fill="#fff" text-anchor="middle">TS</text>
</svg>'

create_svg "py.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#3776ab"/>
  <rect x="4" y="4" width="4" height="4" rx="1" fill="#ffd43b"/>
  <rect x="8" y="8" width="4" height="4" rx="1" fill="#ffd43b"/>
</svg>'

create_svg "rs.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#dea584"/>
  <text x="8" y="11" font-size="6" font-family="sans-serif" fill="#1a1a1a" text-anchor="middle">Rs</text>
</svg>'

create_svg "go.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#00add8"/>
  <text x="8" y="11" font-size="6" font-family="sans-serif" fill="#fff" text-anchor="middle">Go</text>
</svg>'

create_svg "md.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#519aba"/>
  <text x="8" y="11" font-size="5" font-family="sans-serif" fill="#fff" text-anchor="middle">MD</text>
</svg>'

create_svg "txt.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#606060"/>
  <rect x="4" y="4" width="6" height="1" fill="#fff"/>
  <rect x="4" y="7" width="8" height="1" fill="#fff"/>
  <rect x="4" y="10" width="5" height="1" fill="#fff"/>
</svg>'

create_svg "xml.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#e37933"/>
  <text x="8" y="11" font-size="5" font-family="sans-serif" fill="#fff" text-anchor="middle">&lt;/&gt;</text>
</svg>'

create_svg "html.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#e44d26"/>
  <text x="8" y="11" font-size="4" font-family="sans-serif" fill="#fff" text-anchor="middle">HTML</text>
</svg>'

create_svg "css.svg" '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="2" y="1" width="12" height="14" rx="2" fill="#264de4"/>
  <text x="8" y="11" font-size="5" font-family="sans-serif" fill="#fff" text-anchor="middle">CSS</text>
</svg>'

echo ""
echo "Installation complete!"
echo "Icons installed to: $ICONS_DIR"
echo ""
echo "To run Moon-code:"
echo "  ./zig-out/bin/moon-code"
