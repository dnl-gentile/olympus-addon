# Networking and trust

[Documentation index](../README.md) · [Transport lifecycle reference](../transport-lifecycle.md)

## Transport is separate from authority

The application's ordinary messages remain inside WoW. [Comm.lua](../../Olympus/Comm.lua) supplies common transport and dispatch, but the feature receiving a message still owns its authorization and state-transition checks. A message that parses successfully is not necessarily allowed to change state.

| Layer | Responsibility | Start reading |
| --- | --- | --- |
| Representation | Field encoding, bounded report parsing and fragmented payload assembly | [Codec.lua](../../Olympus/Codec.lua) |
| Shared transport | Admission, paced sending, cancellation, route selection and dispatch | [Comm.lua](../../Olympus/Comm.lua) |
| Cross-guild relay | Reporter registration, relay selection and version/admission policy | [Relay.lua](../../Olympus/Relay.lua) |
| Snapshot distribution | Census distribution tree and missing-piece recovery | [RelayTree.lua](../../Olympus/RelayTree.lua) |
| Fallback routing | Provisional relay election and stand-down behavior | [RelayFallback.lua](../../Olympus/RelayFallback.lua) |
| Feature protocol | Message meaning, sender authority, replay/stale checks and effects | The owning feature module |

## Reporter and census flow

Guild hello messages let clients discover peers and compute reporter selection. Reporter selection is scoped to the relevant guild/realm situation; connected realms are not interchangeable with layers. The normal broadcast interval in Comm is about three minutes (`BROADCAST_EVERY = 170`), with separate witness and other maintenance paths.

On Forever, the relay path is central to cross-guild distribution. Reporters register with relays; relays distribute retained census information; reporters distribute it to their guilds. Current code also joins the faction's public first channel lane and can receive older clients' census broadcasts there. It does not simply broadcast all current Forever traffic on that channel. On other clients, route selection differs.

Treat the historical explanation of a launch-day channel failure as context for the implementation, not a fresh measurement of today's server. Inspect `Comm.ChannelSpec`, `Comm.MaybeBroadcast`, `Relay.On` and the relay statistics when diagnosing the route actually in use.

## Queued work has a lifetime

An enqueue result means the local transport accepted work. Completion means local send calls succeeded; neither guarantees a remote client applied the operation. Transfers have admission limits, pacing, timeouts and receiver assembly limits. Backpressure is expected.

Owners attach cancellation/guard information so queued work can be invalidated when a request expires, permissions change, consent is withdrawn or the player changes guild. Retry callbacks must recheck the current state rather than reuse permission captured at enqueue time. Pending jobs do not persist across reloads.

The [transport lifecycle reference](../transport-lifecycle.md) documents queue fairness, stalls, retryable refusals and cancellation contracts. Preserve those contracts when adding messages; do not create an unrelated unbounded outbox beside Comm.

## Authority layers

| Evidence or policy | What it can establish | What it cannot establish alone |
| --- | --- | --- |
| Native sender and distribution | Who the game says sent the message and its delivery scope | That the sender holds every role claimed in its payload |
| Fresh own-guild roster | Local membership and rank for own-guild actions | Arbitrary other-guild membership |
| Census evidence | Cross-guild observations and bounded rank/identity claims | A universally trusted central directory |
| Signed author lists | Authenticity of the covered list content | Every unrelated operation by someone relaying the list |
| Participant-signed records | Integrity of the signed result under established keys | Ownership of an unestablished identity or a guild office |
| Consent | The player's permitted sharing/features | Authority to act on another player's behalf |
| Presentation preview | Which UI a developer can preview | Permission to send privileged mutations |

[Sign.lua](../../Olympus/Sign.lua) validates author-signed material; [Ed25519.lua](../../Olympus/Ed25519.lua) supports participant-signature uses. The two mechanisms serve different contracts. Private signing material for author lists is not part of the addon package.

[Authority.lua](../../Olympus/Authority.lua) contains a signed-manifest enforcement migration. It is not automatically active merely because its source is loaded. Complete, valid, appropriately scoped signed material governs that boundary. Do not replace fresh roster checks with a guessed role or assume a partial manifest grants authority.

[ViewAs.lua](../../Olympus/ViewAs.lua) is presentation-only. [Accord.lua](../../Olympus/Accord.lua), [Consent.lua](../../Olympus/Consent.lua), moderation and feature-specific permission checks are distinct gates. Native UI restrictions are another independent layer, covered in [UI and gamepad integration](ui-and-gamepad.md).

## Protocol changes

Locate the owning sender and receiver, their distribution filters, framing/version, field limits, replay rules, cancellation owner and tests. Check older-client behavior before changing a field layout. Optional trailing fields in one protocol do not imply every parser tolerates new fields.

Never interpret an unknown value as permission. Validate secret-value handling before comparing or logging chat inputs. Recheck sender authority at the mutation point, including after asynchronous assembly. Limit both stored state and work per input; a valid-looking message can still be expensive or repetitive.

For an unrecognized message type, search registrations such as `Comm.Handle`, `Comm.HandleOutside` and Arena's own handler registry. The [module map](module-map.md) identifies the owner; it is not a substitute for the actual parser contract.
