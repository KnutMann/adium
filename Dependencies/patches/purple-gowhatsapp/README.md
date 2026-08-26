# purple-gowhatsapp patches

`Dependencies/source` is not under version control, so this patch is the only record in this
repository of what `PurplePlugins/libwhatsmeow.so` was built from.

Base revision: `c58fcbac9aa7210ce08cf12ef3442932730ec312` (2026-08-19) of
<https://github.com/hoehermann/purple-gowhatsapp>, branch `whatsmeow`; that revision is upstream's merge of our PR #273 (PNGs travel as image
messages, confirmed by the maintainer on Electron, iOS and Android; WebP is silently swallowed
by WhatsApp itself). Upstream is active, so the
patch is expected to be rebased rather than carried forever. The working checkout also has a remote
`knutmann` pointing at <https://github.com/KnutMann/purple-gowhatsapp>, where the earlier single
purpose branches were pushed. The combined branch these changes now live on is local only.

## adium.patch

A series of commits (git counts them, this text will not), all of them adjustments to what suits a Cocoa frontend rather than corrections to
upstream's own behaviour, with one exception noted last.

**Three of the commits are meant for upstream.** "Forward incoming receipts and
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

## Rebuilding the plugin

There is no build phase for this; it is done by hand.

    cd Dependencies/source/purple-gowhatsapp
    git apply ../../patches/purple-gowhatsapp/adium.patch     # if starting from a fresh checkout
    cmake --build build

Then, and this step is not optional:

    ./Dependencies/patches/purple-gowhatsapp/relink_for_bundle.sh

The script copies the result over `PurplePlugins/libwhatsmeow.so`, rewrites the absolute paths cmake
recorded so everything resolves inside the bundle, signs it, and refuses to finish if any absolute
path remains. Skipping it loads second copies of glib, libpurple and gettext into a process that
already has them, and the failures that follow are confusing out of all proportion to the cause.
