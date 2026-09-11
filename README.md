# Ordinals on nostr

**Charged bearer assets over LNURLcash. Cards and banknotes, not QR codes.**

An *ordinal on nostr* is a unique, publicly verifiable asset whose value
lives in an [LNURLcash](https://github.com/lnurl/luds/blob/d2f307fabec4154fa44d25d97c4ea673fa1c1914/25.md)
bearer note, whose artwork lives on [Blossom](https://github.com/hzrd149/blossom),
and whose provenance is a hash-linked chain of signed nostr events. No
blockchain, no consensus: the mint that holds the sats already sequences
every transfer - the chain just makes that sequence public and verifiable.

The wallet is not a wallet. It is a **card viewer**: an asset note renders
as its card, artwork fetched from Blossom by hash; a plain value note
renders as a **banknote** of its denomination. Handover happens over
nostr - pick a contact, send - or as a plain `lnurlw://` link. QR codes
are not part of the screen UX (paper is a different medium; printed notes
may carry codes, screens don't have to).

## Specs

| Spec | Contents |
| ------------------------ | ----------------------------------------------------------------- |
| [NORD-01](NORD-01.md) | Asset events: genesis, transfer, confirm, melt. Chain rules. Artwork on Blossom. |
| [NORD-02](NORD-02.md) | LNURLcash binding: asset pointer in `withdrawRequest`, asset notes as LUD-25 Part 2 `cp1` notes, registered mode (P2PK-style owner), nostr handover. |
| [NORD-03](NORD-03.md) | FIPS transport binding: `<npub>.fips` as the mint's canonical address, mirrors, local-first mesh operation. |
| [DEMO-600B](DEMO-600B.md) | The 600B Timelock TCG as the reference deployment: cards, boosters, duels, banknotes. |

Kind numbers and field names are **draft** - placeholders until review.

## Pinned against

These drafts track [LUD-25](https://github.com/lnurl/luds/pull/301) as of
commit [`d2f307f`](https://github.com/lnurl/luds/blob/d2f307fabec4154fa44d25d97c4ea673fa1c1914/25.md) (2026-09-10). "LUD-25" in every document here
means exactly that text, Part 2 included. Checked against the reference
implementations at `lnurlcash/lnurl-mint@f09849c` and
`lnurlcash/lnurl-wallet@f662aef`. When LUD-25 moves, re-pin here first,
then walk the documents.

## The stack

| Piece | Role | Status |
| ------------ | ---------------------------------------------- | ------------------------------------------------ |
| Wallet | card viewer, holds notes, renders cards/banknotes | [lnurlcash/lnurl-wallet](https://github.com/lnurlcash/lnurl-wallet); our fork [`feature/nostr-ordinals`](https://github.com/BIMbeamFLX/lnurl-wallet/tree/feature/nostr-ordinals): 600B skin, note images, `.fips` hosts, adopted artwork |
| Mint | LNURLcash SERVICE + asset table + genesis publisher | to build on [lnurlcash/lnurl-mint](https://github.com/lnurlcash/lnurl-mint); asset-layer prototype [#1](https://github.com/lnurlcash/lnurl-mint/pull/1) closed unmerged (2026-08-08) |
| Blossom | artwork by sha256, any server, easy file hosting | any BUD-01/02 server |
| Relay | carries the asset chains | any relay; own relay for curation |
| [FIPS](https://fips.network) | optional transport: identity-addressed mesh (`<npub>.fips`), works over LAN/BLE/internet | supported in code, clearnet default for now |

Everything here is deliberately **mint-agnostic**: any LNURLcash mint can
implement NORD-02 and issue assets; any wallet can render them from the
public chain. Cashu mints can bridge later via the NIP-60/61 patterns this
design borrows from (P2PK ownership, transfer-as-event).

## What it borrows

- **LNURLcash (dni)** - the value rail: k1 is the asset, rotate is the
  transfer primitive, mint signatures make notes offline-verifiable.
- **Cashu NUT-11 / NIP-61** - registered ownership: an asset locked to an
  npub, transfers requiring the owner's signature, "the payment itself is
  the receipt".
- **Ordinals** - the mental model: genesis id = inscription id, chain of
  custody, artwork immutably addressed.

## License

MIT
