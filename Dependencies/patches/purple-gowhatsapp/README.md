# purple-gowhatsapp patches

`Dependencies/source` is not under version control, so this patch is the only record in this
repository of what `PurplePlugins/libwhatsmeow.so` was built from.

Base revision: `b618ef56d09f516958f89156cbdec0e9c2b82347` (2026-09-16) of
<https://github.com/hoehermann/purple-gowhatsapp>, branch `whatsmeow`, the last commit before the
1.26.0 release, whose own commit the patch includes. Upstream had merged our PR #273
in August (PNGs travel as image messages, confirmed by the maintainer on Electron, iOS and Android;
WebP is silently swallowed by WhatsApp itself), and the merge of 17 September brought the combined
branch up to this base. Upstream is active, so the patch is expected to be rebased rather than
carried forever. The working checkout also has a remote `knutmann` pointing at
<https://github.com/KnutMann/purple-gowhatsapp>, where the single purpose branches are pushed. The
combined branch these changes live on is `adium-adaptations-v2`. The patch is written with
`git diff b618ef5 adium-adaptations-v2`, one diff rather than a series, because the branch merges
upstream in September and a series cannot carry that merge; applied on the base it reproduces the
tree the plug-in was built from, checked by tree hash on 31 October 2026.

## adium.patch

The sum of a series of commits on the fork's branch, all of them adjustments to what suits a Cocoa frontend rather than corrections to
upstream's own behaviour, with the two plain fixes noted last.

**Four of the commits are meant for upstream.** "Forward incoming receipts and
sent-message ids." and "Emit reactions and message ids as purple signals." exist
as clean branches `receipt-signals` and `reaction-signals` on the upstream base,
prepared as pull requests to hoehermann/purple-gowhatsapp; Adium consumes their
signals in `Plugins/Purple Service/adiumPurpleWhatsApp.m`. Once they are merged
upstream, they leave this patch and the base revision moves forward.

"Fetch the history the phone still remembers." is the third, and it builds on
both of the others, so it can only become a branch of its own once they have
landed. It answers the maintainer's own TODO in `handler.go` and the open
request in upstream issue #263: a conversation coming into being asks the
primary device for the messages before the newest one known, behind the
`fetch-history-on-open` account option. The reactions and delivery state the
phone remembers travel back through the two signals above, which is what lets a
reopened window show its ticks and reaction chips again. The phone answers only
while WhatsApp is running on it, so the option is off by default.

"Retry the group list query instead of dropping the connection." is the fourth, and it stands
alone: the branch `group-list-retry` carries it on upstream's 1.27.0. It is described last.

**Reactions, inline media, voice notes, display names.** The largest of them. Voice notes arrive as
Ogg/Opus, which WebKit will not play, so they are decoded to WAV next to the temporary file and
announced as a link the message view turns into a player. Adium renders media itself, so images are
handed to the conversation instead of being offered as downloads.

**Location messages as Apple Maps links, and no buddies for group identifiers.** A group is a chat,
not a contact, and creating a buddy for one puts a row in the contact list that can never be
messaged sensibly.

**Documents are fetched and announced with a file link** rather than left as an offer to accept.

**Profile pictures at full resolution**, since the list can scale down but cannot invent detail.

**Message cache raised to 500.** The cache is what lets an edit or a reaction find the message it
refers to, and the upstream default is small enough that anything but a brisk conversation loses
the reference.

**Inline media by default.** The test in `gowhatsapp_handle_attachment` compares the option against
INLINE, so the fallback value decides what every account that never touched the setting does.

**Business accounts show their verified name.** They often carry no push name, so the frontend was
left showing the bare JID. whatsmeow delivers the verified name with every message and announces
changes as a BusinessName event; the plugin now listens to the event and lets the verified name
stand in on the message path. Worth offering upstream.

**A sent picture is attributed to the sender, not to the conversation.** This one is a plain fix and
worth offering upstream. The inline echo of an outgoing image passed the transfer's `who` as both
the sender and the conversation. In a one to one chat those are the same string and nothing looks
wrong. In a group chat `who` is the group, so the picture appeared under the group's raw identifier,
`120363...@g.us`, while every other message from the same account showed the account holder's name.
Passing the account name also makes `gowhatsapp_display_text_message` recognise the message as
outgoing, which it decides by comparing the sender against the account.

**A group list that times out no longer takes the account offline.** After login the plugin asks
for the list of joined groups by itself, and when that query ran into whatsmeow's 75 second timeout
the error was reported as fatal. libpurple ranks a fatal error with a wrong password, so Adium
showed the error and never reconnected, although messages could have flowed the whole time: the
list only decides which group chats appear in the contact list. The query is now retried a few
times and then given up on with a warning, the way the participants query has been since upstream's
issue 146, and the list end marker is sent either way so the room list is not left in progress.

**A contact's name survives a restart.** libpurple keeps a buddy's server alias in memory only, and
blist.xml saves the local alias, which this branch leaves to the user. After a restart every buddy
was nameless until the contact sync spoke again, and for a name that had not changed the sync said
nothing, because `gowhatsapp_ensure_buddy_in_blist` compares against the name it recorded. In a
group chat libpurple then seated such a contact under the bare JID, without asking `get_cb_alias`,
which it only does when no buddy exists. The login now hands every buddy its recorded name back
through `purple_blist_server_alias_buddy`, which unlike `purple_serv_got_alias` writes no "is now
known as" line into open conversations. `gowhatsapp_chat_set_participants` is upstream's again: the
branch had passed each participant's resolved name as the third argument of
`purple_conv_chat_add_user`, which is a join notice's extra text, never an alias, so it did nothing.

**A poll vote whose poll is gone says so in Adium's words.** The notice for a vote whose poll has
left the message cache named "this plug-in"; it now names Adium, as the notice about calls does.

## Rebuilding the plugin

There is no build phase for this; it is done by hand, or by `Dependencies/rebuild-whatsmeow.sh`,
which builds, copies the result into PurplePlugins/ and verifies it. By hand it is this.

    cd Dependencies/source/purple-gowhatsapp
    git apply ../../patches/purple-gowhatsapp/adium.patch     # if starting from a fresh checkout
    cmake --build build

Then, and this step is not optional:

    ./Dependencies/patches/purple-gowhatsapp/relink_for_bundle.sh

The script copies the result over `PurplePlugins/libwhatsmeow.so`, rewrites the absolute paths cmake
recorded so everything resolves inside the bundle, signs it, and refuses to finish if any absolute
path remains. Skipping it loads second copies of glib, libpurple and gettext into a process that
already has them, and the failures that follow are confusing out of all proportion to the cause.
