"""Convert the demo's starters.json (600.wtf repo, derived from the E1
rulebook - see its _derivation field) into lnurl-mint's asset import
format: one queued instance per physical card, 15 000 msat... no - 15
sats = 15 000 msat each, 40 cards x 15 sats = 600 sats per starter.

    py make_set.py path/to/starters.json set-600b-starters.json
    # then on the mint box:
    uv run python -m lnurl_mint.assets import set-600b-starters.json

Artwork fields are left unset until the blossom host carries the blobs -
genesis events then carry the card text as content, artwork follows in a
later set (the chain doesn't mind: genesis is immutable per instance,
new instances get new geneses)."""

import json
import sys

STARTER_CARD_MSAT = 15_000


def main(path: str, out_path: str) -> None:
    with open(path, encoding="utf-8") as handle:
        starters = json.load(handle)["starters"]
    assets = []
    for starter in starters.values():
        set_name = f"FASTPLAY {starter['label']}"
        for card in starter["deck"]:
            assets.append(
                {
                    "content": {
                        "id": card["id"],
                        "name": card["name"],
                        "set": set_name,
                        "type": card["type"],
                        "cost": card["cost"],
                        "rarity": card["rarity"],
                        "affinity": card["affinity"],
                        "text": card["text"],
                    },
                    "amount_msat": STARTER_CARD_MSAT,
                    "collection": "600b",
                    "count": card["count"],
                }
            )
    # explicit utf-8 file output - a stdout redirect on Windows writes the
    # console codepage and mangles anything past ASCII
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump({"assets": assets}, out, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
