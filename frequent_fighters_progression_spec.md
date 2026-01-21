# Frequent Fighters - Progression System Implementation Spec

## Project Overview
Frequent Fighters is a multiplayer plane combat game built in Godot. This spec covers the implementation of a round-based progression system with ability selection mechanics.

## Current Game State (Already Implemented)
- Multiplayer networking functional
- Player plane sprite selection
- Main combat scene with flying and shooting (spacebar)
- **Server-authoritative health system** (3 HP per player, tracked on server)
- **Server-authoritative damage processing** (all damage validated on server)
- Kill tracking with star display under sprites
- Kill attribution (only final blow counts, processed on server)
- **Server-controlled respawn system** (3 second timer, no shooting while dead)
- **Server tracking:** `player_health`, `player_max_health`, `player_respawn_state` dictionaries

## New Features to Implement

### 1. Pre-Game Lobby/Menu Enhancements
**Location:** Same screen where players choose plane sprites

**New UI Elements:**
- Game mode selector (default: "Free-for-All")
- Round timer input (in minutes) - determines duration of each combat round
- Number of rounds input (default: "5 rounds") - determines how many rounds total in a match

**Requirements:**
- **SERVER AUTHORITY:** These settings should be server-controlled (only server can modify)
- Settings stored on server and synced to all clients via RPC
- Default values if not set: FFA mode, 1 min per round, 5 rounds
- Clients display settings but cannot modify them

---

### 2. Round Timer System

**Core Functionality:**
- Display countdown timer during combat rounds
- Timer starts when round begins
- When timer reaches 0, round ends immediately (no grace period)
- Timer should be visible to all players (UI element)
- Respawn system polishing (Remove player ability to shoot during 1 second respawn timer)

**Technical Notes:**
- **SERVER AUTHORITY:** Timer runs ONLY on server, synced to clients for display
- Server tracks `current_round_time: float` and broadcasts updates
- Clients display timer but cannot modify it
- Server controls when round ends (clients just react to server's end-round RPC)
- Pause timer during ability selection screens (server-side pause)

---

### 3. Round Win Determination

**Rules:**
- Round winner = player(s) with highest kill count during that specific round
- Multiple players can win a round (tie in kills)
- If ALL players have 0 kills, NO ONE is considered a winner
- Track round wins separately from total kills

**Data Structure Needed (SERVER-SIDE):**
```gdscript
# GameManager.gd - Server authoritative tracking
var player_round_wins: Dictionary = {}  # {player_id: win_count}
var player_rounds_won: Dictionary = {}  # {player_id: [round_numbers]}
var player_current_round_kills: Dictionary = {}  # {player_id: kills_this_round}
var player_total_kills: Dictionary = {}  # {player_id: total_kills_all_rounds}

# Initialize in spawn_player():
if multiplayer.is_server():
    player_round_wins[player_id] = 0
    player_rounds_won[player_id] = []
    player_current_round_kills[player_id] = 0
    player_total_kills[player_id] = 0
```

**Important (SERVER-SIDE LOGIC):**
- Server resets `player_current_round_kills` to 0 at the start of each new round
- Server tracks `player_round_wins` separately for overall game winner determination
- Server stores which players won each round in `player_rounds_won` for tiebreaker logic
- Server syncs all these stats to clients via RPC for UI display only

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

**Multiplayer Sync (SERVER AUTHORITY):**
- Server tracks which players have selected abilities: `var player_ability_selections: Dictionary = {}`
- Clients send their selection to server via RPC: `request_ability_selection.rpc_id(1, ability_id)`
- Server validates selection and applies ability
- Server broadcasts when all selections complete OR timer expires
- Server decides when to proceed to next round
- Show waiting status for players who've already selected (based on server state)

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

**Implementation Logic (SERVER-SIDE):**
```gdscript
# GameManager.gd - Server authoritative ability management
var player_active_abilities: Dictionary = {}  # {player_id: [ability_list]}

func apply_ability_to_player(player_id: int, new_ability: String):
    # SERVER ONLY
    if not multiplayer.is_server():
        return

    # Check for conflicts
    var conflict_category = get_conflict_category(new_ability)

    if conflict_category != null:
        # Remove existing ability in same category
        remove_player_abilities_in_category(player_id, conflict_category)

    # Add new ability to server tracking
    if not player_active_abilities.has(player_id):
        player_active_abilities[player_id] = []
    player_active_abilities[player_id].append(new_ability)

    # Apply effects (server-side stat changes)
    apply_ability_effects(player_id, new_ability)

    # Sync to all clients for display
    sync_player_abilities.rpc(player_id, player_active_abilities[player_id])
```

### 5.3 Ability Persistence (SERVER-MANAGED)
- Server tracks abilities in `player_active_abilities` dictionary
- Abilities carry through ALL rounds in a match (server maintains state)
- Abilities stack unless they conflict (server enforces conflict rules)
- Server resets ALL abilities when new game/match starts
- Abilities persist through death/respawn within same match (server doesn't clear on respawn)
- On player respawn, server re-applies ability stat bonuses (like +health from abilities)

### 5.4 Random Selection Weighting (SERVER-SIDE)
```gdscript
# GameManager.gd - Server generates ability choices
func generate_ability_choices_for_player(player_id: int, tier: String) -> Array:
    # SERVER ONLY - generates 3 random abilities for a player
    if not multiplayer.is_server():
        return []

    var tier_abilities = get_abilities_for_tier(tier)
    var choices = []

    # Pick 3 unique abilities using weighted random
    for i in range(3):
        var ability = get_weighted_random_ability(tier_abilities)
        choices.append(ability)
        # Remove from pool to ensure uniqueness
        tier_abilities.erase(ability)

    return choices

func get_weighted_random_ability(tier_abilities: Array):
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

**Technical Requirements (SERVER AUTHORITY):**
- Server tracks which players are "in tiebreaker": `var tiebreaker_participants: Array = []`
- Server recalculates after each tiebreaker who remains tied
- Server continues tiebreaker rounds until single winner emerges
- Server enforces: No ability selection during ANY tiebreaker rounds
- Server broadcasts tiebreaker state to all clients for UI display

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

**Critical Sync Points (ALL SERVER-AUTHORITATIVE):**
1. **Round timer** - Server runs timer, broadcasts current_time to clients for display
2. **Kill counting** - Server increments `player_current_round_kills[player_id]` on each kill
3. **Round win determination** - Server calculates winners, updates `player_round_wins`
4. **Ability selection** - Clients send requests, server validates and applies
5. **Tiebreaker participants** - Server determines and broadcasts participant list
6. **Ability effects** - Server applies stat changes, syncs to clients

**Server Authority (GameManager.gd):**
- Server determines round winners via `determine_round_winners()` function
- Server tracks round wins in `player_round_wins: Dictionary`
- Server manages tiebreaker logic in `start_tiebreaker()` function
- Server enforces ability conflicts in `apply_ability_to_player()`
- Server tracks all player abilities in `player_active_abilities: Dictionary`
- Server owns all game state, clients are "dumb displays"

**Client Responsibilities:**
- Display UI based on server state (received via RPCs)
- Send ability selections to server: `request_ability_selection.rpc_id(1, ability_id)`
- Render ability effects locally (visual only, stats controlled by server)
- Display synchronized timers (received from server)
- NEVER modify game state locally - always request changes from server

---

### 10. Edge Cases to Handle

1. **Player disconnects during ability selection** (SERVER HANDLES)
   - Server detects disconnect via `peer_disconnected` signal
   - Server auto-selects random ability from their choices
   - Server continues when remaining players ready OR timer expires

2. **Player disconnects during combat** (SERVER HANDLES)
   - Server maintains their state in dictionaries (kills/round wins/abilities)
   - Server marks them as disconnected but keeps data
   - Server excludes them from future tiebreakers if they don't reconnect

3. **All players have 0 kills** (SERVER DETERMINES)
   - Server's `determine_round_winners()` returns empty array
   - Server broadcasts "no winners" state
   - Server ensures all players get BASIC abilities next round

4. **Player rejoins mid-match** (SERVER VALIDATES)
   - Server checks if player_id exists in current match data
   - If exists: Server re-syncs their full state (abilities, stats, round wins)
   - Server forces them to spectate (is_respawning = true) until next round
   - Server restores their sprite/abilities/stats from dictionaries

5. **Tiebreaker with 2+ players, multiple tie again** (SERVER LOGIC)
   - Server's tiebreaker logic handles subset elimination
   - Server recalculates `tiebreaker_participants` after each round
   - System handles any number of tied players (server iterates until one winner)

6. **Rapid fire + Super Rapid Fire stacking** (SERVER VALIDATES)
   - Both are stackable (server allows both in `player_active_abilities`)
   - Server applies fire rate multipliers: `base_cooldown * rapid_fire_mult * super_rapid_fire_mult`
   - Works as intended (very fast shooting, validated on server)

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
**Architecture:** **Server-Authoritative** (all game state on server, clients display only)

**Existing Systems to Integrate:**
- **Server-authoritative health system** (tracked in `player_health`, `player_max_health` dicts)
- **Server-controlled respawn** (3 sec timer, tracked in `player_respawn_state`)
- **Server-side kill tracking** (increments `player_current_round_kills` on server)
- Sprite selection system (client-initiated, server validates)

**Server State Dictionaries (GameManager.gd):**
- `player_health: Dictionary`
- `player_max_health: Dictionary`
- `player_respawn_state: Dictionary`
- `player_round_wins: Dictionary` (new)
- `player_current_round_kills: Dictionary` (new)
- `player_active_abilities: Dictionary` (new)

---

## Notes for Claude Code

### **CRITICAL: Server-Authoritative Architecture**
- **ALL game state lives on the server** (GameManager.gd dictionaries)
- **Clients are "dumb displays"** - they only render what server tells them
- **Never trust client input** - server validates all requests
- **Use RPC pattern:** Client requests → Server validates → Server broadcasts

### **Implementation Guidelines:**
- Store ALL game state in GameManager.gd dictionaries (server-side)
- Use Godot signals for state transitions (server emits, clients listen)
- Keep ability effects modular but server-validated
- Use `@rpc("any_peer", "call_local", "reliable")` with server validation pattern:
  ```gdscript
  @rpc("any_peer", "call_local", "reliable")
  func sync_game_state(...):
      var sender = multiplayer.get_remote_sender_id()
      if sender != 0 and sender != 1:  # Only server can send
          return
      # Apply state...
  ```
- Consider creating an AbilityManager in GameManager for ability logic (server-side)
- Create a RoundManager (already exists) for round/match flow (server-controlled)
- UI should be responsive and clear about what's happening
- Add debug logging for testing multiplayer edge cases
- **Pattern:** `player_stat_name: Dictionary = {player_id: value}` for all player stats

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
