## Summary

<!-- What changed and why. One paragraph. -->

## Files changed

<!-- Group by area: gameplay / networking / UI / level / tests / docs / CI. -->

## Gameplay impact

<!-- What a player would notice. "None" is a valid answer. -->

## Networking impact

- [ ] No new RPCs, or every new RPC is listed below
- [ ] Every client -> host RPC starts by proving the receiver is the host
- [ ] Every host -> client RPC on a client-authority node is gated on the sender being peer 1
- [ ] Every new client request carries the session epoch and is rejected when stale
- [ ] Rate limiting considered for any new client-callable entry point

New or changed RPCs:

<!-- name | direction | reliability | who may call it | what the host validates -->

## Security and authority review

- [ ] No gameplay outcome is decided on a client
- [ ] No client-reported position, health, inventory or cooldown is trusted
- [ ] Object ids referenced by clients are re-checked against the host's own registry
- [ ] Interaction range and line of sight are re-checked by the host

## Tests

Automated tests run (paste the summary line):

```
```

Multi-process multiplayer check run (paste the RESULT line):

```
```

Runtime tests actually performed by hand:

<!-- Be specific: "2 instances on one machine, host + 1 client, full mission". -->

Tests NOT run, and why:

<!-- Honesty here is the point. "Windows build not launched - no Windows machine" -->

## Regression risks reviewed

- [ ] Scene transitions and the readiness barrier
- [ ] Replay / retry / return-to-lobby leaves no stale state
- [ ] Disconnect during each mission stage
- [ ] Victory and failure paths

## Windows export impact

- [ ] `export_presets.cfg` unchanged, or the change is described below
- [ ] Nothing under `tests/` or `tools/` can reach the shipped pack

## Known limitations introduced

<!-- Anything left unverified must also be recorded in docs/KNOWN_LIMITATIONS.md. -->
