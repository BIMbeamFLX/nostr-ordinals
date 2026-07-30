# MINT.md: the complete server-side delta

`status: draft` `audience: the SERVICE implementer` `requires: LUD-XX LNURLcash`

Everything the mint has to do to make NORD real, in dependency order,
nothing omitted, nothing optional left ambiguous. Wallet-side groundwork
already exists ([dni/lnurl-wallet#2](https://github.com/dni/lnurl-wallet/pull/2));
the demo UI exists ([600.wtf/nord.html](https://github.com/600-000-000-000/600000000000/pull/32)).
The mint is the missing piece. Estimated honest scope: items 0-3 are an
afternoon each, 4-5 are optional.

## 0. Baseline: catch lnurl-mint up to the current LUD-XX draft

Per the wallet README's compatibility notes, lnurl-mint still serves an
earlier draft. Required before anything NORD:

| # | Change | Why |
| - | ------ | --- |
| 0.1 | Remove the `?id=sha256(k1)` lookup path | dropped from the spec; the informational GET takes the real `k1` and MUST echo the same secret back, never an opaque id |
| 0.2 | Remove multi-`k1` melt | dropped; merge first, then melt one secret |
| 0.3 | Informational GET returns authoritative `maxWithdrawable` = the note's value | it is the only trustworthy value statement; the URL's `amount` is a claim |
| 0.4 | Callback semantics exactly: `k1&pr` melt, `k1` rotate, `k1&amount` split (returns `k1` + `change`), `k1&k1..` merge | the four operations, no others |
| 0.5 | Publish `mintPubkey` (33-byte compressed secp256k1, hex) in withdrawRequest and payRequest | identity anchor for everything below |
| 0.6 | Sign every rotated/split/merged secret: `signature` (+ `changeSignature`) in the success response, recoverable ECDSA (recovery id ‖ r ‖ s, hex) over `sha256("LNURLcash/note" ‖ uint64_be(amount_msat) ‖ sha256(k1))` | offline verification; the wallet already verifies exactly this |
| 0.7 | Optional but cheap: LUD-21 `verify` on invoices | the wallet auto-claims on settlement with it |

## 1. The asset column

The mint already tracks `sha256(k1) -> value_msat` for outstanding
notes. Add one nullable column:

```sql
ALTER TABLE notes ADD COLUMN asset_genesis_id TEXT NULL;
```

Lineage is automatic: rotate writes the new hash with the same
`asset_genesis_id`; melt clears the row. Two guards:

- **Split and merge MUST fail** (`{"status":"ERROR"}`) when any involved
  secret has a non-null `asset_genesis_id`. An ordinal is indivisible.
- A note's asset assignment never changes after mint. There is no
  "reattach".

## 2. withdrawRequest additions

For a note whose secret has an asset:

```json
{
  "tag": "withdrawRequest",
  "callback": "...", "k1": "...", "minWithdrawable": 0, "maxWithdrawable": 0,
  "mintPubkey": "<hex>",
  "asset": ["<genesis event id, hex>", "<relay url>"],
  "artwork": ["<blob url>", "<sha256 of the blob, hex>"]
}
```

- `asset` is the chain pointer (NORD-02). A wallet with a nostr client
  resolves everything from it.
- `artwork` is the no-relay convenience mirror of the genesis `url`/`x`
  tags, so a wallet without a nostr client can still render the card:
  fetch, verify sha256, display. It MUST equal the genesis values -
  serving different bytes here than the genesis committed to is
  equivocation and wallets will surface it.

## 3. Nostr publishing

- Identity per NORD-01: `nostrPubkey == x(mintPubkey)` when the mint
  holds its own signing key; a mint that delegates note signatures to
  its node's `signmessage` RPC (lnurl-mint does) uses a dedicated nostr
  key instead and advertises it as `nostrPubkey` on the withdrawRequest
  - implemented in [dni/lnurl-mint#1](https://github.com/dni/lnurl-mint/pull/1).
- On **mint settlement** of an asset: publish kind `7600` (genesis) with
  `x`, `url`, `birth` = the invoice's payment hash, `amount`, `lnurl`,
  `t` tags and the collection's content JSON (NORD-01).
- On **rotate** of an asset secret: publish kind `7601` referencing
  genesis + current tip; include `["p", <npub>]` iff the caller passed
  `claimer=<npub>` (NORD-02) - otherwise the hop is recorded ownerless.
- On **melt** of an asset: publish kind `7603`. Terminal.
- Publish to >= 2 relays, fire-and-forget with retry; event publishing
  MUST NOT block or fail the LNURL response (the note operation settled;
  the chain follows). Persist unpublished events and drain on a timer.
- The chain rule the mint MUST uphold: never sign two children of the
  same tip. One rotate = one link. This is the entire integrity model.

## 4. Set import (one-time tool, not an endpoint)

For each artwork: upload once to >= 1 Blossom server (BUD-01/02 - HTTP
PUT of the bytes, signed with the mint's key; the server stores it at
`/<sha256>`). For each card instance: precompute the genesis content
JSON. At booster payment: settle invoice, insert note row with asset id,
publish genesis. That is the whole pipeline.

## 5. Optional: registered mode (NORD-02)

`owner` in withdrawRequest; `owner_sig` (BIP-340 over
`sha256("NORD/own" ‖ k1)`) required on every mutating callback for a
registered secret; `register=` / `release=` / `transfer=` params; kind
`7602` confirms. Skip for v1 - bearer mode is the demo.

## 6. Why Blossom, precisely

**Nostr with storage is the app killer.** Relays hold small signed
facts, Blossom holds content-addressed bytes; together they are the
whole backend an app like this needs, and neither half belongs to
anyone. The exact reasons, in decreasing order of weight. "Blossom server" means:
HTTP `GET /<sha256>` returns the bytes whose sha256 is the path, upload
authenticated by a nostr signature (BUD-01/02). That minimalism is the
point.

1. **The identifier is the verification.** Genesis commits to
   `x = sha256(bytes)`. A client that fetches from ANY source - the
   mint, a mirror, a USB stick - runs one hash pass and knows the bytes
   are exactly the committed ones. Transport is untrusted by
   construction, so it can be anything, run by anyone, forever. A
   URL-addressed image (`/art/123.png`) has the opposite property: the
   server can swap bytes after issuance and no client can tell. With
   URL addressing the chain's immutability promise is a lie at its most
   visible layer, the artwork.
2. **Asset survivability decouples from mint survivability.** The
   charge is custodial - mint dies, sats die; that trade-off is
   LNURLcash and it is honest. But the collectible must not die with
   its bank: chain events live on relays, artwork lives on any Blossom
   server that has the blob, and anyone holding a copy can re-seed a
   new server without permission, registration, or coordination,
   because the hash IS the name. The card outlives everyone involved.
3. **Zero-coordination mirroring, boring transport.** Mirroring is
   `curl | PUT`. Caching is standard HTTP caching (the content at a
   hash never changes, so `Cache-Control: immutable` is finally true).
   CDNs, reverse proxies, offline bundles - all free. Compare IPFS:
   DHT resolution latency, CID codec/multihash variability, gateway
   dependence, pinning services as de-facto registries. Blossom is the
   subset of that idea that survives contact with production.
4. **One identity, everywhere.** BUD uploads are signed with nostr
   keys. The mint's `x(mintPubkey)` already signs its notes (LUD-XX)
   and its events (NORD-01); it now also owns its blobs. No second
   account system, no API keys, no bucket policies.
5. **Deduplication by construction.** A set has thousands of card
   instances sharing dozens of artworks. Content addressing stores
   each artwork once, globally, regardless of how many geneses point
   at it - and regardless of who uploaded it first.
6. **The protocol JSON stays small.** LUD-06 metadata images are
   base64-in-JSON - fine for a 20 KB icon, wrong for print-quality
   card art, and every informational GET would re-ship them. A hash +
   URL is 100 bytes; the bytes move once, over a cacheable channel.
7. **Relays are the wrong place for blobs.** Events carrying megabytes
   get rejected or pruned; blob availability would couple to relay
   retention policy. Blossom exists precisely because nostr split
   "small signed facts" (relays) from "large dumb bytes" (blob
   servers). NORD uses each for what it is.
8. **The client cost is already paid.** Fetch + WebCrypto sha256 -
   zero dependencies; the wallet ships this code path today for its
   image handling. Server cost is a static file server with one PUT
   route. There is no cheaper way to get properties 1-7.

## 7. What NOT to build

- No relay inside the mint. The mint is a relay *client*.
- No Blossom server inside the mint. The mint is a Blossom *client*
  (upload at set import); serving blobs is somebody's static box.
- No new endpoints. Everything rides the LUD-03/06 shapes plus fields.
- No account system, no admin UI, no queue infrastructure. SQLite, a
  timer, and the four callback operations LUD-XX already defines.
