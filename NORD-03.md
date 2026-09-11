# NORD-03: FIPS transport binding

`author: FLX` `status: draft` `requires: NORD-01, NORD-02`

[FIPS](https://fips.network) (Free Internetworking Peering System) is a
self-organizing encrypted mesh where node addresses *are* nostr
keypairs, reachable as `<npub>.fips` over an IPv6 TUN interface -
existing HTTP software runs over it unchanged, over UDP, TCP, Ethernet,
Tor, Nym or Bluetooth. NORD already binds every actor to a secp256k1
identity; FIPS makes that identity the network address. This document
specifies FIPS as an **optional transport**: clearnet (plain IP + DNS)
stays the default for now, but implementations carry `.fips` support in
the code from day one - flipping the default later is configuration,
not development.

## Identity is the address

NORD-01 gives the mint a nostr identity, `nostrPubkey`. A NORD mint
SHOULD run a FIPS node **on that keypair**, making it reachable at:

```
http://<npub(nostrPubkey)>.fips/...
```

This closes the last trust gap in transport: a wallet talking to
`<npub>.fips` is, by construction, talking to the keyholder that signs
the asset chain - and the same endpoint advertises the `mintPubkey` the
notes' certificates verify against. No DNS to poison, no CA to trust, no
certificate to expire. TLS is not used on `.fips` hosts - the mesh is
already Noise-encrypted hop-by-hop and end-to-end.

Relays and Blossom servers SHOULD likewise be reachable at their own
`<npub>.fips` addresses (`ws://<npub>.fips/`, `http://<npub>.fips/<sha256>`),
and genesis `url` hints MAY be `.fips` URLs.

## URL rules

- Wallets MUST resolve `.fips` hosts as `http://` (the same rule LUD-17
  clients already apply to `.onion`). For lnurlcash/lnurl-wallet this is one
  line: `host.endsWith('.fips')` in `isInsecureHost`.
- A note URL SHOULD use the mint's `.fips` address as its canonical
  host. The host is transport, never identity: `k1` is the asset,
  reachable at any host the mint declares (below).

## Mirrors

For holders without a FIPS node, the mint MAY declare interchangeable
hosts in its `withdrawRequest`:

```json
{
  "tag": "withdrawRequest",
  "...": "...",
  "hosts": ["<npub>.fips", "mint.example.com"]
}
```

Every listed host MUST serve the same secret space (same k1s, same
callbacks, same responses). Wallets MAY rewrite a note URL's host to any
declared mirror - e.g. before handing a note to a legacy recipient,
swap `.fips` for the clearnet mirror. Mirror rewriting MUST NOT touch
`k1`, `amount` or `sig`.

## Local-first operation

Because FIPS composes transports on one mesh, the entire NORD stack runs
with no internet at all: mint, relay and Blossom on one machine, viewers
joining over LAN or Bluetooth. Notes minted, traded and melted at a
conference table settle exactly as they do globally - the mesh *is* the
venue, and the mint's address is the same npub in both worlds. Chain
events publish to the local relay immediately and propagate to public
relays whenever the mesh regains an internet-connected node.

## Fallback and compatibility

A legacy wallet (no FIPS, no NORD) needs a clearnet mirror in the note
URL to function at all - mints that expect legacy traffic SHOULD hand
out notes on the mirror host and let NORD wallets rewrite toward
`.fips`, rather than the reverse. Everything else degrades exactly as in
NORD-02: no FIPS daemon, use the mirror; no NORD support, notes are
plain LUD-03 withdraw links.

## Security considerations

- `.fips` reachability proves keyholder control **now**; it does not
  prove the mint is honest (NORD-01's trust model is unchanged).
- Mirror lists are served by the mint and are as trustworthy as the
  mint; a wallet MUST NOT accept mirrors for one mint from another
  origin.
- FIPS is v0.5.x - mints SHOULD treat it as an additional door, not yet
  the main one. Support-on by default, reliance-off until the mesh
  earns it.
