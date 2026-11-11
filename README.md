# 1. ABOUT SLOVOKLAD

**SlovoKlad** (RU: “word treasure”) is a TUI dashboard and study aid. You decide what to learn and when to learn it. Flashcards are only marked as **learned** when you say they are. With several study methods to choose from, you can pick the one that works best for you.

The manuals are in the `manuals` folder. **SlovoKlad** also has a built-in help system; press **?** in the application to open it.

# 2. QUICK START

## 2.1 Prerequisites

Install GNU FriBidi for your platform:

* macOS: `brew install fribidi`
* Debian/Ubuntu: `sudo apt install libfribidi0`
* Fedora: `sudo dnf install fribidi`
* Arch Linux: `sudo pacman -S fribidi`
* Windows (MSYS2 MinGW 64-bit): `pacman -S mingw-w64-x86_64-fribidi`; ensure `C:\msys64\mingw64\bin` is on PATH so Ruby can find the DLL.

## 2.2 Install Mise

Download and install [Mise](https://mise.jdx.dev). This automatically loads the correct Ruby version for the app when you enter the project folder.

## 2.3 Clone the Application

Open your terminal and download this repository to your machine:

```bash
git clone https://github.com/Ikuyu/slovoklad.git
cd slovoklad
```

Replace the repository URL with the actual URL if it differs.

## 2.4 Install Dependencies

Install the application's Ruby dependencies using Bundler:

```bash
bundle install
```

## 2.5 Launch the Application

You are now ready to launch the dashboard. Provide the included `example.json` file to instantly seed your interface with the multi-language test environment:

```bash
bundle exec ruby app.rb example
# No need to add .json
```

## 2.6 Build a Standalone Executable

**SlovoKlad** can also be packaged as a standalone executable using [Tebako](https://github.com/tamatebako/tebako).

Make sure Ruby, Mise and the application dependencies are installed. Then run the build script from the project root:

```bash
ruby build.rb
```

The script prepares a staging directory, packages the application and creates an executable for the platform on which the build is run.

The resulting directory structure is:

```text
dist/
├── macos/
│   └── Slovoklad
├── windows/
│   └── Slovoklad.exe
└── linux/
    └── Slovoklad
```

Only the executable for the current build platform is created or updated. Existing executables for other platforms are preserved.

To run the executable:

**macOS**
```bash
./dist/macos/Slovoklad
```

**Linux**
```bash
./dist/linux/Slovoklad
```

**Windows (PowerShell)**
```powershell
.\dist\windows\Slovoklad.exe
```

Tebako builds for the current host platform. To produce executables for other operating systems, run the build script on the respective platform.

## 2.7 Available Command Line Options

You can inspect all available commands, input operations, and export configurations by using the standard help flags:

```bash
ruby app.rb -h
# or alternatively
ruby app.rb --help
```

# 3. IMPORTANT

**SlovoKlad** cannot run in the default **macOS Terminal** app because it requires a modern terminal emulator. Its user interface is built with Ratatui Ruby, which provides Ruby bindings for Ratatui, a Rust-based TUI library.

The application has been tested in the following terminal emulators:

- iTerm2
- Ghostty.

In **iTerm2**, support for bidirectional (RTL) characters can be enabled or disabled. **SlovoKlad** manages RTL support itself, regardless of whether this feature is enabled in iTerm2.

To use **Alt**-shortcuts on macOS, configure the `Option key as a Meta key` in your preferred terminal emulator:

- In **Ghostty**, add the following line to `~/.config/ghostty/config`: `macos-option-as-alt = left`
- In **iTerm2**, go to: **Settings > Profiles > Keys**. Then set `Left Option Key` to `Esc+`.

In **iTerm2**, the usual macOS keyboard shortcuts also work when `SlovoKlad.itermkeymap` is imported via **Settings > Profiles > Keys > Key Bindings > Presets…**. For **Ghostty**, see `ghostty-config.txt` for the configuration.

If you want to use Command+1 through Command+5 (study sessions) in addition to Alt+1 through Alt+5, go to **Settings > Keys > Navigation Shortcuts > Shortcut to activate a tab** and change the modifier in **iTerm2** from Command to a different key combination. The corresponding Ghostty configuration is provided in `ghostty-config.txt`.

In scripts such as Hebrew and Cyrillic, handwritten (cursive) letters have different forms from printed letters. To display both correctly in **iTerm2**:

1. Go to **Settings > Profiles > Text**.
2. Set the regular font to `JetBrains Mono Regular` and the Non-ASCII Font to `Victor Mono Regular`. Then click `Manage Special Exceptions for this Font`, click `+`, and add the range `U+2500`–`U+259F`, assigning it to **JetBrains Mono** or whichever font you’re currently using.
3. Restart **iTerm2**.

In **SlovoKlad**, press `F3` to switch between the writing styles, if your font supports it.

On macOS, you can easily install both fonts with [Homebrew](https://brew.sh):

```bash
brew install --cask font-victor-mono
brew install --cask font-jetbrains-mono
```

In **Ghostty**, add the following lines to `~/.config/ghostty/config`:

```ini
font-family = "JetBrains Mono", "Victor Mono"
font-style = "Regular"
font-style-italic = "Italic"
```

If you’re using macOS, copy the contents of `ghostty-config.txt` into `~/.config/ghostty/config`.

For **iTerm2** only: turn off **Settings > Profiles > Terminal > Save lines to scrollback in alternate screen mode** to prevent scrollback issues.

# 4. UPDATE THE DEVELOPMENT TOOLS AND APPLICATION DEPENDENCIES

Run the following commands to update Ruby, Mise, FriBidi, Bundler, and the application's Ruby dependencies to their latest available versions.

```bash
# Update Homebrew and upgrade Mise and FriBidi
brew update
brew upgrade mise fribidi

# Upgrade Ruby managed by Mise
mise upgrade ruby

# Update Bundler and the application's dependencies
bundle update --bundler
bundle update
bundle install
```

# 5. KEYBOARD SHORTCUTS FOR INPUT FIELDS

## 5.1 Editing

| Shortcut | Action |
|---|---|
| `Control+X` | Cut the selected text and copy it to the system clipboard. |
| `Control+Y`, `Control+Shift+Z` | Redo (`Control+Shift+Z` doesn't work in all terminals). `Control+Shift+Z` works by default in **Ghostty**. To enable it in **iTerm2**, import `SlovoKlad.itermkeymap` via **Settings > Profiles > Keys > Key Bindings > Presets…**. |
| `Control+Z` | Undo. |
| `Control+T` | Swap the character behind the insertion point with the character in front of it. |

## 5.2 Navigation

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

## 5.3 Removing Text

| Shortcut | Action |
|---|---|
| `Control+W`, `Option+Backspace` | Delete the word to the left of the insertion point. |
| `Option+D`, `Fn+Option+Backspace` | Delete the word to the right of the insertion point. |
| `Control+H`, `Backspace` | Delete the character to the left of the insertion point. |
| `Backspace` | Delete the character to the left of the insertion point. |
| `Control+D`, `Fn+Backspace` | Delete the character to the right of the insertion point. |
| `Control+K` | Delete the text from the insertion point to the end of the line. |
| `Control+U` | Delete the text from the insertion point to the beginning of the line. |

## 5.4 Selecting Text

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
