# NORD-01: Asset events

`author: FLX` `status: draft` `requires: LUD-25 LNURLcash @ d2f307f`

An **asset** is a unique digital object - a trading card, a ticket, a
numbered banknote - whose charge (sats) is held by an LNURLcash SERVICE
("the mint") and whose existence, artwork and provenance are public,
signed nostr events. The asset is identified by the event id of its
**genesis event**; every later event about it links back to that id,
forming a per-asset hash chain.

There is no consensus layer and none is needed: the mint already decides
which bearer secret is outstanding (every rotate/split/merge burns and
mints secrets, first-presented-first-served). The chain does not *create*
that authority, it *publishes* it - making issuance, custody and
destruction verifiable by anyone with a relay connection.

## Identity: the mint on nostr

A mint that issues assets MUST have a nostr identity, advertised as
`nostrPubkey` (x-only hex) in its `withdrawRequest` (NORD-02).

The clean case: a mint that holds its own LNURLcash signing key SHOULD
use that same keypair - `nostrPubkey == x(mintPubkey)` - one key, two
protocols, zero trust setup.

The delegated case (the reference implementation's reality): a mint
whose note signatures go through its funding node's `signmessage` RPC
never holds that key, and no such RPC can produce the raw BIP-340
signature a nostr event needs. Such a mint uses a **dedicated** nostr
key. The two identities are then linked where wallets already look:
the same `withdrawRequest` advertises both `mintPubkey` and
`nostrPubkey`, and every genesis carries the mint's `lnurl` tag - so a
wallet that trusts the mint's endpoint learns both keys from it in one
authenticated round trip, and chain events verify against `nostrPubkey`
wherever this document says "the mint's" key.

## Genesis - kind `7600`

Published by the mint when an asset is born (see NORD-02 for the minting
flow). Signed by the mint. Immutable; there is no edit and no
replaceability - a wrong genesis is melted and reissued.

```json
{
  "kind": 7600,
  "pubkey": "<x(mintPubkey), hex>",
  "tags": [
    ["x", "<sha256 of the artwork blob, hex>"],
    ["url", "<Blossom URL hint>"],
    ["url", "<another Blossom URL hint>"],
    ["birth", "<payment_hash of the minting invoice, hex>"],
    ["amount", "<msat charged at birth>"],
    ["lnurl", "<the mint's withdraw endpoint, LUD-17 form>"],
    ["t", "<collection tag, e.g. 600b>"]
  ],
  "content": "<asset metadata, JSON - schema is collection-defined>"
}
```

- The **asset id** is this event's id.
- `x` + `url`: the artwork, content-addressed. Clients MUST verify the
  sha256 of a fetched blob against `x` and MUST NOT render a mismatch.
  `url` entries are hints, not authorities - any Blossom server that has
  the blob is as good as any other.
- `birth` anchors the asset to the Lightning payment that minted it: it
  is the payment hash of the minting invoice, i.e. `sha256(k1_0)` of the
  asset's first bearer secret (LUD-25: the preimage is the secret). The
  paid invoice is a receipt anyone can check against this tag.
- `amount` is the charge at birth. The current charge is whatever the
  mint reports for the asset's current secret; a melted asset's charge is
  zero. Genesis states history, not present.
- `content` is free-form JSON. NORD-01 does not define asset semantics -
  a card game, a ticket system and a numbered-banknote series will each
  have their own schema, keyed by the `t` collection tag.

## Transfer - kind `7601`

Records a change of custody. Two authorships, one per custody mode (see
NORD-02 for how each is executed against the mint):

- **Bearer handover** (default): authored by **the mint**, after it
  executed the rotate that moved the note. Tags `p` the receiving npub
  when the recipient chose to disclose one, otherwise the transfer is
  recorded ownerless (custody moved, holder anonymous - exactly a
  banknote changing pockets).
- **Registered transfer**: authored by **the current owner** (the npub
  the chain currently assigns the asset to), naming the next owner in
  `p`. Only valid once confirmed by the mint (kind `7602`).

```json
{
  "kind": 7601,
  "pubkey": "<mint | current owner>",
  "tags": [
    ["e", "<genesis id>", "<relay hint>", "genesis"],
    ["e", "<previous chain event id>", "<relay hint>", "prev"],
    ["p", "<next owner npub, hex>"]
  ],
  "content": ""
}
```

## Confirm - kind `7602`

The mint's countersignature on a registered transfer it has executed:

```json
{
  "kind": 7602,
  "pubkey": "<x(mintPubkey)>",
  "tags": [
    ["e", "<genesis id>", "<relay hint>", "genesis"],
    ["e", "<the 7601 being confirmed>", "<relay hint>", "prev"]
  ],
  "content": ""
}
```

A registered `7601` without a matching mint `7602` is a proposal, not a
link. Mint-authored transfers need no confirm - mint authorship is the
confirmation.

## Melt - kind `7603`

Authored by the mint when the asset's note is melted (paid out) or the
asset is otherwise retired. Terminal: a chain with a melt at its tip is
closed, and clients SHOULD render the asset as discharged (the card is
dead, the banknote is void). Same tag shape as `7602`.

## Chain validation

A client walking an asset's chain (relay filter: `#e` = genesis id,
kinds 7601-7603) MUST accept a link only if:

1. its `genesis` tag matches, and its `prev` tag names the current tip;
2. it is authored by the mint (`pubkey == x(mintPubkey)`), **or** it is a
   `7601` authored by the current registered owner and a mint `7602`
   confirms it;
3. no earlier accepted link already extends the same tip (the mint MUST
   NOT sign two children of one tip; if it ever does, the chain is
   equivocated and clients MUST flag the asset - this is the one trust
   assumption, see below).

## What this does and does not prove

The chain proves **what the mint attested, in order**. It does not make
the mint honest: the mint can refuse to honor a note, misstate a charge,
or (detectably, per rule 3) equivocate. Holding the charge was always
custodial trust in the mint - NORD adds no trust and removes none, it
makes the mint's story public, permanent and checkable. Bearer-mode
privacy is preserved: a holder who never discloses an npub appears
nowhere.

## Security considerations

- Artwork MUST be verified against `x` before rendering; a Blossom URL
  is transport, never truth.
- Clients MUST treat `content` JSON as untrusted input.
- A mint SHOULD publish chain events to at least two independent relays;
  clients SHOULD query more than one.
- Kind numbers `7600-7604` are provisional until NIP review.
