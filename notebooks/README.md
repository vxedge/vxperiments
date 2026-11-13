# notebooks

Every experiment's verdict now comes from vxedge, judging the criteria in its package's
`main.yaml`. One analysis script is left, because one published verdict cannot be judged that way
yet.

| File | Why it stays |
|---|---|
| `analyze_exp010.py` | exp-010's published H2 verdict. Its frozen archives hold probe summaries, not samples, so vxedge's verdict engine cannot judge them. This script is the only check of that verdict |
| `cold_start.py` | Imported by `analyze_exp010.py` |
| `check-exp010.sh` | Downloads exp-010 and exp-001 from the pinned Zenodo record, runs `analyze_exp010.py`, and requires the published `results/exp-010/` summary and its H2 verdict. CI runs it |

This folder is removed once the `vxedge/exp-010` package has run live and its verdict comes from
vxedge, like every other experiment's.
