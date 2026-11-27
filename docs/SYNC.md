# Syncing your devices

Optional. Without it Crocuta works normally, just on one device at a time.

Sync keeps **likes, playlists, recently played and stats** aligned across
your devices, through a small Google Apps Script that writes one JSON file
to **your own** Google Drive. Nothing to pay for, no third-party server,
nothing to maintain.

## Turning it on

Everyone uses their own script on their own Drive: builds contain no
addresses or secrets.

1. Open [script.google.com](https://script.google.com) and create a new
   project.
2. Paste the contents of [`tool/crocuta_sync.gs`](../tool/crocuta_sync.gs),
   without changing anything.
3. *Deploy → New deployment → Web app*, with **Execute as: Me** and **Who
   has access: Anyone**. Google asks you to authorize Drive access: it's
   your script, on your account.
4. Copy the deployment URL (it ends in `/exec`).
5. In Crocuta: **Library → Settings → Set Up Sync**, and paste the URL.

The app generates a long random secret, and the script adopts the first
one it receives.

**On your other devices:** tap **Copy Setup Code** on the first one, then
**Set Up Sync** on the next and paste the code. It carries the address and
the secret together. The same secret lets your devices recognize each other
in **Crocuta Connect**.

Sync runs on its own at launch and when the app stops; the badge in
Library says when it last succeeded and syncs right away when tapped.

## Good to know

**Keep the setup code to yourself.** "Who has access: Anyone" is required
because the app doesn't sign in to Google, so the protection is the
secrecy of the URL plus the shared secret. It isn't real authentication:
anyone with both could read your library. Fine for likes and listening
history, not for anything else.

**Deletions are recorded**, not just absent. Otherwise a device that fell
behind would push back what you removed on another one, and a deleted like
would come back on its own. For every entry, the most recent of "added"
and "removed" wins.

**Stats take the highest value, not the sum.** Summing would count
already-synced listens twice, and the numbers would grow on every pass. The
maximum undercounts only when you play the same song on two devices
without syncing in between, and that error doesn't accumulate.

**For a playlist, the most recent version wins, whole.** Merging the songs
of two different versions would produce an order you never chose.
