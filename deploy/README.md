# NORD prototype deployment

One box, one compose file, our forks: the mint with the asset layer
([lnurlcash/lnurl-mint#1](https://github.com/lnurlcash/lnurl-mint/pull/1), closed unmerged, built
straight from `BIMbeamFLX/lnurl-mint#feature/nord-assets`), lnd on
neutrino (no bitcoind - header sync only, minutes not days), a strfry
relay for the asset chains, caddy for TLS + forwarded headers + static
Blossom serving. Fits the smallest Hetzner VPS (2 GB RAM is plenty).

> This prototype predates the LUD-25 pin (see the top-level README) and
> still speaks the July draft. It is not updated to the pinned spec yet.

**Real sats run through this.** Keep `MAX_SENDABLE_MSAT` tight, fund the
node with pocket money, and remember melts pay routing fees out of the
mint's pocket. The wallet seed is the only backup that matters.

## Bring-up

```sh
# 0. DNS first: A records for mint.<domain>, relay.<domain>,
#    blossom.<domain> -> this box (caddy needs them to get certificates)

git clone https://github.com/BIMbeamFLX/nostr-ordinals && cd nostr-ordinals/deploy
cp .env.example .env   # fill in DOMAIN, BASE_URL, NOSTR_SECRET_KEY (openssl rand -hex 32), NOSTR_RELAYS

docker compose up -d

# 1. one-time: create the lnd wallet (WRITE THE SEED DOWN), then store
#    the unlock password so restarts are unattended
docker compose exec lnd lncli create
docker compose exec lnd sh -c 'echo "<wallet password>" > /root/.lnd/unlock.txt'
docker compose restart lnd mint

# 2. fund the node (small!) and open one outbound channel for melts -
#    an unfunded node can mint (invoices settle inbound) but not melt
docker compose exec lnd lncli newaddress p2tr

# 3. queue the 600B fastplay starters (80 instances, 15 sats each)
docker compose cp set-600b-starters.json mint:/tmp/set.json
docker compose exec mint python -m lnurl_mint.assets import /tmp/set.json
```

## Smoke test

1. `https://mint.<domain>/` shows the one-pager with node info.
2. Any LNURLcash wallet (e.g. [dni.github.io/lnurl-wallet](https://dni.github.io/lnurl-wallet/), or our
   [cardviewer fork](https://github.com/BIMbeamFLX/lnurl-wallet/tree/feature/nostr-ordinals)): mint at
   `mint@mint.<domain>` for **15 000 msat exactly** - the note that comes
   back IS a starter card: its withdrawRequest carries
   `asset: [genesis id, wss://relay.<domain>]` and `nostrPubkey`.
3. Watch the chain: `websocat wss://relay.<domain>` then
   `["REQ","c",{"kinds":[7600,7601,7603]}]` - the genesis is there;
   rotate the note and the transfer follows.
4. Melt it back to any invoice of exactly its value - the 7603 closes
   the chain. The card died and paid out. That is the whole protocol.

## Notes

- **Artwork**: drop files named by their sha256 into `./blossom/` and
  they serve at `https://blossom.<domain>/<sha256>` with immutable
  caching and open CORS. The current starter set ships without artwork
  fields (the card text is the genesis content); a set with art is a
  re-import away - new instances, new geneses, the chain doesn't mind.
- **alflx instead of Hetzner**: same compose file; for public reach
  without port-forwarding, `tailscale funnel` in front of caddy's port
  (or run caddy on the funnel port directly). DNS then points at the
  ts.net name instead.
- **Booster mechanic** (one payment -> N cards) needs mint-side
  multi-note minting that doesn't exist yet - v1 sells singles: pay 15
  sats, get the next queued card. The demo's booster stays simulated
  until then.
- **Write policy**: strfry accepts everything for the prototype; before
  anything public matters, lock `writePolicy` to the mint's
  `nostrPubkey`.
