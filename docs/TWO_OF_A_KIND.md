# Game Guide: Two of a Kind (Go Fish / Pair Matching Variant)

This game is a variant of **Go Fish** or **Pairs/Matching**, played using study cards against a computer opponent. The objective is to collect as many matching pairs as possible.

## 1. Setup & Initialization

* **Minimum Cards Required:** The game requires at least **4 original study cards** to start.

* **Duplicating Cards:** Each study card is duplicated so that **two identical copies** share the same `id`.

* **Deck & Initial Hands:**

  * All cards are shuffled together to form the main draw deck (`@two_of_a_kind_deck`).

  * Both the player and the computer start with **1 card** in their hand.

  * If a matching pair happens to be dealt directly into a player's hand during setup, it is automatically removed and awarded as a point.

## 2. Gameplay & Turns

The game is played in alternating turns. The human player (`:user`) goes first.

### A. The Player's Turn

1. **Select a Card:** Use the navigation keys to browse through your hand and select a card.

2. **Ask the Computer (`Enter`):** Ask the computer if it holds the matching card (the card with the exact same `id`).

3. **Outcome:**

   * **MATCH (Computer has the card):**

     * The matching pair is removed from both hands.

     * You earn **1 point** (`@user_score += 1`).

     * You **keep your turn** and may ask for another card.

   * **NO MATCH (Computer does not have the card):**

     * You **draw a card** from the deck.

     * If the drawn card creates a pair with a card already in your hand, the pair is automatically collected for a point.

     * Turn passes to the **computer**.

### B. The Computer's Turn

1. **Computer Asks:** The computer randomly selects a card from its own hand (`chosen_card`) and asks if you have it.

2. **Player Responds:**

   * **Hand Over Card (`Enter`):** If you have the requested card selected and press `Enter`:

     * The pair is removed from both hands.

     * The computer earns **1 point** (`@computer_score += 1`).

     * The computer **keeps its turn** and will ask another question.

   * **"I Don't Have It" (`Tab`):**

     * Press `Tab` to declare that you do not hold the requested card.

     * **Honesty Check:** The system verifies your hand. If you actually *do* have the requested card, the game rejects the action and displays a warning.

     * If you legitimately do not have the card, the computer draws a card from the deck and turn passes back to the **player**.

## 3. Special Rules & Mechanics

* **Empty Hand Refill:**
  If a player runs out of cards after matching a pair, a refill request is queued (`queue_two_of_a_kind_empty_hand`) to draw a new card from the deck.

* **Automatic Pair Collection:**
  Whenever two matching cards end up in the same hand (via drawing or acquiring), they are instantly recognized, removed, and converted into a score point.

* **Header Indicators:**

  * `⧉` displays the current score.

  * `🂠` displays the number of cards in hand.

  * `(⇄)` indicates that the last pair was gained by asking the opponent.

  * `(↓)` indicates that the last pair was gained by drawing from the deck.

## 4. Key Bindings & Controls

| Key | Action |
| --- | --- |
| **Up Arrow / `k` / `p`** | Select previous card in hand |
| **Down Arrow / `j` / `n`** | Select next card in hand |
| **`Home` / `g`** | Jump to first card in hand |
| **`End` / `G`** | Jump to last card in hand |
| **`Page Up` / `Ctrl+u`** | Scroll page up |
| **`Page Down` / `Ctrl+d`** | Scroll page down |
| **`Enter` / `Return`** | Ask for selected card / Confirm answer |
| **`Tab`** | Declare that you **do not** have the requested card |
| **`F4`** | Toggle context/hint display for the selected card |
| **`E` / `F2`** | Edit selected card (pauses game and opens editor) |
| **`F3`** | Toggle handwritten font style |
| **`F5`** | Pause / Resume test timer |

## 5. Game Over Conditions

The game ends when **all** of the following conditions are met:

1. The draw deck (`@two_of_a_kind_deck`) is **empty**, **AND**

2. The player's hand (`@user_hand`) is **empty**, **AND**

3. The computer's hand (`@computer_hand`) is **empty**.

The player with the highest score wins!
