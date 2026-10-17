# 1. ABOUT SLOVOKLAD

SlovoKlad (Russian for “word treasure”) is a TUI dashboard and study aid. You decide what to learn and when to learn it. Flashcards are only marked as 'learned' when you say they are. With several study methods to choose from, you can pick the one that works best for you. SlovoKlad also has a built-in help system; press **?** in the application to open it.

# 2. USAGE

1. Make sure you have a recent version of Ruby installed.
2. From the project folder, install the dependencies: `$ bundle install`.
3. Start the application from the project folder: `$ bundle exec ruby app.rb`. Alternatively, you can run: `$ ruby app.rb`.

# 3. IMPORTANT

The application cannot run in the default macOS Terminal app because it requires a modern terminal emulator. Its user interface is built with Ratatui Ruby, which provides Ruby bindings for Ratatui, a Rust-based TUI library.

SlovoKlad has been tested in the following terminal emulators:

- iTerm2
- Ghostty.

In iTerm2, support for bidirectional (RTL) characters can be enabled or disabled. SlovoKlad manages RTL support itself, regardless of whether this feature is enabled in iTerm2.

To use **Alt-V** on macOS, configure the `Option key as a Meta key` in your prefered terminal emulator:

- In Ghostty, add the following line to your configuration:  `macos-⌥as-meta = left`
- In iTerm2, go to: **Settings → Profiles → Keys**. Then set `Left Option Key` to `Esc+`.

In iTerm2, the usual macOS keyboard shortcuts also work when SlovoKlad.itermkeymap is imported via **Settings → Profiles → Keys → Key Bindings → Presets…**. Ghostty may also support these key combinations; however, this has not yet been tested.

If you want to use Command+1 through Command+4 (study sessions) in addition to Alt+1 through Alt+4, go to **Settings → Keys → Navigation Shortcuts → Shortcut to activate a tab** and change the modifier from Command to a different key combination.

# 4. Keyboard Shortcuts for Input Fields

## 4.1 Editing

| Shortcut | Action |
|---|---|
| `Control+X` | Cut the selected text and copy it to the system clipboard. |
| `Control+Y`, `Control+Shift+Z` | Redo (`Control+Shift+Z` doesn't work in all terminals). `Control+Shift+Z` works by default in Ghostty. To enable it in iTerm2, import `SlovoKlad.itermkeymap` via **Settings → Profiles → Keys → Key Bindings → Presets…**.|
| `Control+Z` | Undo. |
| `Control+T` | Swap the character behind the insertion point with the character in front of it. |

## 4.2 Navigation

| Shortcut | Action |
|---|---|
| `Control+F`, `→` | Move one character forwards. |
| `Control+B`, `←` | Move one character backwards. |
| `Fn↑`, `Fn←`, `Option+↑`, `Control+A` | Move the insertion point to the beginning of the line. |
| `Fn↓`, `Fn→`, `Option+↓`, `Control+E` | Move the insertion point to the end of the line. |
| `Option+←` | Move the insertion point to the beginning of the previous word. |
| `Option+→` | Move the insertion point to the end of the next word. |
| `Control+L` | Centre the insertion point in the text. |
| `Tab`, `Control+P` | Move to the next input field. |
| `Backtab`, `Control+N` | Move to the previous input field. |

## 4.3 Removing Text

| Shortcut | Action |
|---|---|
| `Control+W`, `Option++Backspace` | Delete the word to the left of the insertion point. |
| `Fn+Option+Backspace` | Delete the word to the right of the insertion point. |
| `Control+H`, `Backspace` | Delete the character to the left of the insertion point. |
| `Control+D`, `Fn+Backspace` | Delete the character to the right of the insertion point. |
| `Control+K` | Delete the text from the insertion point to the end of the line. |
| `Control+U` | Delete the text from the insertion point to the beginning of the line. |

## 4.4 Selecting Text

| Shortcut | Action |
|---|---|
| `Control+A`, `Control+Shift+A` | Select all text. |
| `Control+Shift+F`, `Shift+→` | Extend the selection one character to the right. |
| `Control+Shift+B`, `Shift+←` | Extend the selection one character to the left. |
| `Option+Shift+←` | Extend the selection to the beginning of the current word. Press again to extend it to the beginning of the previous word. |
| `Option+Shift+→` | Extend the selection to the end of the current word. Press again to extend it to the end of the next word. |
| `Shift+↑`, `Fn+Shift+↑`, `Option+Shift+↑` | Extend the selection to the beginning of the line. |
| `Shift+↓`, `Fn+Shift+↓`, `Option+Shift+↓` | Extend the selection to the end of the line. |
| `Control+Shift+L` | Extend the selection to the centre of the text. |
