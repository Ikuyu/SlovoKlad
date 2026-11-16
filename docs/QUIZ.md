# Game & UI Guide: Quiz Mode

**Quiz Mode** provides a flashcard-style self-testing view. It presents study cards one at a time, allowing the learner to view a prompt (Question), reveal the answer, and evaluate their memory or difficulty level.

## 1. Overview & Core Mechanics

* **Flashcard Testing:** The quiz progresses through `@cards_to_test` card by card using `@test_current_idx`.
* **Question vs. Answer State:** 
  * When `@test_show_meaning` is `false`, the screen shows the **Question** prompt.
  * When `@test_show_meaning` is `true`, the screen reveals the **Answer**.
* **Card Side Support:** Supports testing in both directions based on `@test_card_directions`.

## 2. Interface Layout & Navigation Structure

The Quiz interface is rendered as a clean card widget within a Terminal User Interface (TUI):

```
+-------------------------------------------------------------+
| [Front]                                              [Back] | <- Tab Header
+-------------------------------------------------------------+
|                                                             |
|  ▍ Question:                                                | <- Header & Margin Line
|  ▍                                                          |
|  ▍ [ Prompt or Revealed Answer Text ]                       | <- Card Content
|  ▍                                                          |
|  ▍ Context: [ Sentence / Hint / N/A ]                       | <- Context Panel
+-------------------------------------------------------------+
```

### A. Top Navigation Tabs

* **`[Front]` Tab:** Highlighted when displaying the front/prompt side of the current flashcard.
* **`[Back]` Tab:** Highlighted when displaying the back/answer side of the current flashcard.
* The active tab toggles dynamically depending on card orientation and whether the answer is currently revealed (`@test_show_meaning`).

### B. Card Body & Visual Elements

* **Margin Indicator (`▍`):** A vertical accent bar is drawn along the left border of the active flashcard card area.
* **Header Label:** Displays either **Question** or **Answer** depending on the study state.
* **Main Content Area:** 
  * Displays the text (term or meaning) formatted centrally within the card box.
  * Font color switches between `:studysessions_answer` (Question state) and `:foreground` (Answer state).
  * Automatically handles BiDirectional (BiDi/RTL) text rendering with FriBidi and adds truncation ellipsis (`…`) if necessary.
  * Applies *italic* style if handwritten font mode is active for non-Latin script.

### C. Context Panel

* Shown when `@test_show_context` is `true`.
* Appears below the main card content as `Context: <value>`.
* Displays either the card's context/example sentence or a localized `"Not Available"` string if blank.

## 3. Game & Test States

The Quiz renderer handles three distinct operational states:

1. **Awaiting Difficulty Rating (`@test_awaiting_difficulty`):**
   * Displays an intermediate start/pause screen with a timer icon showing the number of remaining flashcards before prompting for input.
2. **Standard Active Testing:**
   * Interactive flashcard layout displaying prompts, answers, and context hints.
3. **Completion / Status Screen:**
   * **Passed / Completed:** Renders a green checkmark when all flashcards have been successfully reviewed or `@test_finished_waiting == true`.
   * **Time Expired:** Renders a failure icon if `@test_time_was_up_notified == true`.
