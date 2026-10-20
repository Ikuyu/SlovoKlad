# 1. ABOUT SLOVOKLAD

SlovoKlad (Russian for “word treasure”) is a TUI dashboard and study aid. You decide what to learn and when to learn it. Flashcards are only marked as 'learned' when you say they are. With several study methods to choose from, you can pick the one that works best for you. SlovoKlad also has a built-in help system; press **?** in the application to open it.

# 2. QUICK START

## 2.1 1. Install mise

Download and install [mise](https://mise.jdx.dev). This automatically loads the correct Ruby version for the app the moment you enter the folder.

## 2.2 Clone the Application

Open your terminal and download this repository to your machine:

```bash
git clone https://github.com
cd slovoklad
```

## 2.3 Initialize & Install Dependencies (Gems)

Set up the workspace environment and download all required packages (such as ratatui_ruby and clipboard) via the bundler:

```bash
bundle init
bundle install
```

## 2.4 Launch the Application!

You are now ready to launch the dashboard. Provide the included example.json file to instantly seed your interface with the multi-language test environment:

```bash
bundle exec ruby app.rb example.json
```

## 2.5 Available Command Line Options

You can inspect all available commands, input operations, and export configurations by using the standard help flags:

```bash
ruby app.rb -h
# or alternatively
ruby app.rb --help
```

# 3. IMPORTANT

SlovoKlad cannot run in the default macOS Terminal app because it requires a modern terminal emulator. Its user interface is built with Ratatui Ruby, which provides Ruby bindings for Ratatui, a Rust-based TUI library.

The application has been tested in the following terminal emulators:

- iTerm2
- Ghostty.

In iTerm2, support for bidirectional (RTL) characters can be enabled or disabled. SlovoKlad manages RTL support itself, regardless of whether this feature is enabled in iTerm2.

To use **Alt-V** on macOS, configure the `Option key as a Meta key` in your prefered terminal emulator:

- In Ghostty, add the following line to `~/.config/ghostty/config`:  `macos-option-as-alt = left`
- In iTerm2, go to: **Settings > Profiles > Keys**. Then set `Left Option Key` to `Esc+`.

In iTerm2, the usual macOS keyboard shortcuts also work when SlovoKlad.itermkeymap is imported via **Settings > Profiles > Keys > Key Bindings > Presets…**. Ghostty may also support these key combinations; however, this has not yet been tested.

If you want to use Command+1 through Command+4 (study sessions) in addition to Alt+1 through Alt+4, go to **Settings > Keys > Navigation Shortcuts > Shortcut to activate a tab** and change the modifier from Command to a different key combination.

In scripts such as Hebrew and Cyrillic, handwritten (cursive) letters have different forms from printed letters. To display both correctly in iTerm2:

1. Go to Settings > Profiles > Text.
2. Set the regular font to JetBrains Mono Regular and the Non-ASCII Font to Victor Mono Regular. Then click Manage Special Exceptions for this Font, click `+`, and add the range `U+2500`–`U+259F`, assigning it to JetBrains Mono or whichever font you’re currently using.
3. Restart iTerm2.

In SlovoKlad, press the i key without holding shift to switch between the writing styles, if your font supports it.

On macOS, you can easily install both fonts with [Homebrew](https://brew.sh):
```
brew install --cask font-victor-mono # for Russian cursive
brew install --cask font-jetbrains-mono
```

In Ghostty, add the following lines to `~/.config/ghostty/config`.

```
font-family = "JetBrains Mono", "Victor Mono"
font-style = "Regular"
font-style-italic = "Italic"
```

If you’re using macOS, copy the contents of `ghostty-config.txt` into `~/.config/ghostty/config`.

For iTerm2 only: turn off **Settings > Profiles > Terminal > Save lines to scrollback in alternate screen mode** to prevent scrollback issues.


# 4. Keyboard Shortcuts for Input Fields

## 4.1 Editing

| Shortcut | Action |
|---|---|
| `Control+X` | Cut the selected text and copy it to the system clipboard. |
| `Control+Y`, `Control+Shift+Z` | Redo (`Control+Shift+Z` doesn't work in all terminals). `Control+Shift+Z` works by default in Ghostty. To enable it in iTerm2, import `SlovoKlad.itermkeymap` via **Settings > Profiles > Keys > Key Bindings > Presets…**.|
| `Control+Z` | Undo. |
| `Control+T` | Swap the character behind the insertion point with the character in front of it. |

## 4.2 Navigation

| Shortcut | Action |
|---|---|
| `Control+F`, `>` | Move one character forwards. |
| `Control+B`, `←` | Move one character backwards. |
| `Fn↑`, `Fn←`, `Option+↑`, `Control+A` | Move the insertion point to the beginning of the line. |
| `Fn↓`, `Fn>`, `Option+↓`, `Control+E` | Move the insertion point to the end of the line. |
| `Option+←` | Move the insertion point to the beginning of the previous word. |
| `Option+>` | Move the insertion point to the end of the next word. |
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
| `Control+Shift+F`, `Shift+>` | Extend the selection one character to the right. |
| `Control+Shift+B`, `Shift+←` | Extend the selection one character to the left. |
| `Option+Shift+←` | Extend the selection to the beginning of the current word. Press again to extend it to the beginning of the previous word. |
| `Option+Shift+>` | Extend the selection to the end of the current word. Press again to extend it to the end of the next word. |
| `Shift+↑`, `Fn+Shift+↑`, `Option+Shift+↑` | Extend the selection to the beginning of the line. |
| `Shift+↓`, `Fn+Shift+↓`, `Option+Shift+↓` | Extend the selection to the end of the line. |
| `Control+Shift+L` | Extend the selection to the centre of the text. |
