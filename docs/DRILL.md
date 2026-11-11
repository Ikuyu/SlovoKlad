# Game & UI Guide: Drill Mode

**Drill Mode** is a study mode in which vocabulary/flashcard items are presented in a structured table layout with **Term** and **Meaning** columns. The learner navigates row by row to view the prompt and reveal answers to test their knowledge.

## 1. Core Overview & Mechanics

* **Study Deck:** Uses a list of target flashcards (`@cards_to_test`).
* **Prompt & Answer Direction:** Depending on the selected study strategy, either the **Term** or the **Meaning** acts as the prompt question. The corresponding answer is hidden until revealed on the active row (when `@test_show_meaning` is enabled).
* **Cursor & Active Row Selection:** The currently highlighted card uses a dedicated cursor style (`style_cursor`) to clearly indicate selection.

## 2. Interface Structure & Layout

The UI is rendered as a clean Terminal User Interface (TUI) table with the following layout:

```
+---------------------------------------------------------------+
| [Term]                          |                   [Meaning] |  <- Header
+---------------------------------------------------------------+
|          Prompt (Right aligned) | (Hidden / Revealed)         |  <- Card Rows
|         >>>> Active Row (Highlighted with cursor) <<<<        |
|                                 |                             |
+---------------------------------------------------------------+
| Context: (Optional bottom context panel)                      |  <- Context Panel
+---------------------------------------------------------------+
```

### A. Table Header

* Displays column headers **`[Term]`** on the left and **`[Meaning]`** on the right.
* A horizontal line with optional column dividers separates the header from the content rows.

### B. Dynamic Prompt Strategy

The contents of the left and right cells depend on the configured **study strategy** (`settings.study_strategy`):

1. **`fronts_random` (Default):** The *Term* is on the left (prompt), *Meaning* is on the right (answer).
2. **`backs_random`:** The *Meaning* is on the right (prompt), *Term* is on the left (answer).
3. **`alternately_fronts_and_backs_random`:** Prompts alternate between front and back on even/odd rows.
4. **`everything_random`:** Swaps direction dynamically based on card ID.

> **Note:** The hidden answer cell is only displayed for the active cursor row when the user reveals it (`@test_show_meaning == true`).

### C. Automatic Viewport & Scrolling

* Calculates the maximum visible rows (`max_visible_rows`) dynamically based on terminal height.
* The viewport (`@test_drill_scroll_y`) scrolls automatically as the user moves up or down so the active card always remains visible.
* A dynamic scrollbar appears on the right edge whenever total cards exceed the visible height.

## 3. Special Visual & Localization Features

* **Bottom Context Panel (`@test_show_context`):**
  When enabled, an extra bottom panel renders context notes, example sentences, or hints for the highlighted card.
* **Right-to-Left (RTL) & Unicode Truncation:**
  Includes full support for RTL languages (e.g., Arabic, Hebrew) via FriBidi calculations, automatically adding truncation ellipsis (`…`) when text exceeds column bounds.
* **Handwritten Font Styling:**
  Applies italic modifiers automatically to non-Latin characters when a handwritten font style is active.

## 4. Completion State

When all cards in the drill set are finished or `@test_finished_waiting == true`:

1. The table view is replaced by a **Completion Status Screen**.
2. A prominent checkmark is rendered alongside completion messages confirming the drill exercise is finished.
