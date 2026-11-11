# Game Guide: Memory Game (Concentration)

This view implements a Terminal User Interface (TUI) version of the classic **Memory** (or Concentration) matching game, designed for reviewing study cards.

---

## 1. Overview & Setup

* **Initialization:** When entering the `:memory` study mode, the game initializes cards (`initialize_memory_game`) using the current study deck (`@cards_to_test` or `active_cards`).
* **Card Display:** Each card is represented in a grid as a small rectangular button containing a unique coordinate code (e.g., `A1`, `B2`).

---

## 2. Layout & UI Structure

The UI is divided vertically into three main regions:

```
+-------------------------------------------------------------+
| Header Bar (Title / Instructions OR Card Details Split View)|  <- Header
+-------------------------------------------------------------+
|                                                             |
|  [ A1 ]  [ A2 ]  [ A3 ]  [ A4 ]                             |  <- Memory Cards
|  [ B1 ]  [ B2 ]  [ B3 ]  [ B4 ]                             |
|                                                             |
+-------------------------------------------------------------+
| Context Panel (Displays example context / notes for card)   |  <- Context Panel
+-------------------------------------------------------------+
```

### A. Dynamic Header Bar
1. **Initial State:** Displays a centered message (e.g., `"Memory Game Started!"`).
2. **Active Card State:** When cards are selected/flipped:
   * **Left Header:** Displays information for the **first flipped card** (`@memory_first_flipped_idx`).
   * **Right Header:** Displays information for the **second flipped card** (`@memory_second_flipped_idx`).
   * **Mismatched Feedback:** If the two flipped cards do not match, the text in the right header is shown as **crossed out**.

### B. Cards Grid & Responsiveness
* Cards are dynamic blocks rendered according to window width:
  * Width: `4` characters.
  * Height: `3` lines.
  * Horizontal spacing: `1` character.
* **Responsive Layout:** `cards_per_row` is automatically calculated based on available terminal width.
* **Scrollbar:** When the grid height exceeds the visible window area, a vertical scrollbar is rendered on the far right.

### C. Context Panel (Optional)
* Enabled when `@test_show_context` is true.
* Renders at the bottom separated by a horizontal divider line.
* Displays the `context` string of the currently active/flipped card. Supports Right-to-Left (RTL) text rendering and italic styling for handwritten fonts.

---

## 3. Card Visual States & Styling

Cards change appearance depending on their state:

| Card State | Border / Box Style | Text Visual Style |
| :--- | :--- | :--- |
| **Unselected / Face Down** | Dimmed border | Dimmed coordinate text (e.g., `A1`) |
| **First Pick (`first_flipped`)** | Highlighted border | Standard main text color |
| **Second Pick (`second_flipped`)** | Highlighted border | Crossed-out text style |
| **Matched Pair (`matched`)** | Standard border | Highlighted main text color (removed or revealed) |

---

## 4. Game Completion State

The game ends when all cards are cleared or `@test_finished_waiting` becomes true:
1. The card grid disappears.
2. A completion status screen is rendered with a checkmark and summary messages indicating that the memory session is finished.
