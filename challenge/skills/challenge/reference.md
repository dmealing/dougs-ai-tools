# Challenge: measurements and background

Read this when you are choosing a pair or a budget cap. `SKILL.md` does not need it on every run.

These are aggregate figures from the author's own use of an earlier, unpublished version of the tool, **not a benchmark**. They are one person's questions about a few repositories, judged by one controller, and they are shown so you can set expectations and not so you can rank models. No individual run is identified here.

## Split rates by pairing (snapshot of 2026-10-17)

Only `high`-stakes rows are counted. A **split** here is a row logged `no`. The earlier version counted a `partial` row as agreement, and three rows were logged `partial`, so every rate below is a floor: the true split rate under the current rule, where `partial` counts as a split, is somewhat higher. `challenge-log.sh status` now counts `partial` as a split and shows the interval.

The interval is the 95% Wilson score interval.

| Pairing | Rows | Splits | Split rate | 95% interval | Mean cost per run | Largest |
|---|---|---|---|---|---|---|
| Fable 5.1 + Opus 5 | 56 | 14 | 25% | 15.5–37.7% | $5.34 | $9.12 |
| Fable 5.1 + Opus 5.5 | 4 | 1 | 25% | 4.6–69.9% | $4.84 | $5.90 |
| Opus 4.8 + Opus 5 | 78 | 19 | 24% | 16.2–34.9% | $2.65 | $7.85 |
| Opus 5 + Opus 5 (same model twice) | 6 | 0 | 0% | 0–39.0% | $2.05 | $3.22 |
| **Opus 5.5 + Opus 5 (the default)** | **0** | | | | | |

How to read it:

- **The default pair has no rows.** Nothing here is evidence about Opus 5.5 with Opus 5. Do not quote another pairing's rate as the default's.
- **The Fable pairing split no more often than the cheaper Opus pairings,** and cost about twice as much per run. The intervals overlap heavily, so this is directional, not settled, and a split rate does not measure how useful a split was. It is the reason Fable is opt-in and not the default.
- **The twin row is the control.** Two runs of one model split 0 times in 6, which still allows a true rate up to about 39%. An earlier set of four twin runs, dispatched on the four briefs where the cross-generation pair had split, agreed 4 of 4. If those questions had simply been hard, twins would have split on them too. So those splits looked like the second model seeing it differently, not sampling noise. Only one of the four was a clean replication at the pinned commit; two agreed partly because the repository had moved on and already settled the question. Directional only.
- **A split-only sample cannot rank two pairings.** On a brief where two arms split, a third arm that agrees with one is disagreeing with the other, so two candidate split rates computed from such briefs are forced to sum to about 1 whatever the third arm thinks. Only briefs where the incumbents agreed can give an unbiased rate for a new pairing.
- **Family correlation survives a generation boundary.** In a small replay, a newer model from one family landed on the side of its older sibling, against an Opus. This is a reason to expect a cross-family pair to de-correlate errors more than a cross-generation one, and it is also why two generations of one family should not be counted as two independent voices. At n of 5 it is a hint.

## Why the default is Opus 5.5 with Opus 5

It is the cheapest pair of two current models, so a split cannot be waved away as the older model being weaker. It is also a same-vendor pair, which is the weakest diversity setting: errors are heavily shared inside one vendor, and a pair that is confidently wrong in the same direction is exactly what a challenge exists to catch. A cross-family pair is likely to de-correlate better, at a higher price. This version runs Claude models only, so there is no cross-vendor option.

## Cost

List prices at the time of writing; check the pricing page before relying on them.

| Model | Input per million tokens | Output per million tokens |
|---|---|---|
| Opus 5.5 | $4 | $20 |
| Opus 5 | $5 | $25 |
| Fable 5.1 | $10 | $50 |

- Fable 5.1 costs 2.5 times Opus 5.5 per token.
- A run's cost is two arms plus two differential calls. The differential calls are small, since the model has no tools and reads two answers and a brief.
- The per-arm cap defaults to **$8**, and to **$16** when a Fable model is in the pair. It is a runaway guard, not the expected spend: raising it only moves where an arm is killed. It must not fire asymmetrically by model, because a cap that only ever kills the pricier arm measures the cap and not the models, which is why the Fable default is double. The cap is checked against the CLI's own client-side cost estimate and spend can pass it.
- On a subscription login the same work uses plan quota. Fable usage may bill to usage credits depending on plan, and under `-p` Claude Code bills it without asking.

## Why the differential is its own step

A differential written by the controller that formed the conclusion is the one most likely to find it was right. Three things in the script follow from that:

- **A model outside the pair writes it.** A judge tends to prefer its own family's output; keeping it off both arms' models removes the plainest case.
- **It never sees which model wrote which answer.** Hiding the label removes a real bias. It does not remove style or family recognition, which is why the next point exists.
- **It reads the answers in both orders.** Position bias in model judges is large. If the two passes reach different `AGREEMENT` values, the runner reports `partial` and says the verdict depended on order.

## Model retirement

Defaults go stale. At the time of writing, the retirement floors published for the default models were: Opus 5 not before 2027-07-24, Opus 5.5 not before 2027-09-22 and Fable 5.1 not before 2027-09-01, each with at least 60 days' notice. Review `default_model_a`, `default_model_b` and `default_synth_model` in `challenge-common.sh` at least once a year.

## Replaying a challenge

Every record pins its commit. To re-run a past brief against a newer model, rebuild the snapshot with a depth-limited, single-branch clone, which includes ancestry but no later commits (a later commit message can leak the answer), then run the saved `brief.md` unchanged. Replay is cheaper than running more live challenges, because only the new arm is paid for.
