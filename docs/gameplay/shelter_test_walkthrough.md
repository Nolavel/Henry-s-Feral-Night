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
   (66 nails), orange lighter and silver-bladed knife, spaced apart. Aim at each item and tap F.
   These props stand above the bench and floor, not inside the slab. The hammer
   automatically enters a fitting Quick Access pocket after the stow animation.
5. Spare boards are inside near the tool bench. Extra test stacks remain explicit
   `shelter_test` entries in the layout; the generator retains this arrangement.
6. A second bench beside the tools holds a teal one-litre flask, two yellow-label
   pineapple tins and two red-label stew tins. Pick them up separately with F.
   The food is visible above the tabletop, not hidden in a cabinet or floor.

## Drink water and open pineapple

1. Pick up the flask and knife before going to the cloth-covered meal table by
   the stove. The knife stays in the pack or a pocket; it need not be drawn.
2. The existing Hub **Use** action drinks 250 ml. The flask goes through 1000,
   750, 500, 250 and 0 ml, restoring 12 hydration points per drink. It remains a
   container after the fourth drink; using it empty explains that it is empty.
3. Select the flask in the pack or pocket list: the detail line shows total drunk
   and remaining/capacity in millilitres. The row also shows remaining/capacity,
   and each drink briefly displays the updated figures. A pocketed flask returns
   to the same pocket. Saving retains its current fill; other flasks are unaffected.
4. Sitting presents carried food and drink on the cloth. Aim at the flask and F
   drinks one 250 ml portion through the same consumption system. The old target
   disappears and the remaining flask becomes the next target.
   Different kinds are placed before duplicate tins, so the six cloth slots do
   not hide water or pineapple behind a larger stack of stew.
5. Aim at a pineapple tin: F explicitly says **Open with knife and eat pineapple**.
   Without the knife, the tin is preserved and the refusal points to the tool
   bench. With the knife, this single action opens and eats one tin, adds 300
   calories and eight hydration points, and leaves an empty tin. The knife is
   reusable. Hub Use performs the same action when standing.
6. These are finite test supplies. The empty flask is retained; refilling,
   water purification, knife combat and separate opened-tin storage are not
   implemented by this pass.

## Turn a wooden table into logs

1. First collect all supplies from the bench you intend to dismantle. A table
   with uncollected world items refuses dismantling and explains what to do.
2. Draw the owned hammer through Quick Access/Use. Only while Henry stands with
   the hammer in hand does aiming at the tool bench, supply bench or meal table
   offer **Dismantle wooden table**. The prompt warns: four seconds, three logs,
   table lost. Ordinary F at the meal table still sits Henry when no hammer is drawn.
3. Tap F once; Henry works for four seconds. The tabletop/legs and their solid
   collisions are removed, and three visible logs lie on the interior floor.
4. Pick up the pile with F, carry it to the stove and use the existing open,
   load, light sequence below. Destroying the meal table sacrifices its food
   presentation surface; keep it if you want to use the seated eating ritual.
5. Saves retain the destruction and collection separately. Reloading cannot
   grow the table back or duplicate an already collected salvage pile.

## Roof closure

The shelter and other intact generated bungalow variants now have solid wooden
front/back gables, a ridge cap and strips between side walls and roof eaves. The formerly open
upper holes are closed with matching collision geometry. Windows remain the
intended boarding work; deliberately ruined/roofless houses keep their damage.

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
warmth/readout, table eating/standing, and a flare settling on the floor. It also
checks real F pickups of the new supplies, missing-knife refusal, pineapple
nutrition, four water portions, fill-state save round trips, independent flasks,
same-pocket replacement, roof occlusion and timed table salvage/ledger restoration.

Player/camera locomotion is held fixed by the harness while testing aiming and
actions; outdoor heightmap traversal and an unrestricted manual island playthrough
remain the author's gameplay test. Local compatibility-renderer captures verify
visible bench tools, board preview/control text, stove flame and room readout.
The supplies pass adds captures of both benches, the closed gable, meal props,
drink feedback and the partly filled flask's Hub details. Its issue-reading
record is `docs/audits/2026-09-27-shelter-supplies-issue-review.md`.

The old instantaneous `HeatSourceFeed.feed()` remains a legacy test/tool seam;
runtime player input exclusively follows `begin_act()`'s staged steps.
