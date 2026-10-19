# Why things are the way they are

One file per decision that somebody could reasonably make differently, or trip
over, and that would otherwise have to be argued out again from scratch. The
rules themselves are in CLAUDE.md; this is the reasoning behind them, what was
considered and rejected, and what each choice costs.

Each page says four things:

* **Decision.** What holds today. Rewritten when it changes.
* **Why.** The reasoning, and what was turned down. The rejected option is
  usually the more useful half: it is the one somebody will propose again.
* **What it costs.** The consequence somebody trips over, written down so they
  do not have to find it the hard way.
* **Verified.** A date and the measurement. Not "this is true" but "this was
  checked on this day, this way, and here is the command".

What does not belong here: status, plans, todo lists, or anything that is true
this month and may not be next. That is what docs/ should hold, and it is not in
the repository on purpose; see not-publishing-working-notes.md.

A decision that turns out to rest on a reason that no longer holds is not
deleted. The reason is corrected and the page says so, because the correction
is the interesting part.
