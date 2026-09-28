# Shelter test walkthrough

The island temporarily starts directly outside the shelter entrance for the
author's stove/interaction tests (2026-09-28), facing the house. Start a new game
to use this spawn; Continue restores the position in the existing save. The
complete supply layout, bonus stacks and spare bedroll/flare kit remain in place.
Existing saves and their consumed-pickup ledger are preserved.

## Find and carry supplies

1. Henry starts in the shelter entrance approach, between its spare bedroll
   and road flare. The bunker kit remains available for later route testing.
2. Looking toward the entrance, walk along the right side of the house for the
   full-size plank stacks. Each F pickup carries three boards in Henry's arms;
   they are not placed invisibly into a backpack. More than one trip is expected.
3. The log piles are on the left side of the entrance approach. Each pile gives
   three visible logs, matching the stove's capacity. There are nine logs nearby.
4. Inside, find the separate wooden tool bench on the right: hammer, nail box
   (66 nails), orange lighter, silver-bladed knife and hatchet, spaced apart. Aim at each item and tap F.
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
2. In the Hub, move the flask/tin into a fitting Quick Access pocket. Close the
   Hub and press its `1`–`4` slot, or select with the wheel and wheel-click. The
   owned item appears in the hand; drawing alone does not consume anything.
   `LMB` uses the held item. Switching pockets or opening the Hub safely stows it.
3. Flask Use drinks 250 ml. The flask goes through 1000,
   750, 500, 250 and 0 ml, restoring 12 hydration points per drink. It remains a
   container after the fourth drink; using it empty explains that it is empty.
4. Select the flask in the pack or pocket list: the detail line shows total drunk
   and remaining/capacity in millilitres. The row also shows remaining/capacity,
   and the held flask has a volume mark on both faces plus a persistent drunk/
   remaining readout. A pocketed flask returns
   to the same pocket. Saving retains its current fill; other flasks are unaffected.
5. Sitting presents carried food and drink on the cloth. Aim at the flask and F
   drinks one 250 ml portion through the same consumption system. The old target
   disappears and the remaining flask becomes the next target.
   Different kinds are placed before duplicate tins, so the six cloth slots do
   not hide water or pineapple behind a larger stack of stew.
6. Aim at a pineapple tin: F says **Open pineapple tin with knife**.
   Without the knife, the tin is preserved and the refusal points to the tool
   bench. With the knife, the first action leaves an opened tin with visible
   fruit and no nutrition change. Aim at the opened tin and F again to eat it,
   add 300 calories and eight hydration points, and leave an empty tin. Standing,
   the held tin uses the same two actions through LMB. The knife is reusable and
   the opened tin can be saved in the pack/pocket between opening and eating.
7. These are finite test supplies. The empty flask is retained; refilling,
   water purification and knife combat are not
   implemented by this pass.

## Turn a wooden table into logs

1. First collect all supplies from the bench you intend to dismantle. A table
   with uncollected world items refuses dismantling and explains what to do.
2. Draw the owned hammer through Quick Access/Use. Only while Henry stands with
   the hammer in hand does aiming at the tool bench or supply bench
   offer **Dismantle wooden table**. The prompt warns: four seconds, three logs,
   table lost. The cloth-covered meal table is protected: F always enters its
   seated ritual, including when a safely stowable tool is drawn.
3. Tap F once; Henry works for four seconds. The tabletop/legs and their solid
   collisions are removed, and three visible logs lie on the interior floor.
4. Pick up the pile with F, carry it to the stove and use the existing open,
   load, light sequence below. The ritual table remains available for meals.
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

## Put wood down or chop boards

`G` places the entire carried log/board pile on the ground 1.35 m in front of
Henry. It checks the floor height/slope, the path and room for the whole pile;
obstructed or missing ground leaves the load in his arms. Interaction trigger
Areas do not block the placement. `F` recovers all units from the floor.

To turn boards into fuel, put them down with G, draw the hatchet from a Quick
Access pocket, aim at that loose board pile and tap F. Four seconds of work
turn each board into one firewood log. Stowing the hatchet before completion
keeps the boards intact. Without a drawn hatchet F picks the boards up normally.
Loose piles and collected source IDs follow the existing save/ledger contract.

## Door and stove

The exterior door is always operable; its closed frame leaks 5% of an open
aperture. Snow enters through the four actual edge gaps only, follows live wind
and snowfall, and stops on the moving leaf/frame. Only the four windows accept
boards, hammer placement and nails. Old boarded-door saves do not lock it.

1. A new game starts with the reusable lighter in the right coat pocket
   (Quick Access slot 2) and one tinder portion in the left thigh pocket (slot 3).
   Stove preparation draws the lighter and uses tinder directly from these pockets;
   no pickup or Quick Access selection is needed. Existing saves restore their own
   pockets; Continue does not replace them with the starting equipment. Additional
   tinder remains at the fort/collapsed house after the starter portion is spent.
2. Aim at the stove door/handle: **F opens or closes it**. Aim inside the open
   firebox for fuel and ignition. The cooking ring remains a separate target.
3. With wood in Henry's arms, **F loads the whole armful that fits**. The prompt
   shows the number before starting. Loading takes two seconds and 0.5 game
   minutes per log. Logs leave the hands and appear in the firebox on completion;
   F cancellation before completion preserves the entire carried load.
   The main prompt shows the loading percentage; F cancellation is secondary.
   The stove advances its transfer presentation directly through the shared action
   system, which still owns game-time billing, stop checks and completion. Loss
   of that action ends the loading state with a retry hint instead of leaving it busy.
4. Any surplus is automatically put down as a normal saved wood pile. Placement
   checks the floor ahead, then to Henry's left and right. If every position is
   blocked, the loaded wood stays in the stove and the surplus stays in his arms.
   The prompt explains the obstruction; use **G** somewhere clear, then F to
   prepare ignition. A burning stove only receives fuel and does not prepare a lighter.
5. After a cold load, Henry **automatically draws his owned lighter and kneels**
   using the existing Fixing_Kneeling animation. He holds its middle at 2.6 seconds,
   with the hand at the firebox instead of the torch pose. No extra F or Quick
   Access selection is needed. Missing lighter/tinder never prevents loading:
   the cold logs remain inside and the prompt names the missing item. Once it is
   acquired, **F lights the stove** by starting the same kneeling preparation.
   Lighter and tinder ownership includes the pack and worn pockets. An already
   drawn lighter is stowed before the stove draws its strike prop; it does not
   block the action. Missing-item prompts name the prerequisite directly, with
   no F ignition offer. A completed load remains clearly reported even if the
   next ignition step cannot start.
6. Once Henry has settled into the pose, **press and hold LMB for three seconds**.
   Each accepted press gives a guaranteed audible strike, visible sparks and
   lighter flame. Pressing before the pose is ready does not start a flame; release
   and press once ready. Short holds do not accumulate. Release or a paused menu
   immediately extinguishes the lighter and resets the hold; resuming requires a
   fresh press. Tinder is spent once when the fire catches. Henry then puts away
   the lighter and finishes the animation to stand up; the stove door stays open.
   **F cancels** either loading or ignition. During an action, moving the crosshair
   between this stove's body, firebox and door preserves the same interaction.
   Aiming elsewhere, leaving reach or losing the stove cancels it. Cancelling
   before Henry settles reverses the partial kneel instead of completing the work clip.
   **RMB retrieves up to two intact cold logs**, with the usual hand/weight limits.
   During ignition preparation it first cancels the lighter. Returned wood remains
   in Henry's arms; RMB can retrieve again, and F deliberately loads it back.

7. The stove then develops independently for **20 seconds at normal game speed**,
   from 8% to full output. Flame, light, radiant warmth, room heating and cooking
   share HeatSource intensity. Sleep and accelerated time advance the same stage;
   saves restore progress. Old burning saves load fully developed. Previously
   burned fuel never returns as whole logs; old cold saves without intact-log
   accounting conservatively offer no retrieval.
8. **Room air: ... degrees** shows outdoor air plus accumulated room heating,
   excluding body temperature and the stove's immediate radiant warmth. Windows
   determine the heat ceiling; the closed door gap has only a small effect.

Transfers commit items/fuel on completion. **F cancels an ongoing transfer**;
looking away also cancels, preserving resources. Partial work retains only the
existing earned game-time cost. Stove mouse input takes priority over Quick Access.

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

This stove revision has not been run in Godot or rendered by Codex, at the author's
request. Earlier automated stove expectations still describe the previous controls.
For manual acceptance, check a full armful, a partially full cold stove with
surplus placed nearby, blocked overflow placement, missing lighter/tinder,
short versus uninterrupted holds, pause/cancellation and hot refueling.
The held load, visible stove fuel and loose piles must always account for the
same total logs; preparing a lighter must never spend tinder.

`test_shelter_workflow.gd` uses the real player scene, its component/input routing,
a TPS camera with the production 0.51 m lens offset, and generated house
collisions. It tests tool and floor pickup, both board trips, five LMB placements,
cancel/obstruction, cold three-log loading, missing lighter, ignition, progressive
warmth/readout, table eating/standing, and a flare settling on the floor. It also
checks real F pickups of the new supplies, missing-knife refusal, pineapple
nutrition, four water portions, fill-state save round trips, independent flasks,
same-pocket replacement, roof occlusion and timed table salvage/ledger restoration.

`test_held_supplies.gd` additionally checks real hand sockets and pocket/input
routing, wheel-click draw before Use, finite water marks, duplicate pack items,
two-step pineapple, missing knife, hand invalidation, blocked G drops, axe
conversion/cancellation and loose-wood restore order. The workflow test confirms
that a drawn hammer cannot replace the protected meal ritual with dismantling.

Player/camera locomotion is held fixed by the harness while testing aiming and
actions; outdoor heightmap traversal and an unrestricted manual island playthrough
remain the author's gameplay test. Local compatibility-renderer captures verify
visible bench tools, board preview/control text, stove flame and room readout.
The supplies pass adds captures of both benches, the closed gable, meal props,
drink feedback and the partly filled flask's Hub details. Its issue-reading
record is `docs/audits/2026-09-27-shelter-supplies-issue-review.md`.

The old instantaneous `HeatSourceFeed.feed()` remains a legacy test/tool seam;
runtime player input exclusively follows `begin_act()`'s staged steps.
