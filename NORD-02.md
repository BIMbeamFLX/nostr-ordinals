# NORD-02: LNURLcash binding

`author: FLX` `status: draft` `requires: LUD-25 LNURLcash @ d2f307f, NORD-01`

NORD-01 defines what an asset *is*; this document defines how a mint
carries one on plain LNURLcash, and how custody moves without a QR code
ever hitting a screen. Everything here is additive: a WALLET that knows
none of it sees ordinary withdraw links and can cash them out (LUD-03);
a SERVICE that implements none of it is simply a mint without assets.

## The asset table

An asset's bearer secret changes constantly (every rotate, split input,
merge input burns one and mints another). The mint MUST track which
outstanding note currently *is* which asset - the same bookkeeping it
already does for note values, one column wider:

```
note_id -> (value_msat, asset_genesis_id | NULL)
```

A plain value note has `NULL` there and renders as a banknote; a note
with a genesis id is that asset. Split semantics: an asset note MUST NOT
be split (an ordinal is indivisible); the mint MUST reject `amount` on
its callback. Merge across asset notes MUST likewise be rejected. Plain
value notes split and merge as ever.

## Asset notes are Part 2 notes

An asset note MUST be a LUD-25 Part 2 `cp1` note, from mint to melt:

- **Mint.** The asset payLink MUST reject a mint whose `comment` is not
  `cp1<pk>`. A genesis `anchor` (NORD-01) is therefore always a `cp1`
  value, and `note_id` above is that pubkey.
- **Rotate.** The mint MUST reject a rotate of an asset note whose `p1`
  is not `cp1<pk'>`. (Split and merge are refused anyway.)
- **Certificate.** The withdrawRequest of an asset note MUST carry
  LUD-25's `sig` (`cs1`), and the note travels as
  `lnurlw://...?k1=ck1<...>&amount=<msat>&sig=cs1<...>`.

Why: cards change hands person to person, often offline, and a
counterfeit card is the one fraud collectors actually care about. Part 2
gives every asset note an issuance certificate that verifies against
`mintPubkey` with no NORD-specific crypto, and a WALLET recovers its
cards from its seed (LUD-25 Seed & derivation). Plain value notes stay
free to use Part 1.

## withdrawRequest additions

```json
{
  "tag": "withdrawRequest",
  "...": "...",
  "mintPubkey": "<33-byte compressed secp256k1, hex>",
  "sig": "<cs1<...>: LUD-25 certificate, required on asset notes>",
  "nostrPubkey": "<x-only nostr pubkey the chain events verify against>",
  "asset": ["<genesis event id, hex>", "<relay hint>"],
  "artwork": ["<blob url>", "<sha256 of the blob, hex>"],
  "owner": "<npub of registered owner, hex, optional>"
}
```

- `asset` is the pointer that makes any wallet a card viewer: resolve
  the genesis event, fetch the artwork by its `x` hash from Blossom,
  verify, render. Absent on plain notes.
- `artwork` mirrors the genesis `url`/`x` tags verbatim, so a wallet
  without a nostr client can render the card in one round trip: fetch,
  verify sha256, display. A mint serving bytes here that don't match
  the genesis commitment is equivocating, and clients that later
  resolve the chain will surface it.
- `owner` is present iff the asset is in **registered mode** (below).

## Minting an asset

The LUD-25 minting flow, unchanged, plus one publication:

```mermaid
sequenceDiagram
  participant W as WALLET
  participant S as SERVICE (mint)
  participant B as Blossom
  participant R as Relay
  S->>B: upload artwork (once, at set import)
  W->>S: LUD-06 payRequest, comment = id of k1_0, pays invoice
  Note over W: holds k1_0, the note the mint credits under that comment
  S->>R: publish genesis (kind 7600, birth = payment_hash, anchor = comment)
  W->>S: GET withdrawLink?k1=k1_0 (verify), rotate
  Note over W: holds asset note, renders card from Blossom
```

The minting wallet finds its genesis by `anchor` - the comment it chose
itself - and can confirm the asset is *its* before it even rotates.
`birth` lets everyone else tie that genesis to a real, paid invoice.

## Moving custody without QR codes

Three transports, all producing the NORD-01 chain events. On-screen UX
is contact-first: pick an npub, send. (Printed notes are a different
medium and out of scope here.)

### 1. Nostr handover (bearer)

The sender rotates (fresh secret only they know), then sends the note
URL to the recipient as a NIP-59 gift-wrapped rumor, kind `7604`:

```json
{
  "kind": 7604,
  "tags": [["e", "<genesis id>", "<relay>", "genesis"]],
  "content": "<the note URL, lnurlw://...?k1=ck1...&amount=...&sig=cs1...>"
}
```

The recipient's wallet unwraps, stores, and immediately rotates (LUD-25
receive hygiene - the sender still knows the wrapped `ck1`). The mint
records the bearer transfer (NORD-01 kind `7601`, mint-authored; `p`
only if the recipient disclosed an npub at rotate time via `claimer`,
below). Wrapped in NIP-59, nothing on relays links sender, recipient and
asset publicly in bearer mode.

### 2. Registered transfer

No secret travels at all. The current owner signs a NORD-01 `7601`
naming the next owner and presents it to the mint's callback; the mint
rotates internally, points `owner` at the new npub, publishes the `7602`
confirm, and the recipient's viewer sees the card arrive by watching the
chain. The nutzap pattern, for whole assets.

### 3. Link

`lnurlw://...` as text - message, mail, sticker under a scratch layer.
Still no QR on screen.

## Registered mode

Ports Cashu NUT-11's idea onto LNURLcash. When an asset is registered,
the mint MUST require, on every mutating callback for its secret, an
additional parameter:

```
callback?k1=ck1<...>&owner_sig=<schnorr sig, hex>
```

`owner_sig` is a BIP-340 signature by the registered `owner` npub over
`sha256("NORD/own" || pk)`, where `pk` is the asset note's current
`cp1` key. Possession of the `ck1` alone no longer moves the asset - a leaked or shoulder-surfed note is inert without the
owner's nostr key.

Callback operations on registered assets:

| Request | Result |
| ----------------------------------------------- | ----------------------------------------------- |
| `?k1=X&owner_sig=..` | rotate, owner unchanged |
| `?k1=X&owner_sig=..&transfer=<7601 event id>` | execute registered transfer, publish `7602` |
| `?k1=X&owner_sig=..&register=<npub>` | enter registered mode / change owner |
| `?k1=X&owner_sig=..&release=1` | leave registered mode, back to bearer |
| `?k1=X&claimer=<npub>` (bearer only) | rotate; record `p` in the mint-authored `7601` |

Entering registered mode from bearer needs only `register=` (whoever
holds the secret is the owner - that is what bearer means). A mint MUST
reject `pr` (melt) on registered assets without `owner_sig`.

## Backward compatibility

A legacy WALLET given an asset note sees a valid LUD-03 withdraw link
(`k1` is opaque to it) and can melt it - the asset discharges, the mint publishes the NORD-01
melt, the card dies. That is not a flaw; it is what bearer value means.
A Part-1-only LNURLcash WALLET can melt it too, but cannot rotate it:
the mint refuses a plain-hash output for an asset. Registered mode
exists precisely for holders who want the opposite trade-off. A legacy SERVICE ignores every parameter above and no chain
exists - notes are just notes.

## Security considerations

- The mint MUST NOT accept a `7601` whose `prev` is not the current
  chain tip (stale or replayed transfers).
- `owner_sig` commits to the *current* note key, so a captured signature
  dies with the rotate it authorized.
- A mint SHOULD rate-limit `claimer`/`register` npub disclosure to
  mitigate chain-analysis spam of bearer assets.
- Asset notes MUST refuse split/merge server-side; a client should not
  even offer it.
