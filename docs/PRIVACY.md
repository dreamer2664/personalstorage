# Privacy

**Your notes stay on your device.** There is no account, no server, no analytics and no advertising.

## Where data lives

* Notes, tasks, tags, vectors and the graph are in a SQLite database in the app's private storage.
* Photos you attach are copied into the app's private `media/` folder.
* The optional cloud API key is stored with the platform secure storage (Keychain / Keystore), never in
  preferences or in the database.
* Android: `allowBackup="false"`. iOS: the app's Documents are part of device backups according to your
  iCloud/iTunes backup settings.
* **Settings -> Delete all data** wipes the database; deleted notes are also purged after 30 days.

## When the network is used

| Feature | What is sent | Default | Control |
|---|---|---|---|
| **Link previews** | An HTTP GET to the URL you saved, to read its title/description | On | Settings -> "Fetch link previews" |
| **Cloud embeddings** | Note text, to the OpenAI-compatible endpoint *you* configure | **Off** | Settings -> Cloud embeddings |
| **Voice notes** | Audio is handled by the OS speech recogniser. It may be processed by Apple/Google servers unless on-device recognition is available and preferred | OS default | Settings -> "Prefer on-device speech" |

Categorisation, task extraction, priority, tags, semantic search and the graph **never** use the network.

## Permissions

| Permission | Why |
|---|---|
| Microphone / Speech recognition | Dictating notes |
| Camera / Photos | Attaching pictures |
| Notifications | Task reminders (local; nothing is pushed from a server) |
| Internet | Link previews and optional cloud embeddings |

## Lock screen

Widgets, the Quick Settings tile and Control Center controls open the app into an **empty composer**.
The app deliberately does **not** show itself above the lock screen (`showWhenLocked`), because the
"recent captures" strip would expose your notes; the device's normal unlock step applies.
