# Shelter test walkthrough

The ordinary island start is temporarily at the shelter. Start a new game to test
the complete supply layout: old saves correctly retain their pickup ledger and
already consumed supplies. No existing save is deleted or rewritten by this pass.

## Find and carry supplies

1. Henry starts facing the entrance, beyond the veranda steps. The packed bedroll
   and road flare are still separate pickups beside the approach.
2. Looking toward the entrance, walk along the right side of the house for the
   full-size plank stacks. Each F pickup carries three boards in Henry's arms;
   they are not placed invisibly into a backpack. More than one trip is expected.
3. The log piles are on the left side of the entrance approach. Each pile gives
   three visible logs, matching the stove's capacity. There are nine logs nearby.
4. Inside, find the separate wooden tool bench on the right: hammer, nail box
   (66 nails), and orange lighter, spaced apart. Aim at each item and tap F.
   These props stand above the bench and floor, not inside the slab. The hammer
   automatically enters a fitting Quick Access pocket after the stow animation.
5. Spare boards are inside near the tool bench. Extra test stacks remain explicit
   `shelter_test` entries in the layout; the generator retains this arrangement.

## Board a window

1. Carry an armful into the house. Approach the chosen window from inside and aim
   at its opening. F says **Lay boards beside window** and leaves the armful on
   the floor beside that opening. This frees both hands without sealing the gap.
2. Pick up the hammer and nails if you have not yet done so. Return to the same
   opening: F says **Take one board and draw hammer**. The already owned hammer
   is drawn from the pack or pocket; a board appears in the other hand.
3. A translucent plank appears across the window. Moving the camera up or down
   chooses its height. Green means placement is allowed; red means too far away
   or obstructed. Looking away hides the ghost. A wall between Henry and the
   window prevents installation.
4. LMB nails that board and consumes exactly two nails. The placed board stays;
   the ghost goes away. The prompt reports the remaining gap. F selects the next
   board, so each installation is a deliberate separate action.
5. Lay boards next to one another rather than overlapping them. A 1.1 m window
   can be sealed with five carefully fitted 0.24 m boards: approximately bottom,
   lower middle, centre, upper middle, top. Bring a second armful when needed.
6. Esc cancels a pending installation without spending boards or nails. Unused
   boards remain beside that window; F recovers them after it is sealed.

There are 33 boards across the test route, 27 at/inside the shelter, and 66 nails.
The wider route still contains supplies; opening overlap still wastes coverage.

## Light the stove

1. Pick up the lighter from the tool bench. It stays reusable in the inventory;
   it does not need a new binding or a separate selected-item action.
2. Carry a three-log pile from the left side of the house to the stove. Aim at
   the firebox/door, not the cooking ring above it.
3. First F: **Open stove door**. The door swings open; no logs are spent.
4. Second F: **Put carried logs inside**. Up to three logs move from the arms to
   the firebox. The cold load is visible and saved without starting a fire.
5. Third F: **Light with lighter**. Without the lighter, the prompt tells Henry
   where to find it, and the loaded wood stays intact. No hidden tinder item is
   required by this player interaction. Ignition takes five seconds; Henry holds
   still, flame grows, then the door closes and the HeatSource starts burning.
6. The prompt reports loaded logs and remaining hours (three logs = six game
   hours). Additional wood can be loaded later by opening the door again.
7. **Room air: ... °C** appears at the upper right while inside. It reads outdoor
   air plus accumulated room heating, excluding core body temperature and the
   stove's immediate radiant warmth. Heating rises at the existing six degrees
   per game hour, with a small two-degree ceiling even in the completely leaky
   test shelter. Boarding increases the ceiling toward eighteen extra degrees.

## Sit, eat, wait, sleep and drop the flare

Aim at the small cloth-covered table or its seat beside the stove and press F.
Henry sits on the seat; his pack and Kenny are set beside him, and carried food
appears on the cloth. Aim at a food prop and F eats/drinks one unit. Seated
selection uses the actual camera-centre ray and continues respecting walls.
F with no reachable target opens waiting; movement or Esc stands Henry up,
clears the food presentation, and picks up the pack. Armfuls must be put down
before sitting; a refusal explains this at the centre prompt.

The stove cooking ring retains its separate warming interaction for a carried
tin/mug. Pick up the bedroll and use its existing item action to enter placement;
the mattress remains a separate sleep interaction.

Draw the unlit flare through Quick Access. LMB lights it; LMB again drops the
burning flare. It now leaves the actual hand height in a small rigid body,
inherits walking velocity, falls under gravity, and collides with terrain/floor.
It keeps burning after landing. Held-item rotation remains specific to the flare.

## Verification and limits

`test_shelter_workflow.gd` uses the real player scene, its component/input routing,
a TPS camera with the production 0.51 m lens offset, and generated house
collisions. It tests tool and floor pickup, both board trips, five LMB placements,
cancel/obstruction, cold three-log loading, missing lighter, ignition, progressive
warmth/readout, table eating/standing, and a flare settling on the floor.

Player/camera locomotion is held fixed by the harness while testing aiming and
actions; outdoor heightmap traversal and an unrestricted manual island playthrough
remain the author's gameplay test. Local compatibility-renderer captures verify
visible bench tools, board preview/control text, stove flame and room readout.

The old instantaneous `HeatSourceFeed.feed()` remains a legacy test/tool seam;
runtime player input exclusively follows `begin_act()`'s staged steps.
