# An early protocol is not offered until somebody asks for it

**Decision.** A service descriptor can carry `Experimental`, and a service so
marked stays out of every service menu until a preference is set:

    defaults write com.adiumX.adiumX AIShowExperimentalServices -bool YES

This is a general mechanism, not a judgement about one protocol. Matrix is the
first service to use it and will not be the last; anything that works but is
plainly early goes in the same way.

**Why.** A protocol can be genuinely useful and still be rough: no password
sign-in, a device that does not verify itself, no media, a history that logs
twice. Somebody who came to try that protocol will live with all of it happily.
Somebody who opened the account list to add a Jabber account did not ask to meet
it, and they would judge the whole application by the roughest thing they saw.
The two audiences want opposite things from the same build, and a preference is
how both get what they want.

**What it costs.** Almost nothing, because the hook was already there.
`AIService` has carried `isHidden` since long before this and nothing ever
overrode it, and `AIServiceMenu` is the single path by which a service is offered
anywhere: the account list, the setup assistant, adding a contact, adding a
bookmark. One override in `AIPurpleGenericService` covers all four.

The distinction that matters: it hides the offer, not the service. An account
already configured keeps working, keeps connecting and keeps its conversations
whatever the preference says, so nobody testing an early protocol loses it at the
next launch.

**How a service leaves this state.** The key comes out of its descriptor row when
the gaps that put it there are closed. For Matrix today that means sign-in
without a token from another client, a device that verifies itself, and a
reopened room that does not log its history twice.

**Verified** 19 October 2026: the `Experimental` key is in the descriptor and
`isHidden` in `AIPurpleGenericService.m` reads it.
