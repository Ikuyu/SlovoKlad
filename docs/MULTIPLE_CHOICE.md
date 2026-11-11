# Game & UI Guide: Multiple Choice Mode

**Multiple Choice Mode** tests the user's knowledge by displaying a prompt (Term or Meaning) along with a list of numbered options. The user must select the correct answer from the choices provided.

## 1. Overview & Core Mechanics

* **Prompt & Options:** Displays the question text (Term or Meaning based on test direction) and a list of options (`@test_mc_options`).
* **Answer Validation:**
  * Before answering, options are prefixed with numbers (e.g., `[1]`, `[2]`).
  * After answering (`@test_mc_answered == true`), visual feedback is provided:
    * **Correct Choice:** Marked with `[]`.
    * **Incorrect Choice:** Marked with `[]` and rendered with a `crossed_out` (strikethrough) and dimmed style.
    * **Revealed Correct Answer:** If the user chose incorrectly, the correct option is also highlighted with `[]`.

## 2. Layout & Interface Structure

The UI is rendered as a clean card within a Terminal User Interface (TUI):

```
+-------------------------------------------------------------+
| [Right]                                             [Wrong] | <- Tab Header
+-------------------------------------------------------------+
|                                                             |
|  Question                                                   | <- Left Label & Header
|                                                             |
|  [ Question / Prompt Text ]                                 | <- Question Area
|                                                             |
|  [1] Option A                                               | <- Options Area
|  [2] Option B                                               |
|  [3] Option C                                               |
|                                                             |
|  Context: [ Example sentence or N/A ]                       | <- Context Panel
+-------------------------------------------------------------+
```

### A. Dynamic Tab Headers

* Top tabs reflect the result after an answer is submitted:
  * **`[Right]` Tab:** Highlighted if the selected option matches `@test_mc_correct_answer`.
  * **`[Wrong]` Tab:** Highlighted if the selected option was incorrect.

### B. Vertical Accent Margin (`â–`)

* A vertical line is drawn along the left side of the prompt and options to frame the card UI cleanly.

### C. Options Rendering

* Options are displayed line-by-line starting below the question.
* Supports **BiDirectional (RTL/LTR)** text via FriBidi integration.
* Automatically truncates long option text with an ellipsis (`…`).
* Applies *italic* styling when handwritten font mode is active for non-Latin characters.

### D. Optional Context Panel

* When `@test_show_context` is enabled, an additional line displays context notes or hints at the bottom of the card (`Context: <value>`).

## 3. Game & Test States

1. **Difficulty Selection Screen (`@test_awaiting_difficulty`):**
   * Displays an introductory status screen with a timer icon showing the total number of flashcards in the set.
2. **Active Multiple Choice Screen:**
   * Interactive testing view showing the current prompt, numbered options, and immediate feedback upon selection.
3. **Completion Status Screens:**
   * **Passed / Completed:** Displays a green checkmark when all cards are completed or `@test_finished_waiting == true`.
   * **Time Expired:** Displays a failure icon if `@test_time_was_up_notified == true`.
