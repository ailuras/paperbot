# Scoring

PaperDaily combines venue reputation and citation impact.

## Venue Tiers

The default configuration uses three tiers:

- Tier 1: 20 points for core/top venues in the configured research area.
- Tier 2: 10 points for strong specialized venues.
- Tier 3: 5 points for relevant secondary venues.

Venue matching uses acronym boundaries and case-insensitive phrase matching. The tier list is intentionally configurable because research priorities differ by user and domain.

## Citation Score

The default citation formula uses diminishing returns:

- Citations 0-10: 1 point each.
- Citations 11-50: 0.5 points each.
- Citations 51+: 0.2 points each.
- Citation score is capped at 40 points by default.

This prevents very highly cited broad-topic papers from overwhelming newer or more specialized papers.

## Final Score

```text
score = venue_tier_points + citation_points
```

The recommendation system treats `high_score_threshold` as the cutoff for quality-priority selection.
