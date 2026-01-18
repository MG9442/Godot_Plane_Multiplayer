# Frequent Fighters - Progression System Implementation Spec

## Project Overview
Frequent Fighters is a multiplayer plane combat game built in Godot. This spec covers the implementation of a round-based progression system with ability selection mechanics.

## Current Game State (Already Implemented)
- Multiplayer networking functional
- Player plane sprite selection
- Main combat scene with flying and shooting (spacebar)
- Health system (3 HP per player)
- Kill tracking with star display under sprites
- Kill attribution (only final blow counts)
- Respawn system (1 second timer, and invincible during respawn)

## New Features to Implement

### 1. Pre-Game Lobby/Menu Enhancements
**Location:** Same screen where players choose plane sprites

**New UI Elements:**
- Game mode selector (default: "Free-for-All")
- Round timer input (in minutes) - determines duration of each combat round
- Number of rounds input (default: "5 rounds") - determines how many rounds total in a match

**Requirements:**
- These settings should be host-controlled (multiplayer host sets them)
- Settings must sync to all connected players
- Default values if not set: FFA mode, 1 min per round, 5 rounds

---

### 2. Round Timer System

**Core Functionality:**
- Display countdown timer during combat rounds
- Timer starts when round begins
- When timer reaches 0, round ends immediately (no grace period)
- Timer should be visible to all players (UI element)
- Respawn system polishing (Remove player ability to shoot during 1 second respawn timer)

**Technical Notes:**
- Timer needs to be synchronized across all clients in multiplayer
- Use Godot's networking to ensure consistency
- Pause timer during ability selection screens

---

### 3. Round Win Determination

**Rules:**
- Round winner = player(s) with highest kill count during that specific round
- Multiple players can win a round (tie in kills)
- If ALL players have 0 kills, NO ONE is considered a winner
- Track round wins separately from total kills

**Data Structure Needed:**
```gdscript
# Per player tracking
var round_wins = 0  # Number of rounds this player has won
var rounds_participated = []  # Which rounds they won
var current_round_kills = 0  # Kills in current round (resets each round)
var total_kills = 0  # Cumulative kills across all rounds
```

**Important:**
- Reset `current_round_kills` to 0 at the start of each new round
- Track `round_wins` separately for overall game winner determination
- Store which players won each round for tiebreaker logic

---

### 4. Ability Selection Screen

**Trigger Conditions:**
- After each normal round (rounds 1 through N-2)
- Before the final round (round N-1), ALL players choose from OVERPOWERED abilities
- After final round, skip ability selection (proceed to tiebreaker logic if needed)
- NO ability selection during tiebreaker rounds

**Screen Elements:**
- 30 second countdown timer
- Display three random abilities from given tier which each player picks from
- Once an ability is chosen by a player, it will not appear in that player's subsequent selections (except for stackable abilities)
- Horizontal list of available abilities with descriptions
- Visual feedback when ability is selected
- "Locked in" indicator when player confirms choice

**Selection Logic:**
```
IF current_round < (final_round - 1):
    IF player won the round (or tied for most kills):
        Display RARE abilities
    ELSE:
        Display BASIC abilities

IF current_round == (final_round - 1):
    ALL players display OVERPOWERED abilities (before final round starts)

IF current_round == final_round:
    NO ability selection (skip this screen, proceed to winner check)

IF in_tiebreaker_round:
    NO ability selection (skip this screen entirely)
```

**Timeout Behavior:**
- If player doesn't select within 30 seconds, randomly assign an ability from the given choices
- Show "Auto-selected" indicator for players who timed out

**Multiplayer Sync:**
- All players must complete selection before proceeding
- Show waiting status for players who've already selected
- Proceed when all selections made OR after 30 second timer expires

---

### 5. Ability System

### 5.1 Ability Tiers and Definitions

**BASIC ABILITIES** (Non-round-winners):
| Ability | Effect | Weight | Conflicts With |
|---------|--------|--------|----------------|
| +1 Max Health | Increases max HP by 1 | 1.0 | None (stackable) |
| +2 Bullet Container | Increases max active bullets by 2 | 1.0 | None (stackable) |
| Faster Bullet Speed | Increases projectile velocity by 25% | 1.0 | None (stackable) |
| Basic Shield | Absorbs 1 hit before breaking | 1.0 | None (stackable) |
| Faster Movement | Increases plane speed by 20% | 1.0 | None (stackable) |
| V-Shape Shot Pattern | Fires 3 bullets in V formation | 0.5 | All other shot patterns |

**RARE ABILITIES** (Round winners):
| Ability | Effect | Weight | Conflicts With |
|---------|--------|--------|----------------|
| +2 Max Health | Increases max HP by 2 | 1.0 | None (stackable) |
| Rapid Fire | Decreases fire cooldown by 40% | 1.0 | None (stackable) |
| Regen Health | Restores 1 HP every 5 seconds | 1.0 | Regen Shield |
| Regen Shield | Shield regenerates 10 seconds after breaking | 1.0 | Regen Health |
| Blink/Dash Movement | Press 'Q' to dash short distance (3 sec cooldown) | 1.0 | Invisibility Movement |
| Front-Back Shot | Fires bullets forward AND backward | 0.5 | All other shot patterns |

**OVERPOWERED ABILITIES** (Final round for all players):
| Ability | Effect | Weight | Conflicts With |
|---------|--------|--------|----------------|
| +3 Max Health | Increases max HP by 3 | 1.0 | None (stackable) |
| Homing Missiles | Bullets track nearest enemy | 1.0 | All other shot patterns |
| Star Shape Shot | Fires 5 bullets in star pattern | 1.0 | All other shot patterns |
| Super Rapid Fire | Decreases fire cooldown by 70% | 1.0 | None (stackable) |
| Invincibility Shield | Absorbs 3 hits before breaking | 1.0 | None (stackable) |
| Invisibility Movement | Press 'Q' to become invisible; cannot shoot while invisible | 1.0 | Blink/Dash Movement |

### 5.2 Ability Conflict Resolution

**Conflict Categories:**
1. **Shot Patterns** - Mutually exclusive
   - V-Shape, Front-Back, Homing Missiles, Star Shape
   - When new pattern selected, remove old pattern

2. **Regen Types** - Mutually exclusive
   - Regen Health, Regen Shield
   - When new regen selected, remove old regen

3. **Movement Abilities** - Mutually exclusive
   - Blink/Dash, Invisibility
   - When new movement selected, remove old movement

**Implementation Logic:**
```gdscript
func apply_ability(new_ability):
    # Check for conflicts
    var conflict_category = get_conflict_category(new_ability)
    
    if conflict_category != null:
        # Remove existing ability in same category
        remove_abilities_in_category(conflict_category)
    
    # Add new ability
    active_abilities.append(new_ability)
    apply_ability_effects(new_ability)
```

### 5.3 Ability Persistence
- Abilities carry through ALL rounds in a match
- Abilities stack unless they conflict
- Reset ALL abilities when new game/match starts
- Abilities persist through death/respawn within same match

### 5.4 Random Selection Weighting
```gdscript
# Example weighted random selection
func get_weighted_random_ability(tier_abilities):
    var total_weight = 0
    for ability in tier_abilities:
        total_weight += ability.weight
    
    var rand_value = randf() * total_weight
    var cumulative = 0
    
    for ability in tier_abilities:
        cumulative += ability.weight
        if rand_value <= cumulative:
            return ability
```

---

### 6. Overall Game Winner Determination

**Primary Win Condition:**
- Player with most round wins at end of all rounds
- Example: 5 rounds total, Player A wins 3 rounds → Player A is overall winner

**Tiebreaker System:**

#### First Tiebreaker Round
- **Participants:** Only players tied for most round wins
- **Abilities:** Players keep their current loadout (no new selection)
- **Winner:** Player(s) with highest kills in tiebreaker round

#### Subsequent Tiebreakers (if still tied)
- **Elimination Logic:** Only players who TIED in previous tiebreaker continue
  
**Example Scenario:**
```
Initial Tie: Players 1, 2, 3 (all have 2 round wins)

Tiebreaker Round 1:
- Player 1: 10 kills
- Player 2: 8 kills  
- Player 3: 10 kills

Result: Player 2 ELIMINATED (didn't tie for most kills)

Tiebreaker Round 2:
- Player 1: 5 kills
- Player 3: 5 kills

Result: Still tied, continue

Tiebreaker Round 3:
- Player 1: 7 kills
- Player 3: 4 kills

Result: Player 1 WINS (finally broke tie)
```

**Technical Requirements:**
- Track which players are "in tiebreaker"
- After each tiebreaker, recalculate who remains tied
- Continue until single winner emerges
- No ability selection during ANY tiebreaker rounds

---

### 7. Game Flow State Machine

```
START_GAME
    ↓
LOBBY (choose planes, set rules)
    ↓
ROUND_1_START
    ↓
ROUND_1_COMBAT (timer running)
    ↓
ROUND_1_END (determine round winners)
    ↓
ABILITY_SELECTION (30 sec, tier based on round performance)
    ↓
ROUND_2_START
    ↓
... (repeat for rounds 2 through N-2)
    ↓
ABILITY_SELECTION (ALL players choose OVERPOWERED abilities before final round)
    ↓
FINAL_ROUND_START
    ↓
FINAL_ROUND_COMBAT
    ↓
FINAL_ROUND_END
    ↓
CHECK_WINNER
    ↓
IF TIED:
    ↓
    TIEBREAKER_ROUND (no ability selection, subset of players)
    ↓
    CHECK_TIEBREAKER_WINNER
    ↓
    IF STILL_TIED: TIEBREAKER_ROUND (repeat)
    ↓
VICTORY_SCREEN (show overall winner)
```

---

### 8. UI/UX Requirements

**During Combat:**
- Round timer (large, visible countdown)
- Current round number (e.g., "Round 2/5")
- Player health bars
- Player kill counts (current round)
- Player round wins (overall)
- Active abilities icons/indicators

**Ability Selection Screen:**
- Timer (30 seconds)
- Player's tier ("You won! Choose from RARE abilities" or "Choose from BASIC abilities")
- Grid of available abilities with:
  - Icon
  - Name
  - Description
  - Visual highlight on hover
- "Locked In" status
- Other players' selection status (waiting/ready)

**Victory Screen:**
- Winner announcement
- Final statistics:
  - Round wins per player
  - Total kills per player
  - MVPs (most kills in a single round, etc.)

---

### 9. Multiplayer Synchronization Points

**Critical Sync Points:**
1. Round timer synchronization (server authoritative)
2. Kill counting and attribution
3. Round win determination (server decides)
4. Ability selection (all clients must confirm before proceeding)
5. Tiebreaker participant list
6. Ability effects (server validates, clients display)

**Server Authority:**
- Server determines round winners
- Server tracks round wins
- Server manages tiebreaker logic
- Server enforces ability conflicts

**Client Responsibilities:**
- Display UI based on server state
- Send ability selections to server
- Render ability effects locally
- Display synchronized timers

---

### 10. Edge Cases to Handle

1. **Player disconnects during ability selection**
   - Auto-select random ability for them
   - Continue when remaining players ready OR timer expires

2. **Player disconnects during combat**
   - Their settings (kills/rounds wins/abilities/sprite) persist until new match
   - They're excluded from future tiebreakers if they don't reconnect

3. **All players have 0 kills**
   - No round winner declared
   - All players choose from BASIC abilities next round

4. **Player rejoins mid-match**
   - Can join ongoing match
   - Must spectate until next round
   - Their settings (kills/rounds wins/abilities/sprite) persist on rejoin for existing match

5. **Tiebreaker with 2+ players, multiple tie again**
   - Could result in subset (example showed 3→2→2 elimination)
   - System handles any number of tied players

6. **Rapid fire + Super Rapid Fire stacking**
   - Both are stackable, so fire rate compounds
   - Should work as intended (very fast shooting)

---

### 11. Testing Checklist

**Round System:**
- [ ] Timer counts down correctly
- [ ] Timer synced across clients
- [ ] Round ends exactly at 0
- [ ] Round wins tracked correctly
- [ ] Multiple round winners handled

**Ability Selection:**
- [ ] Correct tier shown based on performance
- [ ] 30 second timer works
- [ ] Auto-selection on timeout
- [ ] Ability conflicts resolved properly
- [ ] Abilities persist across rounds
- [ ] Abilities reset on new game

**Tiebreaker Logic:**
- [ ] Correct players enter tiebreaker
- [ ] Elimination logic works (subset of tied players)
- [ ] No ability selection in tiebreakers
- [ ] Eventually produces single winner

**Multiplayer:**
- [ ] All sync points working
- [ ] Server authority enforced
- [ ] Client disconnection handled
- [ ] Late join prevented

**Final Round:**
- [ ] All players get overpowered abilities
- [ ] Correctly identified as final round

---

### 12. Implementation Priority Order

**Phase 1 - Core Round System:**
1. Round timer implementation
2. Round win tracking
3. Basic round transitions

**Phase 2 - Ability Framework:**
1. Ability data structures
2. Ability selection UI
3. Ability application system
4. Conflict resolution logic

**Phase 3 - Game Flow:**
1. Normal round progression (1 to N-1)
2. Final round special handling
3. Victory screen

**Phase 4 - Tiebreaker System:**
1. Tiebreaker detection
2. Player elimination logic
3. Recursive tiebreaker handling

**Phase 5 - Polish:**
1. UI refinement
2. Multiplayer edge cases
3. Testing and bug fixes

---

## Technical Constraints

**Godot Version:** 4.3
**Networking:** Godot's built-in high-level multiplayer
**Language:** GDScript
**Existing Systems to Integrate:**
- Current health system (3 HP)
- Existing respawn logic (1 sec, invincible, no shooting)
- Kill tracking system
- Sprite selection system

---

## Notes for Claude Code

- Prioritize server-authoritative logic for all game state
- Use Godot signals for state transitions
- Keep ability effects modular (separate script/resource for each)
- Use Godot's RPC system for multiplayer sync
- Consider creating an AbilityManager singleton for ability logic
- Create a GameStateManager for round/match flow
- UI should be responsive and clear about what's happening
- Add debug logging for testing multiplayer edge cases

---

## Success Criteria

✅ Players can set game rules in lobby  
✅ Rounds progress with timer and win tracking  
✅ Ability selection works with correct tier assignment  
✅ Abilities apply correctly and persist across rounds  
✅ Ability conflicts are handled properly  
✅ Final round gives all players overpowered abilities  
✅ Tiebreaker system works with elimination logic  
✅ Game correctly determines overall winner  
✅ All systems work in multiplayer environment  
✅ Edge cases handled gracefully  

---

**End of Specification**
