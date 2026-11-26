# Olympus 1.6.4.1

Small visual consistency update. Portraits and chat marks follow their standard role visuals.

No release letter is added for this maintenance version. Existing office, membership, authorization and signed-list data are unchanged.

## Validation

Run the full `bash scripts/check.sh` before publication. Focused regression checks exercise the actual portrait and chat selectors, including the standard High Council appearance and gamepad transitions. A version-letter regression verifies that the maintenance release creates no automatic letter or letter retry timers, while archived letters remain available.

Offline checks do not establish installed-client behavior. In game, check target, focus, party and player portraits plus native guild chat for a councillor and an ordinary member; confirm that existing roles remain unchanged and that updating does not open a maintenance letter.
