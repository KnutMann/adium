# The working notes are not in the repository

**Decision.** `docs/` is in `.gitignore` and nothing under it is committed. It
holds the modernisation roadmap, the fork comparisons and the capability matrix:
internal notes about what is half finished.

**Why.** They are the author's own direction while it is still being worked out,
and somebody pulling the code should not be making decisions about their own work
based on a plan that is still moving. A roadmap in a repository reads as a
commitment to anybody who finds it, and it is not one. It should not guide other
people.

That is a decision about *status*, not about openness. This folder exists because
the opposite case is also true: a decision that has settled is worth writing down
exactly so that nobody has to re-derive it or argue it out again. The line is
whether a sentence will still be true next month.

**What it costs, and the way it went wrong once.** It was decided on 17 August
2026 and the commit that carried it out said only "Remove ignored documentation
artifacts", with no reason. Two days later another session read that silence as an
accident, narrowed the ignore rule and brought the files back, and they sat in
public for two months until somebody noticed. Commit `c034def91` put them out
again, this time with the reason in the message.

The lesson generalises past this one case: a removal without a stated reason
reads as a mistake, and the next person will undo it. If a decision is worth
making it is worth a paragraph.

**What this means for a contributor.** Do not un-ignore `docs/` and do not commit
anything in it for now. Documentation that belongs in public goes in `README.md`,
in a `CLAUDE.md`, or here.

**Verified** 19 October 2026: `.gitignore` line 13 is `docs/`, and `git ls-files
docs` returns nothing.
