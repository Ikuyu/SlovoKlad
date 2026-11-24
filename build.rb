# SLOVOKLAD – BUILD SCRIPT GUIDE
#
# PURPOSE
#
# The build.rb script prepares and packages Slovoklad as a
# standalone executable using the Tebako compiler.
#
# It automatically scans the project directory and reads
# .gitignore to determine which files should be excluded.
# Files containing local secrets, temporary files, Git data
# and development-related files are also excluded.
#
# The script creates a temporary staging directory containing
# all files required to run the application.
# It then builds a standalone executable for the current
# operating system, including the Ruby runtime.
# Ruby does not need to be installed on the target computer.
#
# REQUIREMENTS
#
# - Ruby installed on the build computer.
# - Tebako CLI installed and available in PATH.
# - Git installed (required for .gitignore processing).
# - A valid .gitignore file in the project directory.
#
# HOW TO USE
#
# 1. Open a terminal in the Slovoklad project directory.
# 2. Make sure Tebako is installed.
# 3. Run the following command:
#
# ruby build.rb
#
# The script will automatically:
#
# - Scan the project files.
# - Read and apply .gitignore rules.
# - Display included and excluded files.
# - Prepare the staging directory.
# - Compile the application for the current OS.
# - Save the executable in the dist directory.
# - Remove the temporary staging directory.
#
# OUTPUT
#
# The generated executable is stored in:
#
# dist/
#
# IMPORTANT
#
# This script builds only for the operating system on which
# it is executed.
#
# To create Windows, macOS and Linux versions, run the build
# process separately in suitable native build environments.
#
# Always review the file inclusion report before distributing
# the executable to ensure all required application resources
# are included.
#
# Make sure that .gitignore does not exclude files required
#
# by Slovoklad at runtime.
#
# Ruby version used by Tebako can be configured through:
#
# TEBAKO_RUBY_VERSION
#
# Default version: 4.0.6
#
# Example:
#
# TEBAKO_RUBY_VERSION=4.0.6 ruby build.rb

require 'fileutils'
require 'find'
require 'open3'
require 'set'
require 'time'

# ============================================================
# CONFIGURATION
# ============================================================

ROOT_DIR = File.expand_path(__dir__)

DIST_DIR = File.join(ROOT_DIR, 'dist')
STAGING_DIR = File.join(ROOT_DIR, 'dist_staging')

ENTRY_POINT = 'app.rb'

# Pin the Ruby runtime used by Tebako.

def detect_ruby_version
  lockfile = File.join(ROOT_DIR, 'Gemfile.lock')
  gemfile = File.join(ROOT_DIR, 'Gemfile')

  # 1. Read the version from Gemfile.lock
  if File.file?(lockfile)
    content = File.read(lockfile)

    return Regexp.last_match(1) if content =~ /^RUBY VERSION\s*\n\s*ruby\s+(\d+\.\d+\.\d+)/
  end

  # 2. Read the version from Gemfile
  if File.file?(gemfile)
    content = File.read(gemfile)

    return Regexp.last_match(1) if content =~ /^\s*ruby\s+['"](\d+\.\d+\.\d+)['"]/
  end

  # 3. Fall back to the currently running Ruby version
  RUBY_VERSION
end

# Files and folders that must never enter the package.
ALWAYS_EXCLUDE = %w[
  .git
  .gitignore
  build.rb
  dist
  dist_staging
].freeze

# Protect local secrets, even if .gitignore is incomplete.
SECRET_PATTERNS = [
  /^\.env(?:\.|$)/,
  /\.pem$/,
  /\.key$/
].freeze

# ============================================================
# TERMINAL COLORS
# ============================================================

CLR_RESET  = "\e[0m"
CLR_BOLD   = "\e[1m"
CLR_GREEN  = "\e[32m"
CLR_YELLOW = "\e[33m"
CLR_BLUE   = "\e[34m"
CLR_RED    = "\e[31m"
CLR_CYAN   = "\e[36m"

def info(message)
  puts "#{CLR_BLUE}INFO#{CLR_RESET} #{message}"
end

def success(message)
  puts "#{CLR_GREEN}OK#{CLR_RESET} #{message}"
end

def warning(message)
  warn "#{CLR_YELLOW}WARNING#{CLR_RESET} #{message}"
end

def error(message)
  warn "#{CLR_RED}ERROR#{CLR_RESET} #{message}"
end

def ensure_command_installed(command, install_instruction)
  windows = RUBY_PLATFORM.match?(/mingw|mswin|cygwin/)

  extensions = if windows
                 ENV.fetch('PATHEXT', '.COM;.EXE;.BAT;.CMD').split(';')
               else
                 ['']
               end

  commands = if windows && File.extname(command).empty?
               extensions.map { |extension| "#{command}#{extension}" }
             else
               [command]
             end

  installed = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
    commands.any? do |candidate|
      path = File.join(directory, candidate)
      File.file?(path) && (windows || File.executable?(path))
    end
  end

  return if installed

  error("#{command} is not installed.")
  puts "Install it first: #{install_instruction}"
  exit(1)
end

# ============================================================
# TEBAKO CHECK
# ============================================================

def ensure_tebako_installed
  return if system('tebako', '--version', out: File::NULL, err: File::NULL)

  error('Tebako CLI was not found.')
  puts 'Install instructions: https://www.tebako.org/docs/guides/install/'
  exit(1)
end

# ============================================================
# APPLICATION NAME
# ============================================================

def application_name
  path = File.join(ROOT_DIR, 'app_info.yml')

  return 'slovoklad' unless File.file?(path)

  require 'yaml'
  data = YAML.safe_load_file(path) || {}

  name = data['app_name'].to_s
  name = 'slovoklad' if name.empty?

  name.downcase.gsub(/[^a-z0-9_-]+/, '_')
rescue StandardError => e
  error("Could not read app_info.yml: #{e.message}")
  exit(1)
end

# ============================================================
# PROJECT SCANNER
# ============================================================

def excluded_manually?(relative_path)
  parts = relative_path.split('/')

  return true if parts.any? { |part| ALWAYS_EXCLUDE.include?(part) }
  return true if parts.any? { |part| part == '.DS_Store' }
  return true if parts.any? { |part| part.start_with?('.env') }

  SECRET_PATTERNS.any? { |pattern| relative_path.match?(pattern) }
end

def scan_project
  info('Scanning project files...')

  files = []

  Find.find(ROOT_DIR) do |path|
    next if path == ROOT_DIR

    relative = path.delete_prefix("#{ROOT_DIR}#{File::SEPARATOR}").tr('\\', '/')

    if File.directory?(path)
      next unless ALWAYS_EXCLUDE.include?(File.basename(path))

      Find.prune

    end

    next unless File.file?(path)
    next if File.symlink?(path)

    files << relative unless excluded_manually?(relative)
  end

  files.sort
end

# ============================================================
# GITIGNORE FILTER
# ============================================================

def filter_gitignored(files)
  gitignore = File.join(ROOT_DIR, '.gitignore')

  unless File.file?(gitignore)
    warning('.gitignore was not found. No Git ignore rules will be applied.')
    return files
  end

  info('Checking .gitignore rules...')

  input = files.join("\0") + "\0"

  stdout, stderr, status = Open3.capture3(
    'git',
    '-C', ROOT_DIR,
    'check-ignore',
    '--no-index',
    '-z',
    '--stdin',
    stdin_data: input
  )

  # Exit code 1 means no matching ignored files.
  unless status.success? || status.exitstatus == 1
    error("Git ignore check failed: #{stderr}")
    exit(1)
  end

  ignored = stdout.split("\0").to_set

  included = files.reject { |file| ignored.include?(file) }
  excluded = files.select { |file| ignored.include?(file) }

  [included, excluded]
rescue Errno::ENOENT
  error('Git is required to interpret .gitignore correctly.')
  exit(1)
end

# ============================================================
# STAGING DIRECTORY
# ============================================================

def prepare_staging_directory
  FileUtils.rm_rf(STAGING_DIR)
  FileUtils.mkdir_p(STAGING_DIR)

  files = scan_project
  included, ignored = filter_gitignored(files)

  puts
  puts "#{CLR_BOLD}PROJECT SCAN#{CLR_RESET}"
  puts "Files found:       #{files.size}"
  puts "Included:          #{included.size}"
  puts "Excluded:          #{files.size - included.size}"

  puts
  puts "#{CLR_GREEN}FILES INCLUDED#{CLR_RESET}"

  included.each do |relative|
    puts "  + #{relative}"

    source = File.join(ROOT_DIR, relative)
    destination = File.join(STAGING_DIR, relative)

    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination, preserve: true)
  end

  puts
  puts "#{CLR_YELLOW}FILES EXCLUDED#{CLR_RESET}"

  ignored.each do |relative|
    puts "  - #{relative} (.gitignore)"
  end

  puts
  success('Staging directory prepared.')

  unless included.include?(ENTRY_POINT)
    error("Entry point #{ENTRY_POINT} is missing from the staging directory.")
    exit(1)
  end

  if File.file?(File.join(ROOT_DIR, 'Gemfile')) &&
     !included.include?('Gemfile.lock')
    warning('Gemfile.lock is missing or excluded. Check dependency reproducibility.')
  end
end

# ============================================================
# NATIVE PLATFORM DETECTION
# ============================================================

def current_platform
  case RUBY_PLATFORM
  when /darwin/
    'macos'
  when /linux/
    'linux'
  when /mingw|mswin|cygwin/
    'windows'
  else
    error("Unsupported host platform: #{RUBY_PLATFORM}")
    exit(1)
  end
end

def prepare_icon_assets
  platform = current_platform
  source = File.join(ROOT_DIR, 'assets', 'logo.webp')
  platform_dir = File.join(DIST_DIR, platform)

  unless File.file?(source)
    error("Application logo not found: #{source}")
    exit(1)
  end

  FileUtils.mkdir_p(platform_dir)

  info("Preparing #{platform} application icon...")

  case platform
  when 'macos'
    iconset = File.join(platform_dir, 'Slovoklad.iconset')
    output = File.join(platform_dir, 'Slovoklad.icns')

    FileUtils.rm_rf(iconset)
    FileUtils.mkdir_p(iconset)

    sizes = {
      'icon_16x16.png' => 16,
      'icon_16x16@2x.png' => 32,
      'icon_32x32.png' => 32,
      'icon_32x32@2x.png' => 64,
      'icon_128x128.png' => 128,
      'icon_128x128@2x.png' => 256,
      'icon_256x256.png' => 256,
      'icon_256x256@2x.png' => 512,
      'icon_512x512.png' => 512,
      'icon_512x512@2x.png' => 1024
    }

    sizes.each do |filename, size|
      destination = File.join(iconset, filename)

      next if system(
        'magick', source,
        '-resize', "#{size}x#{size}",
        '-background', 'none',
        '-gravity', 'center',
        '-extent', "#{size}x#{size}",
        destination
      )

      error("Could not generate icon: #{filename}")
      exit(1)
    end

    unless system('iconutil', '-c', 'icns', iconset, '-o', output)
      error('Could not create the macOS ICNS icon.')
      exit(1)
    end

    FileUtils.rm_rf(iconset)

  when 'windows'
    output = File.join(platform_dir, 'Slovoklad.ico')

    unless system(
      'magick', source,
      '-resize', '256x256',
      '-background', 'none',
      '-gravity', 'center',
      '-extent', '256x256',
      '-define', 'icon:auto-resize=256,128,64,48,32,16',
      output
    )
      error('Could not create the Windows ICO icon.')
      exit(1)
    end

  when 'linux'
    output = File.join(platform_dir, 'Slovoklad.png')

    unless system(
      'magick', source,
      '-resize', '512x512',
      '-background', 'none',
      '-gravity', 'center',
      '-extent', '512x512',
      output
    )
      error('Could not create the Linux PNG icon.')
      exit(1)
    end
  end

  success("Application icon prepared: #{output}")
end

def create_macos_app_bundle
  return unless current_platform == 'macos'

  platform_dir = File.join(DIST_DIR, 'macos')
  executable = File.join(platform_dir, 'Slovoklad')
  icon = File.join(platform_dir, 'Slovoklad.icns')

  app_bundle = File.join(platform_dir, 'Slovoklad.app')
  contents = File.join(app_bundle, 'Contents')
  macos_dir = File.join(contents, 'MacOS')
  resources_dir = File.join(contents, 'Resources')

  unless File.file?(executable) && File.file?(icon)
    error('Executable or ICNS icon is missing. Cannot create macOS app bundle.')
    exit(1)
  end

  info('Creating macOS application bundle...')

  FileUtils.rm_rf(app_bundle)
  FileUtils.mkdir_p(macos_dir)
  FileUtils.mkdir_p(resources_dir)

  FileUtils.cp(icon, File.join(resources_dir, 'Slovoklad.icns'))

  launcher = <<~'BASH'
    #!/bin/bash

    executable="__EXECUTABLE__"

    if [ -d "/Applications/iTerm.app" ] || [ -d "$HOME/Applications/iTerm.app" ]; then
      open -a iTerm "$executable"
    elif [ -d "/Applications/Ghostty.app" ] || [ -d "$HOME/Applications/Ghostty.app" ]; then
      open -a Ghostty --args -e "$executable"
    else
      osascript -e 'display alert "Geen geschikte terminal gevonden" message "Installeer iTerm2 of Ghostty om SlovoKlad te starten."'
    fi
  BASH

  launcher = launcher.sub('__EXECUTABLE__', executable)

  launcher_path = File.join(macos_dir, 'Slovoklad')
  File.write(launcher_path, launcher)
  FileUtils.chmod(0o755, launcher_path)

  identifier = "org.slovoklad.#{application_name}"

  plist = <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>Slovoklad</string>
      <key>CFBundleIdentifier</key>
      <string>#{identifier}</string>
      <key>CFBundleName</key>
      <string>SlovoKlad</string>
      <key>CFBundleDisplayName</key>
      <string>SlovoKlad</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleIconFile</key>
      <string>Slovoklad</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>NSHighResolutionCapable</key>
      <true/>
    </dict>
    </plist>
  PLIST

  File.write(File.join(contents, 'Info.plist'), plist)

  success("macOS application bundle created: #{app_bundle}")
end

def create_linux_desktop_entry
  return unless current_platform == 'linux'

  platform_dir = File.join(DIST_DIR, 'linux')
  executable = File.join(platform_dir, 'Slovoklad')
  icon = File.join(platform_dir, 'Slovoklad.png')
  desktop_file = File.join(platform_dir, 'Slovoklad.desktop')

  unless File.file?(executable) && File.file?(icon)
    error('Linux executable or PNG icon is missing.')
    exit(1)
  end

  info('Creating Linux desktop entry...')

  escape_exec = lambda do |path|
    escaped = path.gsub(/[\\"`$]/) { |char| "\\#{char}" }
    %("#{escaped}")
  end

  desktop_entry = <<~DESKTOP
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=SlovoKlad
    Comment=SlovoKlad study application
    Exec=#{escape_exec.call(executable)}
    Path=#{platform_dir}
    Icon=#{icon}
    Terminal=true
    Categories=Education;
    StartupNotify=false
  DESKTOP

  File.write(desktop_file, desktop_entry)
  FileUtils.chmod(0o755, desktop_file)

  success("Linux desktop entry created: #{desktop_file}")
end

def create_linux_installer
  return unless current_platform == 'linux'

  platform_dir = File.join(DIST_DIR, 'linux')
  installer = File.join(platform_dir, 'install.sh')

  script = <<~'BASH'
    #!/bin/bash
    set -e

    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    APP_DIR="$HOME/.local/share/slovoklad"
    APPLICATIONS_DIR="$HOME/.local/share/applications"

    mkdir -p "$APP_DIR" "$APPLICATIONS_DIR"

    cp "$SCRIPT_DIR/Slovoklad" "$APP_DIR/Slovoklad"
    cp "$SCRIPT_DIR/Slovoklad.png" "$APP_DIR/Slovoklad.png"
    chmod +x "$APP_DIR/Slovoklad"

    escape_desktop_value() {
      local value="$1"
      value="${value//\\/\\\\}"
      value="${value//\"/\\\"}"
      value="${value//\`/\\\`}"
      value="${value//\$/\\\$}"
      printf '%s' "$value"
    }

    EXEC_PATH="$(escape_desktop_value "$APP_DIR/Slovoklad")"
    APP_PATH="$(escape_desktop_value "$APP_DIR")"
    ICON_PATH="$(escape_desktop_value "$APP_DIR/Slovoklad.png")"

    cat > "$APPLICATIONS_DIR/Slovoklad.desktop" <<EOF
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=SlovoKlad
    Comment=SlovoKlad study application
    Exec="$EXEC_PATH"
    Path=$APP_PATH
    Icon=$ICON_PATH
    Terminal=true
    Categories=Education;
    StartupNotify=false
    EOF

    chmod +x "$APPLICATIONS_DIR/Slovoklad.desktop"

    echo "SlovoKlad has been installed in your application menu."
  BASH

  File.write(installer, script)
  FileUtils.chmod(0o755, installer)

  success("Linux installer created: #{installer}")
end

def embed_windows_icon
  return unless current_platform == 'windows'

  platform_dir = File.join(DIST_DIR, 'windows')
  executable = File.join(platform_dir, 'Slovoklad.exe')
  icon = File.join(platform_dir, 'Slovoklad.ico')

  unless File.file?(executable) && File.file?(icon)
    error('Windows executable or ICO icon is missing.')
    exit(1)
  end

  info('Embedding application icon into Windows executable...')

  unless system('rcedit', executable, '--set-icon', icon)
    error('Could not embed the application icon into the Windows executable.')
    exit(1)
  end

  success('Windows application icon embedded successfully.')
end

def ensure_icon_tools
  platform = current_platform

  ensure_command_installed(
    'magick',
    'Install ImageMagick: https://imagemagick.org/script/download.php'
  )

  case platform
  when 'macos'
    ensure_command_installed(
      'iconutil',
      'Install or use the macOS Command Line Developer Tools.'
    )
  when 'windows'
    ensure_command_installed(
      'rcedit',
      'Install rcedit and make sure it is available in PATH.'
    )
  end

  success('All required icon tools are available.')
end

# ============================================================
# BUILD
# ============================================================

# ============================================================
# BUILD OVERVIEW
# ============================================================

def print_build_overview(name)
  platforms = {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux'
  }

  puts
  puts "#{CLR_BOLD}SLOVOKLAD BUILD OVERVIEW#{CLR_RESET}"
  puts

  platforms.each do |platform, label|
    extension = platform == 'windows' ? '.exe' : ''
    filename = "Slovoklad#{extension}"
    path = File.join(DIST_DIR, platform, filename)

    if File.file?(path)
      size_mb = File.size(path) / 1024.0 / 1024.0

      puts "#{CLR_GREEN}OK#{CLR_RESET}  #{label.ljust(8)} " \
           "#{filename} (#{format('%.1f', size_mb)} MB)"
    else
      puts "#{CLR_YELLOW}--#{CLR_RESET}  #{label.ljust(8)} Nog niet gebouwd"
    end
  end

  puts
end

def build_executable
  platform = current_platform
  name = application_name

  platform_dir = File.join(DIST_DIR, platform)
  FileUtils.mkdir_p(platform_dir)

  extension = platform == 'windows' ? '.exe' : ''
  output = File.join(platform_dir, "Slovoklad#{extension}")

  info("Building #{platform.upcase} executable...")

  command = [
    'tebako', 'press',
    '-r', STAGING_DIR,
    '-e', ENTRY_POINT,
    '-o', output,
    '-m', 'self-contained'
  ]

  puts command.join(' ')
  puts

  unless system(*command)
    error("Build failed for #{platform}.")
    exit(1)
  end

  unless File.file?(output)
    error('Tebako reported success but the output file is missing.')
    exit(1)
  end

  success("Executable created: #{output}")

  create_macos_app_bundle
  create_linux_desktop_entry
  create_linux_installer
  embed_windows_icon

  history_file = File.join(DIST_DIR, 'build_history.log')

  File.open(history_file, 'a') do |file|
    file.puts [
      Time.now.iso8601,
      platform,
      RUBY_VERSION,
      File.basename(output),
      "#{(File.size(output) / 1024.0 / 1024.0).round(1)} MB"
    ].join(' | ')
  end

  print_build_overview(name)
end

# ============================================================
# MAIN
# ============================================================

begin
  Dir.chdir(ROOT_DIR)

  ensure_tebako_installed
  ensure_icon_tools

  info('Tebako will select the Ruby runtime automatically.')

  prepare_staging_directory
  prepare_icon_assets
  build_executable

  puts
  success('Build completed successfully.')
ensure
  FileUtils.rm_rf(STAGING_DIR)
end
