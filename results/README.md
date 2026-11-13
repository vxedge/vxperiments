# results/

The frozen record of every published campaign and gate run. Frozen data is never regenerated, and a
superseded campaign stays beside the one that replaced it.

- **Summaries.** `*-summary.md` and `*-summary.csv` per campaign, with the sha256 of the input
  that produced them. Every number published from them is registered in
  [`docs/FACTS.md`](https://github.com/vxedge/docs/blob/main/FACTS.md).
- **Frozen campaign records.** `<exp>/campaign.json` lists each archive of a frozen campaign, the
  trial it is, and its sha256, so vxAPI can judge or compare against it
  (`--reference-workspace <this repo>`). exp-001's is the reference H2 reads.
- **Gate and functional runs.** A folder per run holding its README, its transcript or step
  output, and the harness it used, as committed text.

Run archives are not committed. The published ones are the Zenodo dataset
[10.5281/zenodo.23804197](https://doi.org/10.5281/zenodo.23804197) (all versions); version
2026-11-v2 is [10.5281/zenodo.24192950](https://doi.org/10.5281/zenodo.24192950), mirrored as the
GitHub release
[`archives-2026-11-v2`](https://github.com/vxedge/vxarchives/releases/tag/archives-2026-11-v2) of
vxedge/vxarchives. A campaign run from a package writes its archives, `campaign.json` and
`verdict.json` under `results/<campaign id>/` in the package's folder by default.

Verdicts come from vxedge judging a package's criteria over archives:
[`scripts/verdict-parity.sh --fetch`](../scripts/verdict-parity.sh) re-judges every published
dataset that holds samples and requires its published verdict. exp-010's H2 is the one exception,
checked by `notebooks/analyze_exp010.py` because its archives hold summaries only
([`notebooks/README.md`](../notebooks/README.md)).

Some READMEs here describe how a past result was produced with the bash runners and analysis
notebooks the packages replaced. Their links point at the
[v0.2.1 tag](https://github.com/vxedge/vxperiments/tree/v0.2.1), the last release that has them.
