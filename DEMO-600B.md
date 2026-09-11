# DEMO-600B: the reference deployment

`status: draft` `collection tag: 600b`

The 600B Timelock TCG is the demo that exercises every corner of NORD:
unique charged cards, plain banknotes, bearer trades, registered
collections, and death by melt. Card data and rules already exist in
`TCG600nap`; art direction follows the 600B design system (orange on
volcanic, Impact caps, sharp corners).

## Two kinds of paper

The viewer renders every note as the object it is - no QR codes on
screen, no hex strings above the fold:

- **Banknote** - a plain value note. Denomination large in Impact
  (210 sats), mint name, series, the 600 glyph, guilloche in the fire
  palette. Selecting it offers: send (contact list -> nostr handover),
  melt, split, combine.
- **Card** - an asset note. Full-bleed artwork from Blossom (`x`-verified),
  name, affinity (P/B/K/S/T), set and card number from the genesis
  `content` JSON, charge shown as the card's "life". A `signed` stamp
  when the LUD-25 signature verifies, an `owner` stamp when registered.
  Send and melt only - cards refuse split/merge (NORD-02), and melting
  shows exactly what it is: **the card dies and pays out its charge**.

## Genesis content schema (`t = 600b`)

```json
{
  "name": "Network Storm",
  "set": "E1",
  "number": "042/120",
  "affinity": "K",
  "rarity": "rare",
  "rules": "<card text, verbatim from the locked E1 set>",
  "artist": "600B council"
}
```

The card pipeline (`cards/e1-cards.json` -> Blossom upload -> genesis
per printed card) is the mint's set-import step: one blob per artwork,
one 7600 per physical card instance, `birth` bound to the booster
payment that mints it.

## Flows to demo

1. **Booster** - 210 sats, one LUD-06 invoice: three random cards at
   60 sats charge each, 30 sats change as a banknote. The mint
   pre-commits the cards, publishes their geneses on settlement, the
   buyer's viewer fans them out. Pure LUD-25 minting, three times.
2. **Fastplay starters** - two fixed 40-card decks, SIGNAL (Signal
   affinity) and STONE (Power affinity), derived - not curated - from
   the rulebook's recommended-first-deck shape over the real E1 pool in
   collector-number order. 600 sats each, 40 x 15 priced to the sat, no
   change. Buy both, hand one over, duel.
3. **Trade** - bearer handover of two cards in opposite directions via
   nostr DM (gift-wrapped 7604s). No trust gained, none needed: both
   sides rotate on receive, both chains record the custody hop.
4. **Duel stake** - each player sends a banknote into a 2-of-2-style
   arrangement the simple way: both stake to the mint-run table npub
   (registered transfers), winner gets both back. The mint is already
   trusted with every charge; the table is one more row in its book.
5. **Collection page** - a nostr client (or the viewer's public mode)
   renders any npub's registered cards straight from the chains: relay
   filter on kinds 7601/7602 with `p` = npub, artwork from Blossom.
   A public trophy shelf, zero backend.
6. **Death** - melt a card on stage. The chain closes with a 7603, the
   viewer greys the artwork, the sats land in a plain banknote. Scarcity
   you can watch.

## Why this demo sells the spec

Every piece demonstrates a property, not a feature: the booster shows
mint-agnostic issuance, the trade shows bearer privacy, the stake shows
registered custody, the shelf shows public verifiability, the melt shows
that charge is real. A conference table, two phones, one projector - no
step needs a QR code, an account, or an explanation longer than "it's a
banknote that knows what it is".
