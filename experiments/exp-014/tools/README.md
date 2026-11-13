# tools/ — analysis and helpers for this experiment

The campaign's arms, its probe, its metrics and the hop rule are in `../main.yaml`. vxedge judges them:
`vxedge campaign verdict <campaign id>` for a campaign, and
`vxedge results verdict --experiment <this package> <archives>` offline over archives.

What belongs here is what only this experiment needs beyond that. None yet.
