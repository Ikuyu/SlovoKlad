module AppTranslations
  TRANSLATIONS = {
    en: {
      # {} will be use to collapse/expand tree items
      menu_app_name: '%<app_name>s',
      menu_help: 'Help',
      sub_menu_about: 'About',
      sub_menu_visit_website: 'Visit website',
      sub_menu_compose_support_email: 'Compose support email',
      menu_title: 'Menu F10',
      about_title: 'About',
      table_title: 'Deck ]',
      tree_title: 'Library [',
      print_header: 'Deck',
      statusbar_speech_command_not_configured: 'Speech not configured (use --speech-command and --speech-voice)',
      statusbar_speech_command_missing_placeholders: 'Speech command template must include {text} and {voice}',
      statusbar_speech_command_not_found: 'Speech command not found',
      statusbar_speech_command_invalid: 'Invalid speech command template',
      statusbar_no_change: 'No change',
      statusbar_already_set: 'already set',
      statusbar_rename_can_only_be_used_in_tree: "'Rename' can only be used in the library",
      statusbar_add_can_only_be_used_in_deck: "'Add' can only be used in a deck",
      statusbar_edit_can_only_be_used_in_deck: "'Edit' can only be used in a deck",
      statusbar_remove_duplicates_from: 'Remove all duplicates from',
      statusbar_x_duplicates_removed: 'duplicate cards removed',
      statusbar_no_duplicates_found_in: 'No duplicate cards found in',
      statusbar_no_duplicates_found_in_selection: 'No duplicate cards in the selection',
      statusbar_duplicates_removed_from: 'duplicate cards successfully removed from',
      statusbar_nothing_to_reset_in: 'Nothing to reset in',
      statusbar_selected_items: 'selected items',
      statusbar_reset_success: 'cards successfully reset in',
      statusbar_reset_all_in: 'Reset all decks in',
      statusbar_contains_sub_decks: 'contains sub-decks (add ! to override)',
      statusbar_title: 'Command :',
      statusbar_new_no_write_last_change: 'No write since last change (add ! to override)',
      statusbar_saved: 'Saved',
      statusbar_new_file: '[New]',
      statusbar_written: 'Written',
      statusbar_opened: 'File loaded successfully',
      statusbar_imported: 'Successfully imported',
      statusbar_imported_into: 'cards into',
      statusbar_argument_required: 'Argument required',
      statusbar_saveas_argument_required: ':saveas <filename>',
      statusbar_open_argument_required: ':open <filename>',
      statusbar_theme_argument_required: ':theme <filename>',
      statusbar_import_argument_required: ':import <filename>',
      statusbar_file_not_found: 'File not found',
      statusbar_theme_not_found: 'Theme not found',
      statusbar_theme_hash_error: 'Theme must return a valid key-value Hash',
      statusbar_yaml_hash_error: 'YAML data is not a valid Hash structure',
      statusbar_file_removed_or_deleted: 'File has been moved or deleted',
      statusbar_theme_error: 'Invalid theme structure',
      statusbar_theme_syntax_error: 'syntax error(s) found',
      statusbar_no_filename_known: 'No filename known',
      statusbar_save_not_dirty: 'No changes',
      statusbar_unexpected_extension: 'Unexpected extension (add ! to override)',
      statusbar_already_exists: 'File exists (add ! to override)',
      statusbar_quit_warning: 'Unsaved changes (add ! to override)',
      statusbar_save_error: 'Save error',
      statusbar_write_error: 'Write error',
      statusbar_open_error: 'Open error',
      statusbar_empty_file_error: 'Empty data file (0 bytes)',
      statusbar_import_error: 'Import error',
      statusbar_print_error: 'Print error',
      statusbar_not_a_source_or_deck: 'no source or deck selected',
      statusbar_no_deck_selected: 'no deck selected',
      statusbar_dir_not_exists: 'directory does not exist',
      statusbar_import_no_valid_csv: 'The CSV file is invalid or not in order',
      statusbar_include_header: 'Include header? (y/n)',
      statusbar_export_success: 'Packed',
      statusbar_template_file_error: 'failed to generate print template',
      statusbar_printed_from: 'cards from',
      statusbar_exported_decks: 'decks',
      statusbar_exported_cards: 'cards',
      statusbar_exported_into: 'into',
      statusbar_export_error: 'Export error',
      statusbar_choose_format: 'Choose format',
      statusbar_format: '<1> CSV or <2> XML',
      statusbar_deck_not_empty: 'The deck already contains cards. Append anyway? (y/n)',
      statusbar_table_error: 'Table error',
      statusbar_deck_empty: 'empty deck',
      statusbar_save_confirmation: 'Save anyway? (y/n)',
      statusbar_beeps_on: 'Beeps: on',
      statusbar_beeps_off: 'Beeps: off',
      statusbar_rotation_indicator_on: 'Rotation indicator: on',
      statusbar_rotation_indicator_off: 'Rotation indicator: off',
      statusbar_replace_with: 'Replace with',
      statusbar_unknown_command: 'Unknown command',
      statusbar_show_active_corner: 'Active corner style',
      statusbar_show_active_theme: 'Active theme',
      statusbar_show_active_lang: 'Active language',
      statusbar_show_active_marker: 'Active marker',
      statusbar_corner_not_available: 'Corner not available',
      statusbar_theme_not_available: 'Theme not available',
      statusbar_lang_not_available: 'Language not available',
      statusbar_marker_not_available: 'Marker not available',
      statusbar_corners: 'Corners',
      statusbar_available_corners: 'plain, rounded',
      statusbar_languages: 'Languages',
      statusbar_available_languages: 'en, nl',
      statusbar_themes: 'Themes',
      statusbar_available_themes: 'default, cga, julia, crt, amber, borland, tos, dracula, teletext, c64, terminal',
      statusbar_markers: 'Markers',
      statusbar_available_markers: 'cross, block, plus, asterisk',
      statusbar_corner_succes: 'Corner successfully set to',
      statusbar_theme_succes: 'Theme successfully set to',
      statusbar_lang_succes: 'Language successfully set to English',
      statusbar_marker_succes: 'Marker successfully set to',
      statusbar_no_cards_available: 'no cards available',
      statusbar_not_enough_cards_selected: 'not enough cards selected',
      table_header_field1: 'Study',
      table_header_field2: 'Term',
      table_header_field3: 'Context',
      table_header_field4: 'Meaning',
      table_title_add_card: 'Deck: add',
      table_title_edit_card: 'Deck: edit',
      statusbar_modification_eror: 'Modification error',
      statusbar_term_meaning_required: 'Term and meaning are required',
      statusbar_query_required: 'Query is required',
      statusbar_name_required: 'Name is required',
      table_placeholder_term: 'Term',
      table_placeholder_context: 'Context',
      table_placeholder_meaning: 'Meaning',
      tree_title_rename: 'Library: rename',
      statusbar_form_error: 'Form error',
      statusbar_no_name_specified: 'no name specified',
      hint: '⇥ Tab: Cycle Fields, ↵ Enter: OK, Esc: Cancel',
      statusbar_search_error: 'Search error',
      statusbar_replace_error: 'Replace error',
      search_title_table: 'Deck: search',
      search_title_tree: 'Library: search',
      search_and_replace_title_table: 'Deck: find and replace',
      search_and_replace_title_tree: 'Library: find and replace',
      search_placeholder: 'Search…',
      replace_placeholder: 'Replace with…',
      search_case_sensitive: 'Case-sensitive',
      search_regex: 'Regex',
      search_all: 'All',
      statusbar_no_query_specified: 'no query specified',
      statusbar_no_results_found: 'no results found',
      alert_title: '[!] Alert',
      alert_config_err_msg: "Failed to load settings.\n\nRunning app with default values",
      alert_cancel_ok: 'Press <Enter> to confirm or <Esc> to cancel',
      alert_ok: 'Press <Enter> to continue',
      statusbar_study_session_error: 'Study session error',
      statusbar_study_memory_limit_reached: 'The maximum number of cards allowed in the Memory game is',
      statusbar_study_memory_init_msg: 'Find the matching pairs',
      statusbar_study_two_of_a_kind_msg: 'Collect as many pairs as possible',
      study_status_screen_play_two_of_a_kind_shortcuts: '<Enter> Ask a card / Hand over a card | <Tab> I don’t have that card',
      statusbar_study_two_of_a_kind_warning: 'You have the card—hand it over',
      statusbar_study_two_of_a_kind_user: 'User',
      statusbar_study_two_of_a_kind_computer: 'Computer',
      study_status_screen_drill: 'DRILL',
      study_status_screen_quiz: 'QUIZ',
      study_status_screen_multiple_choice: 'MULTIPLE CHOICE',
      study_status_screen_play_memory: 'MEMORY GAME',
      study_status_screen_play_two_of_a_kind: 'TWO OF A KIND GAME',
      study_status_screen_flashcards: 'FLASHCARDS',
      study_status_screen_start: 'Select a level <1–3>',
      study_status_screen_finished: 'Press any key to continue',
      study_status_screen_passed: 'Well done',
      study_status_screen_exercise_completed: 'Exercise completed',
      study_status_screen_memory_game_completed: 'All pairs found',
      study_status_screen_failed: 'Try again later',
      study_multiple_choice_right: 'Right',
      study_multiple_choice_wrong: 'Wrong',
      study_modus_front: 'FRT',
      study_modus_back: 'BCK',
      study_modus_alternate: 'ALT',
      study_modus_mixed: 'MIX',
      study_quiz_front: 'Front',
      study_quiz_back: 'Back',
      study_question: 'Q:',
      study_answer: 'A:',
      study_context: 'Context: ',
      study_context_not_available: 'n/a',
      study_drill_title: 'Drill',
      study_quiz_title: 'Quiz',
      study_multiple_choice_title: 'Multiple Choice',
      study_play_memory_title: 'Play Memory',
      study_play_two_of_a_kind_title: 'Play Two of a Kind',
      statusbar_difficulty: 'Difficulty',
      statusbar_levels: '<1> Easy <2> Medium <3> Hard',
      statusbar_good_luck: 'Good luck',
      statusbar_test_about_to_begin: 'The test is about to begin',
      statusbar_min_req_cards: 'select a deck with at least four cards',
      study_test_passed: 'Test passed',
      study_test_failed: 'Test failed',
      study_test_completed_on_time: 'completed on time',
      study_test_time_up: 'time is up',
      help_main_title: 'Help',
      help_main_screen_title: 'Help: main screen',
      help_commands_title: 'Help: commands',
      help_library_title: 'Help: library',
      help_deck_title: 'Help: deck',
      help_study_title: 'Help: study',
      help_input_fields_title: 'Help: input fields',
      mail_subject: '%<app_name>s Support request',
      about_message: <<~TEXT,
        %<app_name>s

        TUI dashboard study-aid

        Version %<app_version>s

        Copyright (c) %<app_copyright_year>s Edwin H. Jonkvorst.
        All rights reserved.
      TEXT
      help_main: <<~TEXT,
        1 : This help menu
        2 : Main screen
        3 : Commands
        4 : Library
        5 : Deck
        6 : Study
        7 : Input fields
      TEXT
      help_main_screen: <<~TEXT,
        ?       : Help
        :       : Menu
        [       : Library
        ]       : Deck
        Tab     : Next panel
        Backtab : Previous panel
        |       : Toggle show vertical dividers
        I       : Toggle rotation indicator
        F3      : Toggle the handwritten letter style
        C       : Toggle corner style (round/plain)
        S       : Toggle marker symbol
        T       : Next theme
        Shift+T : Previous theme
      TEXT
      help_commands: <<~TEXT,
        Commands can generally be run using their full name, the first letter, or the first two letters.
        Exceptions:
        - search, replace, reset, and export can be run using their full name or the first three letters.
        - Study sessions and “print the current working directory” can only be started using their abbreviated forms.
        - Compound commands can be shortened to their initial letters (e.g., an for add-node).
        For plural forms, append -s.

        :?                  : Show help
        :reset              : Reset selected deck
        :dedup              : Remove duplicate cards
        :beeps              : Toggle beeps
        :rotation-indicator : Toggle rotation indicator
        :langs              : Show available languages
        :lang [language]    : Set language
        :corners            : Show available corners
        :corner [corner]    : Set corner
        :markers            : Show available marker symbols
        :marker [marker]    : Set marker symbol
        :themes             : Show available themes
        :theme [theme]      : Set theme
        :search             : Search
        :replace            : Replace
        :add-node           : Add item to the library
        :rename-node        : Rename item in the library
        :delete-nodes       : Delete node(s) from the library
        :add-card           : Add card to a deck
        :edit-card          : Edit card in a deck
        :delete-cards       : Delete card(s) from a deck
        :dr                 : Drill
        :qz                 : Quiz
        :mc                 : Multiple choice
        :pm                 : Play Memory
        :tk                 : Play Two of a Kind
        :pwd                : Print the current working directory
        :lct                : Load a custom theme
        :new                : New library
        :o <filename>       : Load file
        :w [filename]       : Save, optionally to a new filename
        :wq                 : Save and quit
        :saveas <filename>  : Save as filename and use it as the current filename
        :import <filename>  : Import a CSV file
        :export             : Export files in CSV or XML format
        :print              : Print a deck
        :q                  : Quit
        :q!                 : Force quit without saving
      TEXT
      help_library: <<~TEXT,
        H, {, ←                         : Collapse
        L, }, →                         : Expand
        Control+P, K, ↑                 : Row up
        Control+N, J, ↓                 : Row down
        G, Home                         : Jump to top
        Shift+G, End                    : Jump to bottom
        Control+U, PageUp               : Page up
        Control+D, PageDown             : Page down
        Option+N, Option+P,
           Shift+J, Shift+K,
           Shift+↓, Shift+↑,
           Control+Shift+A
           Shift+M, Option+Space,
           Shift+Home, Shift+End,
           Shift+PageUp, Shift+PageDown : Mark items for bulk deletion
        Option+Enter, A, +, F7          : Add item
        Enter, Shift+R, F2              : Rename item
        Backspace, -, F8                : Delete item(s)
        /, Control+F, F                 : Search
        \\, Control+H, Shift+F           : Search and replace
        N, Control+N, J, ↓              : Search next
        Shift+N, Control+P, J, ↑        : Search previous
        Control+Z                       : Undo
        Control+Y, Shift+Control+Z      : Redo
        M                               : Switch modus
        D                               : Remove duplicates from selected deck(s)
        R                               : Reset selected deck(s)
        ⌥1 ⌥2 ⌥3 ⌥4                     : Start a study session with the selected deck
      TEXT
      help_deck: <<~TEXT,
        Control+P, K, ↑                 : Row up
        Control+N, J, ↓                 : Row down
        G, Home                         : Jump to top
        Shift+G, End                    : Jump to bottom
        Control+U, PageUp               : Page up
        Control+D, PageDown             : Page down
        Option+N, Option+P,
           Shift+J, Shift+K,
           Shift+↓, Shift+↑,
           Control+Shift+A
           Shift+M, Option+Space,
           Shift+Home, Shift+End,
           Shift+PageUp, Shift+PageDown : Mark cards for bulk deletion
        Space                           : (De)select card(s)
        Option+Enter, A, +, F7          : Add card
        Enter, E, F2                    : Edit card
        Backspace, -, F8                : Delete card(s)
        /, Control+F, F                 : Search
        \\, Control+H, Shift+F           : Search and replace
        N, Control+N, J, ↓              : Search next
        Shift+N, Control+P, K, ↑        : Search previous
        Control+Z                       : Undo
        Control+Y, Control+Shift+Z      : Redo
        1 2 3 4                         : Sort column
        M                               : Switch modus
        D                               : Remove duplicates from selected deck(s)
        R                               : Reset selected deck(s)
        ⌥1 ⌥2 ⌥3 ⌥4                     : Start a study session
      TEXT
      help_study: <<~TEXT,
        D = Drill
        Q = Quiz
        MC = Multiple Choice
        PM = Play Memory
        TK = Two of a Kind

        A study session is completed when all cards are:
        - memorized, without time pressure (D);
        - have been tested within time (Q & MC); or
        - are paired as a pair in the Memory or Two of a Kind game (PM, TK).

        Note: The J and K keys are used in PM to enter codes.

        Control+P, K, ↑                : Row up (D, PM, TK)
        Control+N, J, ↓                : Row down / up (D, PM, TK)
        G, Home                        : Jump to top / beginning (D, PM, TK)
        Shift+G, End                   : Jump to bottom / end (D, PM, TK)
        Control+U PageUp               : Page up (D, PM, TK)
        Control+D PageDown             : Page down (D, PM, TK)
        F4                             : Toggle show context (D, Q, MC & PM, TK)
        F5                             : Pause (D, Q, MC & PM, TK)
        S                              : Switch seconds timer (D)
        T                              : Toggle timer (D)
        Space, Enter                   : Show answer (D, Q) / next card (Q)
        1 2 3 4                        : Answer (MC)
        Tab                            : Exclude card from future exercises (D, Q & MC) & show next card (Q & MC) | I don’t have that card (TK)
        F2                             : Edit card (D, Q, MC & PM) | Ask a card / Hand over a card (TK)

      TEXT
      help_input_fields: <<~TEXT
        === EDITING ===
           Control+X.                 : Cut the selected text and copy it to the system clipboard.
           Control+Y, Control+Shift+Z : Redo (Control+Shift+Z doesn't work in all terminals).
           Control+Z                  : Undo.
           Control+T                  : Swap the character behind the insertion point with the character in front of the insertion point.

        === NAVIGATION ===
           Control+F, →           : Move one character forwards.
           Control+B, ←           : Move one character backwards.
           Fn+↑, Fn+←,
              Option+↑, Control+A : Move the insertion point to the beginning of the line.
           Fn+↓, Fn+→,
              Option+↓, Control+E : Move the insertion point to the end of the line.
           Option+←               : Move the insertion point to the beginning of the previous word.
           Option+→               : Move the insertion point to the end of the next word.
           Control+L              : Centre the insertion point in the text.
           Tab, Control+P         : Next inputfield.
           Backtab, Control+N     : Previous inputfield.

        === REMOVING TEXT ===
           Control+W, Option+Backspace : Delete the word to the left of the insertion point.
           Fn+Option+Backspace         : Delete the word to the right of the insertion point.
           Control+H, Backspace        : Delete the character to the left of the insertion point.
           Control+D, Fn+Backspace     : Delete the character to the right of the insertion point.
           Control+K                   : Delete text from the right of the insertion point to the end of the line.
           Control+U                   : Delete text from the insertion point to the beginning of the line.

        === SELECTING TEXT ===
           Control+A, Control+Shift+A : Select all text.
           Control+Shift+F, Shift+→   : Extend text selection one character to the right.
           Control+Shift+B, Shift+←   : Extend text selection one character to the left.
           Option+Shift+←             : Extend text selection to the beginning of the current word, then to the beginning of the following word if pressed again.
           Option+Shift+→             : Extend text selection to the end of the current word, then to the end of the following word if pressed again.
           Shift+↑, Fn+Shift+↑,
              Option+Shift+↑          : Extend text selection to the beginning of the line.
           Shift+↓, Fn+Shift+↓,
              Option+Shift+↓          : Extend text selection to the end of the line.
              Control+Shift+L         : Extend the text selection to the centre of the text.
      TEXT
    },
    nl: {
      menu_app_name: '%<app_name>s',
      menu_help: 'Help',
      sub_menu_about: 'Over',
      sub_menu_visit_website: 'Bezoek website',
      sub_menu_compose_support_email: 'Supportmail schrijven',
      menu_title: 'Menu F10',
      about_title: 'Over',
      table_title: 'Kaartenbak ]',
      tree_title: 'Bibliotheek [',
      print_header: 'Kaartenbak',
      statusbar_speech_command_not_configured: 'Spraak niet geconfigureerd (gebruik --speech-command en --speech-voice)',
      statusbar_speech_command_missing_placeholders: 'Sjabloon voor spraakopdrachten moet {text} en {voice} bevatten',
      statusbar_speech_command_not_found: 'Spraakopdracht niet gevonden',
      statusbar_speech_command_invalid: 'Ongeldig sjabloon voor spraakopdrachten',
      statusbar_no_change: 'Geen wijziging',
      statusbar_already_set: 'al ingesteld',
      statusbar_rename_can_only_be_used_in_tree: "'Hernoemen' kan alleen in de bibliotheek worden gebruikt",
      statusbar_add_can_only_be_used_in_deck: "'Toevoegen' kan alleen in een kaartenbak worden gebruikt",
      statusbar_edit_can_only_be_used_in_deck: "'Bewerken' kan alleen in een kaartenbak worden gebruikt",
      statusbar_remove_duplicates_from: 'Alle dubbele kaarten verwijderen uit',
      statusbar_x_duplicates_removed: 'dubbele kaarten verwijderd',
      statusbar_no_duplicates_found_in: 'Geen dubbele kaarten gevonden in',
      statusbar_no_duplicates_found_in_selection: 'De selectie bevat geen dubbele kaarten',
      statusbar_duplicates_removed_from: 'dubbele kaarten succesvol verwijderd uit',
      statusbar_nothing_to_reset_in: 'Niets te resetten in',
      statusbar_selected_items: 'geselecteerde onderdelen',
      statusbar_reset_success: 'kaarten succesvol gereset in',
      statusbar_reset_all_in: 'Alle kaartenbakken resetten in',
      statusbar_contains_sub_decks: 'bevat onderliggende kaartenbakken (voeg ! toe om te forceren)',
      statusbar_title: 'Commando :',
      statusbar_new_no_write_last_change: 'Niet opgeslagen sinds de laatste wijziging (add ! to overridevoeg ! toe om te forceren)',
      statusbar_saved: 'Opgeslagen',
      statusbar_new_file: '[Nieuw]',
      statusbar_written: 'Weggeschreven',
      statusbar_opened: 'Bestand succesvol ingeladen',
      statusbar_imported: 'Succesvol geïmporteerd',
      statusbar_imported_into: 'kaarten in',
      statusbar_argument_required: 'Argument vereist',
      statusbar_saveas_argument_required: ':saveas <bestandsnaam>',
      statusbar_open_argument_required: ':open <bestandsnaam>',
      statusbar_theme_argument_required: ':thema <bestandsnaam>',
      statusbar_import_argument_required: ':import <filename>',
      statusbar_file_not_found: 'Bestand niet gevonden',
      statusbar_theme_not_found: 'Thema niet gevonden',
      statusbar_theme_hash_error: 'Thema moet een geldige Hash met sleutel-waardeparen retourneren',
      statusbar_yaml_hash_error: 'De YAML-gegevens hebben geen geldige Hash-structuur',
      statusbar_file_removed_or_deleted: 'Bestand is verplaatst of verwijderd',
      statusbar_theme_error: 'Ongeldige themastructuur',
      statusbar_theme_syntax_error: 'syntaxisfout(en) gevonden',
      statusbar_no_filename_known: 'Geen bestandnaam bekend',
      statusbar_save_not_dirty: 'Geen wijzigingen',
      statusbar_unexpected_extension: 'Afwijkende extensie (voeg ! toe om te overschrijven)',
      statusbar_already_exists: 'Bestand bestaat al (voeg ! toe om te overschrijven)',
      statusbar_quit_warning: 'Niet-opgeslagen wijzigingen (voeg ! toe om te forceren)',
      statusbar_save_error: 'Opslagfout',
      statusbar_write_error: 'Schrijffout',
      statusbar_open_error: 'Fout bij openen',
      statusbar_empty_file_error: 'Leeg gegevensbestand (0 bytes)',
      statusbar_import_error: 'Fout bij importeren',
      statusbar_print_error: 'Fout bij afdrukken',
      statusbar_not_a_source_or_deck: 'geen bron of kaartenbak geselecteerd',
      statusbar_no_deck_selected: 'geen kaartenbak geselecteerd',
      statusbar_dir_not_exists: 'map bestaat niet',
      statusbar_import_no_valid_csv: 'Het CSV-bestand is ongeldig of staat niet in de juiste volgorde',
      statusbar_include_header: 'Inclusief koptekst? (y/n)',
      statusbar_export_success: 'Ingepakt',
      statusbar_template_file_error: 'afdruksjabloon genereren mislukt',
      statusbar_printed_from: 'kaarten uit',
      statusbar_exported_decks: 'kaartenbakken',
      statusbar_exported_cards: 'kaarten',
      statusbar_exported_into: 'into',
      statusbar_export_error: 'Fout bij exporteren',
      statusbar_choose_format: 'Kies formaat',
      statusbar_format: '<1> CSV of <2> XML',
      statusbar_deck_not_empty: 'Kaartenbak bevat al kaarten. Toch toevoegen? (y/n)',
      statusbar_table_error: 'Fout in tabel',
      statusbar_deck_empty: 'lege kaartenbak',
      statusbar_save_confirmation: 'Toch opslaan? (y/n)',
      statusbar_beeps_on: 'Pieptonen: aan',
      statusbar_beeps_off: 'Pieptonen: uit',
      statusbar_rotation_indicator_on: 'Rotatie-indicator: aan',
      statusbar_rotation_indicator_off: 'Rotatie-indicator: uit',
      statusbar_replace_with: 'Vervangen door',
      statusbar_unknown_command: 'Onbekend commando',
      statusbar_show_active_corner: 'Actieve hoekstijl',
      statusbar_show_active_theme: 'Actief thema',
      statusbar_show_active_lang: 'Actieve taal',
      statusbar_show_active_marker: 'Actieve markerstijl',
      statusbar_corner_not_available: 'Hoekstijl niet beschikbaar',
      statusbar_theme_not_available: 'Thema niet beschikbaar',
      statusbar_lang_not_available: 'Taal niet beschikbaar',
      statusbar_marker_not_available: 'Markerstijl niet beschikbaar',
      statusbar_corners: 'Hoekstijlen',
      statusbar_available_corners: 'plain, rounded',
      statusbar_languages: 'Languages',
      statusbar_available_languages: 'en, nl',
      statusbar_themes: "Thema's",
      statusbar_available_themes: 'default, cga, julia, crt, amber, borland, tos, dracula, teletext, c64, terminal',
      statusbar_markers: 'Markerstijlen',
      statusbar_available_markers: 'cross, block, plus, asterisk',
      statusbar_corner_succes: 'Vensterhoeken succesvol ingesteld op',
      statusbar_theme_succes: 'Thema succesvol ingesteld op',
      statusbar_lang_succes: 'Taal succesvol ingesteld op Nederlands',
      statusbar_marker_succes: 'Markerstijl succesvol ingesteld op',
      statusbar_no_cards_available: 'geen kaarten beschikbaar',
      statusbar_not_enough_cards_selected: 'er zijn te weinig kaarten geselecteerd',
      table_header_field1: 'Leren',
      table_header_field2: 'Term',
      table_header_field3: 'Context',
      table_header_field4: 'Betekenis',
      table_title_add_card: 'Kaartenbak: toevoegen',
      table_title_edit_card: 'Kaartenbak: bewerken',
      statusbar_modification_eror: 'Wijzigingsfout',
      statusbar_term_meaning_required: 'Term en betekenis zijn vereist',
      statusbar_query_required: 'Zoekopdracht is vereist',
      statusbar_name_required: 'Naam is vereist',
      table_placeholder_term: 'Term',
      table_placeholder_context: 'Context',
      table_placeholder_meaning: 'Betekenis',
      tree_title_rename: 'Bibliotheek: hernoemen',
      statusbar_form_error: 'Formulierfout',
      statusbar_no_name_specified: 'geen naam vermeld',
      hint: '⇥ Tab: Wissel veld, ↵ Enter: OK, Esc: Annuleren',
      statusbar_search_error: 'Fout bij zoeken',
      statusbar_replace_error: 'Fout bij vervangen',
      search_title_table: 'Kaartenbak: zoeken',
      search_title_tree: 'Bibliotheek: zoeken',
      search_and_replace_title_table: 'Kaartenbak: zoeken en vervangen',
      search_and_replace_title_tree: 'Bibliotheek: zoeken en vervangen',
      search_placeholder: 'Zoek…',
      replace_placeholder: 'Vervangen door…',
      search_case_sensitive: 'Hoofdlettergevoelig',
      search_regex: 'Regex',
      search_all: 'Alles',
      statusbar_no_query_specified: 'geen zoekopdracht vermeld',
      statusbar_no_results_found: 'geen resultaten gevonden',
      alert_title: '[!] Waarschuwing',
      alert_config_err_msg: "Fout inladen voorkeuren.\n\nApp starten met standaardwaarden",
      alert_ok: 'Druk op <Enter> om door te gaan',
      alert_cancel_ok: 'Druk op <Enter> om te bevestigen of op <Esc> om te annuleren',
      statusbar_study_session_error: 'Studiesessiefout',
      statusbar_study_memory_limit_reached: 'Het maximaal toegestane aantal kaarten in het memoryspel is',
      statusbar_study_memory_init_msg: 'Zoek de paren die bij elkaar horen',
      statusbar_study_two_of_a_kind_msg: 'Verzamel zo veel mogelijk paren',
      study_status_screen_play_two_of_a_kind_shortcuts: '<Enter> Kaart vragen / kaart afstaan | <Tab> Die kaart heb ik niet',
      statusbar_study_two_of_a_kind_warning: 'Je hebt de kaart—geef die af',
      statusbar_study_two_of_a_kind_user: 'Gebruiker',
      statusbar_study_two_of_a_kind_computer: 'Computer',
      study_status_screen_quiz: 'QUIZ',
      study_status_screen_drill: 'STAMPEN',
      study_status_screen_multiple_choice: 'MEERKEUZE VRAGEN',
      study_status_screen_play_memory: 'MEMORYSPEL',
      study_status_screen_play_two_of_a_kind: 'DUOSPEL',
      study_status_screen_flashcards: 'OVERHOORKAARTEN', # alternatief: LEERKAARTEN
      study_status_screen_start: 'Selecteer een niveau <1–3>',
      study_status_screen_finished: 'Druk op een willekeurige toets om verder te gaan',
      study_status_screen_exercise_completed: 'Oefening voltooid',
      study_status_screen_memory_game_completed: 'Alle paren gevonden',
      study_status_screen_passed: 'Goed gedaan',
      study_status_screen_failed: 'Probeer het later nog eens',
      study_multiple_choice_right: 'Goed',
      study_multiple_choice_wrong: 'Fout',
      study_modus_front: 'VKT',
      study_modus_back: 'AKT',
      study_modus_alternate: 'AFW',
      study_modus_mixed: 'MIX',
      study_quiz_front: 'Voorkant',
      study_quiz_back: 'Achterkant',
      study_question: 'V:',
      study_answer: 'A:',
      study_context: 'Context: ',
      study_context_not_available: 'n.b.',
      study_drill_title: 'Stampen',
      study_quiz_title: 'Overhoren',
      study_multiple_choice_title: 'Meerkeuzevragen',
      study_play_memory_title: 'Speel Memory',
      study_play_two_of_a_kind_title: 'Speel Duo',
      statusbar_difficulty: 'Moeilijkheidsgraad',
      statusbar_levels: '<1> makkelijk <2> gemiddeld <3> moeilijk',
      statusbar_good_luck: 'Veel succes',
      statusbar_test_about_to_begin: 'De test gaat beginnen',
      statusbar_min_req_cards: 'selecteer een kaartenbak met minstens 4 kaarten',
      study_test_passed: 'Test geslaagd',
      study_test_failed: 'Test niet geslaagd',
      study_test_completed_on_time: 'op tijd afgerond',
      study_test_time_up: 'de tijd is om',
      help_main_title: 'Help',
      help_main_screen_title: 'Help: hoofdscherm',
      help_commands_title: "Help: commando's",
      help_library_title: 'Help: bibliotheek',
      help_deck_title: 'Help: kaartenbak',
      help_study_title: 'Help: studeren',
      help_input_fields_title: 'Help: invoervelden',
      mail_subject: '%<app_name>s-supportverzoek',
      about_message: <<~TEXT,
        %<app_name>s

        TUI dashboard studiehulp

        Version %<app_version>s

        Copyright (c) %<app_copyright_year>s Edwin H. Jonkvorst.
        Alle rechten voorbehouden.
      TEXT
      help_main: <<~TEXT,
        1 : Dit help menu
        2 : Hoofdscherm
        3 : Commando's
        4 : Bibliotheek
        5 : Kaartenbak
        6 : Studeren
        7 : Invoervelden
      TEXT
      help_main_screen: <<~TEXT,
        ?       : Help
        :       : Menu
        [       : Bibliotheek
        ]       : Kaartenbak
        Tab     : Volgend paneel
        Backtab : Vorig paneel
        |       : Verticale scheidingslijnen tonen/verbergen
        I       : Rotatie-indicator aan- of uitzetten
        F3      : Schakel de handgeschreven lettervorm in of uit
        C       : Wisselen hoekstijl (rond/recht)
        S       : Wisselen markeersymbool
        T       : Volgend thema
        Shift+T : Vorig thema
      TEXT
      help_commands: <<~TEXT,
        Commando’s kunnen doorgaans worden uitgevoerd met hun volledige naam, de eerste letter of de eerste twee letters.
        Uitzonderingen:
        - search, replace, reset en export worden uitgevoerd met hun volledige naam of de eerste drie letters.
        - Studiesessies en 'print the current working directory' kunnen alleen worden gestart met de verkorte aanduidingen.
        - Samengestelde commando’s kunnen worden afgekort tot hun beginletters (bijv. an voor add-node).
        Bij meervoudsvormen voeg je een -s toe.

        :?                  : Toon help
        :reset              : Reset geselecteerde kaartenbak
        :dedup              : Dubbele kaarten verwijderen
        :beeps              : Zet pieptonen aan/uit
        :rotation-indicator : Zet rotatie-indicator aan/uit
        :langs              : Toon beschikbare talen
        :lang [language]    : Taal instellen
        :corners            : Toon beschikbare hoekstijlen
        :corner [corner]    : Hoekstijl instellen
        :markers            : Toon beschikbare markeringstekens
        :marker [marker]    : Markeringsteken instellen
        :themes             : Toon beschikbare thema's
        :theme [theme]      : Thema instellen
        :search             : Zoeken
        :replace            : Vervangen
        :add-node           : Item aan de bibliotheek toevoegen
        :rename-node        : Item in de bibliotheek hernoemen
        :delete-nodes       : Items(s) uit de bibliotheek verwijderen
        :add-card           : Kaart aan een kaartenbak toevoegen
        :edit-card          : Kaart in een kaartenbak bewerken
        :delete-cards       : Kaart(en) uit een kaartenbak verwijderen
        :dr                 : Stampen
        :qz                 : Overhoren
        :mc                 : Meerkeuzevragen
        :pm                 : Speel Memory
        :tk                 : Speel Duo
        :lct                : Aangepast thema laden
        :pwd                : Print de huidige werkmap
        :new                : Nieuwe bibliotheek
        :o <filename>       : Bestand inladen
        :w [filename]       : Opslaan, eventueel naar een nieuwe bestandsnaam
        :wq                 : Opslaan en afsluiten
        :saveas <filename>  : Opslaan als bestandsnaam en deze gebruiken als huidige bestandsnaam
        :import <filename>  : CSV-bestand importeren
        :export             : Bestanden exporteren naar CSV- of XML-formaat
        :print              : Kaartenbak afdrukken
        :q                  : Afsluiten
        :q!                 : Forceer afsluiten zonder opslaan
      TEXT
      help_library: <<~TEXT,
        H, {, ←                         : Inklappen
        L, }, →                         : Uitklappen
        Control+P, K, ↑                 : Rij omhoog
        Control+N, J, ↓                 : Rij omlaag
        G, Home                         : Spring naar het begin
        Shift+G, End                    : Spring naar het einde
        Control+U, PageUp               : Pagina omhoog
        Control+D, PageDown             : Pagina omlaag
        Option+N, Option+P,
           Shift+J, Shift+K,
           Shift+↓, Shift+↑,
           Control+Shift+A
           Shift+M, Option+Space,
           Shift+Home, Shift+End,
           Shift+PageUp, Shift+PageDown : Markeer onderdelen voor bulk verwijdering
        Option+Enter, A, +, F7          : Onderdeel toevoegen
        Enter, Shift+R, F2              : Onderdeel hernoemen
        Backspace, -, F8                : Onderde(e)l(en) verwijderen
        /, Control+F, F                 : Zoeken
        \\, Control+H, Shift+F           : Zoeken en vervangen
        N, Control+N, J, ↓              : Zoek volgende
        Shift+N, Control+P, J, ↑        : Zoek vorige
        Control+Z                       : Herstel
        Control+Y, Shift+Control+Z      : Herstel ongedaan maken
        M                               : Wissel modus
        D                               : Dubbele kaarten uit geselecteerde kaartenbak(ken) verwijderen
        R                               : Geselecteerde kaartenbak(ken) resetten
        ⌥1 ⌥2 ⌥3 ⌥4                     : Start een studiesessie met de geselecteerde kaartenbak
      TEXT
      help_deck: <<~TEXT,
        Control+P, K, ↑                 : Rij omhoog
        Control+N, J, ↓                 : Rij omlaag
        G, Home                         : Spring naar het begin
        Shift+G, End                    : Spring naar het einde
        Control+U, PageUp               : Pagina omhoog
        Control+D, PageDown             : Pagina omlaag
        Option+N, Option+P,
           Shift+J, Shift+K,
           Shift+↓, Shift+↑,
           Control+Shift+A
           Shift+M, Option+Space,
           Shift+Home, Shift+End,
           Shift+PageUp, Shift+PageDown : Markeer kaarten voor bulk verwijdering
        Space                           : Kaart(en) (de)selecteren
        Option+Enter, A, +, F7          : Kaart toevoegen
        Enter, E, F2                    : Kaart wijzigen
        Backspace, -, F8                : Kaart(en) verwijderen
        /, Control+F, F                 : Zoeken
        \\, Control+H, Shift+F           : Zoeken en vervangen
        N, Control+N, J, ↓              : Zoek volgende
        Shift+N, Control+P, K, ↑        : Zoek vorige
        Control+Z                       : Herstel
        Control+Y, Control+Shift+Z      : Herstel ongedaan maken
        1 2 3 4                         : Kolom sorteren
        M                               : Wissel modus
        D                               : Dubbele kaarten uit geselecteerde kaartenbak(ken) verwijderen
        R                               : Geselecteerde kaartenbak(ken) resetten
        ⌥1 ⌥2 ⌥3 ⌥4                     : Start een studiesessie
      TEXT
      help_study: <<~TEXT,
        D = Stampen
        Q = Overhoren
        MC = Meerkeuzevragen
        PM = Speel Memory
        TK = Speel Duo

        Een studiesessie is voltooid als alle kaarten:
        - uit het hoofd zijn geleerd, zonder tijdsdruk (S);
        - zijn getest binnen de tijd (S & O);
        - als paar zijn gekoppeld in het Memory of Duo spel (MC, TK).

        Opmerking: De J- en K-toetsen worden in PM gebruikt om codes in te voeren.

        Control+P, K, ↑                : Rij omhoog (S, PM, TK)
        Control+N, J, ↓                : Rij omlaag (S, PM, TK)
        G, Home                        : Spring naar het begin (S, PM, TK)
        Shift+G, End                   : Spring naar het einde (S, PM, TK)
        Control+U, PageUp              : Pagina omhoog (S, PM, TK)
        Control+D, PageDown            : Pagina omlaag (S, PM, TK)
        F4                             : Zet context tonen aan/uit (S, O, MK & SM, TK)
        F5                             : Pauzeren (S, O, MK & SM, TK)
        S                              : Wissel seconden timer (D)
        T                              : Zet timer aan/uit (D)
        Space, Enter                   : Toon antwoord (S, O) / volgende kaart (O)
        1 2 3 4                        : Antwoord (MK)
        Tab                            : Kaart uitsluiten van toekomstige oefeningen (S, O & MK) & toon volgende kaart (O & MK) | Die kaart heb ik niet (TK)
        F2                             : Kaart bewerken (S, O, MK & SM) | Kaart vragen / kaart afstaan (TK)
      TEXT
      help_input_fields: <<~TEXT
        === BEWERKEN ===
           Control+X                  : Knip de geselecteerde tekst en kopieer deze naar het systeemklembord.
           Control+Y, Control+Shift+Z : Opnieuw uitvoeren (Control+Shift+Z werkt niet in alle terminals).
           Control+Z                  : Ongedaan maken.
           Control+T                  : Verwissel het teken vóór de invoegpositie met het teken erna.

        === NAVIGATIE ===
           Control+F, →           : Verplaats de invoegpositie één teken naar rechts.
           Control+B, ←           : Verplaats de invoegpositie één teken naar links.
           Fn+↑, Fn+←,
              Option+↑, Control+A : Verplaats de invoegpositie naar het begin van de regel.
           Fn+↓, Fn+→,
              Option+↓, Control+E : Verplaats de invoegpositie naar het einde van de regel.
           Option+←               : Verplaats de invoegpositie naar het begin van het vorige woord.
           Option+→               : Verplaats de invoegpositie naar het einde van het volgende woord.
           Control+L              : Plaats de invoegpositie in het midden van de tekst.
           Tab, Control+P         : Ga naar het volgende invoerveld.
           Backtab, Control+N     : Ga naar het vorige invoerveld.

        === TEKST VERWIJDEREN ===
           Control+W, Option+Backspace : Verwijder het woord links van de invoegpositie.
           Fn+Option+Backspace         : Verwijder het woord rechts van de invoegpositie.
           Control+H, Backspace        : Verwijder het teken links van de invoegpositie.
           Control+D, Fn+Backspace     : Verwijder het teken rechts van de invoegpositie.
           Control+K                   : Verwijder de tekst vanaf de invoegpositie tot het einde van de regel.
           Control+U                   : Verwijder de tekst vanaf de invoegpositie tot het begin van de regel.

        === TEKST SELECTEREN ===
           Control+A, Control+Shift+A : Selecteer alle tekst.
           Control+Shift+F, Shift+→   : Breid de selectie één teken naar rechts uit.
           Control+Shift+B, Shift+←   : Breid de selectie één teken naar links uit.
           Option+Shift+←             : Breid de selectie uit tot het begin van het huidige woord. Druk opnieuw om uit te breiden tot het begin van het volgende woord.
           Option+Shift+→             : Breid de selectie uit tot het einde van het huidige woord. Druk opnieuw om uit te breiden tot het einde van het volgende woord.
           Shift+↑, Fn+Shift+↑,
              Option+Shift+↑          : Breid de selectie uit tot het begin van de regel.
           Shift+↓, Fn+Shift+↓,
              Option+Shift+↓          : Breid de selectie uit tot het einde van de regel.
              Control+Shift+L         : Breid de tekstselectie uit tot het midden van de tekst.
      TEXT
    }
  }.freeze
end
