# MINT.md: the complete server-side delta

`status: draft` `audience: the SERVICE implementer` `requires: LUD-25 LNURLcash @ d2f307f`

Everything the mint has to do to make NORD real, in dependency order.
Wallet-side groundwork already exists (our [lnurl-wallet fork](https://github.com/BIMbeamFLX/lnurl-wallet/tree/feature/nostr-ordinals));
the demo UI exists ([600.wtf/nord.html](https://github.com/600-000-000-000/600000000000/pull/32)).
The mint is the missing piece. Estimated honest scope: 0.1-0.5 and 0.7
are an afternoon each, 0.6 is the one real feature.

## 0. Baseline: what lnurl-mint already does, and the delta

Checked against `lnurlcash/lnurl-mint@f09849c`. The July catch-up list
is withdrawn: lnurl-mint now implements the pinned LUD-25 itself, Part 2
included, and its formats replace the ones this document used to define
(no `?id=` removal, no `LNURLcash/note` digest, no `signature` /
`changeSignature` fields).

What NORD builds on, unchanged:

| LUD-25 piece | lnurl-mint | NORD uses it for |
| ------------ | ---------- | ---------------- |
| Comment-protected minting: `comment` = `hex(sha256(secret))` or `cp1<pk>`, `commentAllowed: 64`, no comment = no invoice | `/p/cb`, `mints.comment_hash` | the asset's first note id, known before the invoice is paid |
| Wallet-generated outputs `p1`/`p2`, success response `{"status":"OK"}` + `sig`/`sig2` | `/w/cb` | lineage: every rotate names the next note id up front |
| `mintPubkey` on `/w` and the per-note GET, `cs1` certificates | `signing.py`, node `signmessage` (spark: its own seed key) | offline-verifiable cards |
| Replay-safe mutations, burned notes kept as `spent=1` | `burns`, `notes.spent` | one rotate = one chain link, even under retries |
| Lookup without the secret (`?h=`, `?p=cp1<pk>`) | `/w` | resolving a note's card without handling its secret |
| LUD-21 `verify` on mint invoices | `/verify` | the paid invoice as a public receipt |

The delta NORD adds on top:

| # | Change | Where in lnurl-mint | Details |
| - | ------ | ------------------- | ------- |
| 0.1 | Dedicated nostr key, advertised as `nostrPubkey` on `/w` and the per-note GET | `config.py`, `get_withdraw` | §3, NORD-01 |
| 0.2 | Nullable `asset_genesis_id` on `notes`, carried to the output of every rotate | `db.py`, `get_withdraw_callback` | §1 |
| 0.3 | Refuse split and merge when any input is an asset note | `get_withdraw_callback` | §1 |
| 0.4 | `asset` / `artwork` on the withdrawRequest of an asset note | `get_withdraw` | §2 |
| 0.5 | Publish chain events at mint settlement, rotate and melt, never blocking the LNURL response | `_mint_settled_by_comment`, `get_withdraw_callback`, `_melt_settled` | §3 |
| 0.6 | Set import and an asset payLink that binds each paid mint to the next queued instance | new module | §4 |
| 0.7 | Asset notes are `cp1` only: the asset payLink rejects a non-`cp1` comment, `/w/cb` rejects a non-`cp1` `p1` for an asset input | `/p/cb`, `get_withdraw_callback` | §1, NORD-02 |

## 1. The asset column

The mint already tracks `notes.id -> amount_msat` for outstanding
notes, where `id` is the comment hash for a fresh mint, the `p1`/`p2`
value after a mutation, and the hex pubkey for a `cp1` note. Add one nullable column:

```sql
ALTER TABLE notes ADD COLUMN asset_genesis_id TEXT NULL;
```

Lineage is automatic: rotate writes the new hash with the same
`asset_genesis_id`; melt clears the row. Two guards:

- **Split and merge MUST fail** (`{"status":"ERROR"}`) when any involved
  secret has a non-null `asset_genesis_id`. An ordinal is indivisible.
- A note's asset assignment never changes after mint. There is no
  "reattach".
- **Asset notes are `cp1` notes** (NORD-02): an asset mint whose
  `comment` is not `cp1<pk>`, and a rotate of an asset note whose `p1`
  is not `cp1<pk>`, MUST fail. lnurl-mint already certifies every `cp1`
  output (`sig`/`sig2`), so cards are offline-verifiable at no extra cost.

## 2. withdrawRequest additions

For a note whose secret has an asset:

```json
{
  "tag": "withdrawRequest",
  "callback": "...", "k1": "...", "minWithdrawable": 0, "maxWithdrawable": 0,
  "mintPubkey": "<hex>",
  "sig": "cs1<...>",
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

- Identity per NORD-01: a dedicated nostr key, advertised as
  `nostrPubkey` on the withdrawRequest. lnurl-mint certifies notes
  through its node's `signmessage` RPC, which cannot sign nostr events;
  only a backend that holds its signing key (spark) may reuse it. The
  nostr side was prototyped in [lnurlcash/lnurl-mint#1](https://github.com/lnurlcash/lnurl-mint/pull/1) (closed unmerged).
- On **mint settlement** of an asset: publish kind `7600` (genesis) with
  `x`, `url`, `birth` = the invoice's payment hash, `anchor` = its
  `comment` verbatim, `amount`, `lnurl`,
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
`sha256("NORD/own" ‖ pk)`, `pk` the note's current `cp1` key) required on every mutating callback for a
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
4. **One nostr identity, everywhere.** BUD uploads are signed with
   nostr keys. The mint's `nostrPubkey` already signs its events
   (NORD-01); it now also owns its blobs, and the withdrawRequest links
   it to `mintPubkey`. No second
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
  timer, and the four callback operations LUD-25 already defines.
