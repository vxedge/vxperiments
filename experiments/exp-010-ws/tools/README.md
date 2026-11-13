# tools/ — analysis and helpers for this experiment

The campaign, its probe, its metrics and the H2 criteria are in `../main.yaml`. vxedge judges them,
reading exp-001's frozen campaign from this repo's `results/` for H2's other arm:
`vxedge campaign verdict <campaign id> --reference-workspace <this repo>` for a campaign, and
`vxedge results verdict --experiment <this package> --reference-workspace <this repo> <archives>`
offline over archives.

What belongs here is what only this experiment needs beyond that. None yet.
