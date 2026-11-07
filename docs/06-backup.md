# 06 — Backups: what to save before you wipe

A factory reset deletes `/data`. This page tells you exactly what that means, in what order to save things, and how to do it while the phone is rebooting every two minutes.

---

## What a factory reset destroys

| Data | Where it lives | Survives reset? | Recoverable afterwards? |
|---|---|---|---|
| Photos, videos, downloads | `/sdcard/DCIM`, `/sdcard/Pictures`, ... | ❌ | Only if copied off first |
| WhatsApp chats | `/data/data/com.whatsapp/databases/` + `/sdcard/Android/media/com.whatsapp/` | ❌ | From Google Drive backup, or local `.crypt14` **+ key** |
| WhatsApp media | `/sdcard/Android/media/com.whatsapp/WhatsApp/Media/` | ❌ | Only if backed up |
| SMS, call log | `/data/data/com.android.providers.telephony/` | ❌ | Only from an app backup |
| Contacts | Google account or `/data/data/com.android.providers.contacts/` | ✅ if synced to Google | Re-sync |
| App logins / app data | `/data/data/<pkg>/` | ❌ | Re-sign-in; most apps have no export |
| **2FA authenticator seeds** | `/data/data/<authenticator>/` | ❌ | **Only if you exported/migrated them** |
| Saved Wi-Fi passwords | `/data/misc/wifi/` | ❌ | Google backup sometimes restores them |
| Device settings | `/data/system/` | ❌ | Google backup restores a subset |
| Internal storage files | `/sdcard/` | ❌ | Only if copied off |
| SD card (if present) | physical card | ✅ | Not touched |
| SIM contacts | SIM card | ✅ | Not touched |

**The two things people most often lose and cannot get back: 2FA seeds and WhatsApp media.**

---

## Priority order

Do these in order. If you only have 10 minutes, do 1–3.

1. **2FA authenticator seeds** — export/migrate in the app. Without this you can be locked out of email, banking, everything.
2. **Photos and videos** — copy `DCIM`, `Pictures`, `Download`, `Movies`, `Music`, `Documents`.
3. **WhatsApp** — Google Drive backup **and** copy the local `Databases` folder.
4. **SMS / call log** — SMS Backup & Restore.
5. **Contacts** — Google sync or `.vcf` export.
6. **Games** — copy save folders (`Android/data/<game>/`, `Android/obb/<game>/`) if accessible; many games are cloud-synced, some are not.
7. **App-specific exports** — banking, notes, password manager, chat apps.
8. **Device settings screenshot** — not data, but saves reconfiguration time.

---

## Method 1 — MTP (no ADB needed)

Works even if USB debugging is off.

1. Connect USB. On the phone, pull down the notification shade → tap the USB notification → **File transfer / MTP**.
2. On Windows, the phone appears in **This PC**.
3. Copy these folders to `D:\phone-backup\<date>\`:

```text
DCIM\
Pictures\
Download\
Movies\
Music\
Documents\
Android\media\com.whatsapp\        (if accessible)
```

Windows Explorer may stall when the phone reboots. If a copy fails, just restart it — Explorer resumes per-file, and already-copied files are skipped.

> On Android 11+, `Android/data` and `Android/obb` are hidden from MTP. `Android/media` is usually visible. If WhatsApp's folder is not, use Method 2.

---

## Method 2 — `adb pull` with a retry loop (best for a bootlooping phone)

`adb pull` is faster and survives reboots better than Explorer, because you can script retries. Each boot gives you a window; the script copies whatever exists and resumes next boot.

```powershell
$src = "/sdcard/"
$dst = "D:\phone-backup\sdcard"
New-Item -ItemType Directory -Force -Path $dst | Out-Null

for ($i = 1; $i -le 40; $i++) {
    adb wait-for-device
    Write-Host "[$i] device up, pulling..."
    adb pull $src $dst 2>&1 | Out-Null
    Write-Host "[$i] attempt finished"
    Start-Sleep -Seconds 3
}
```

`adb pull` skips files that already exist with the same size, so repeated runs are incremental.

Targeted pulls (faster, higher value):

```bash
adb pull /sdcard/DCIM                     D:\phone-backup\DCIM
adb pull /sdcard/Pictures                 D:\phone-backup\Pictures
adb pull /sdcard/Download                 D:\phone-backup\Download
adb pull /sdcard/Android/media/com.whatsapp D:\phone-backup\whatsapp-media
adb pull /sdcard/Android/data             D:\phone-backup\android-data
adb pull /sdcard/Android/obb              D:\phone-backup\android-obb
```

Ready-made: [`../scripts/adb/pull-sdcard.ps1`](../scripts/adb/pull-sdcard.ps1).

> This is exactly how the reference device was backed up: a retry loop pulling **DCIM, images, videos and game folders** across a 1.5–3 minute reboot interval, while the phone was in airplane mode with gnirehtet providing internet. Each boot copied a batch; the loop survived the reboots. WhatsApp and Gmail were then backed up over the USB tunnel. It is slow but it works.

---

## Method 3 — WhatsApp, done properly

WhatsApp has three separate things that are easy to confuse.

### 3a. Google Drive backup (the reliable one)

In WhatsApp: **Settings → Chats → Chat backup → Back up to Google Drive**.

- Choose **Include videos** if you have Drive space.
- Note the Google account used — you must sign in with the **same** account after the reset.
- If **end-to-end encrypted backup** is enabled, you need the **64-digit key** or your password. Save it somewhere that is not the phone. If you lose it, the backup is unrecoverable, including by WhatsApp.

This backup is tied to your **phone number**. You must reactivate the same number after the reset.

### 3b. Local `.crypt14` backup (only useful with the key)

The phone keeps encrypted databases here:

```text
/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/
    msgstore.db.crypt14              ← current
    msgstore-YYYY-MM-DD.1.db.crypt14 ← daily history
    wa.db.crypt14                    ← contacts
    ...
```

Copy the whole folder to the PC. **But:** `.crypt14` is encrypted with a key stored in WhatsApp's private app storage (`/data/data/com.whatsapp/files/key`), which is **wiped by the factory reset** and is **not readable without root**. So:

- With root: back up the key file too, and the local backup is restorable.
- Without root: the local `.crypt14` files alone are **not enough**. You need the Google Drive backup.

This was exactly the situation in the reference incident: 49 MB of local `.crypt14` files, no root, no key export — so the Drive backup was the only real restore path.

### 3c. Restoring after the reset

1. Install WhatsApp from Play Store.
2. Register with the **same phone number**.
3. When prompted, choose **Restore** from Google Drive.
4. If restoring from a local file instead: copy `msgstore.db.crypt14` (or a dated one renamed to `msgstore.db.crypt14`) into
   `/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/` **before** opening WhatsApp, then register.
5. Media restores from Drive only if "Include videos" was on.

> Do not copy a `.crypt14` from a different phone number. It will fail to decrypt or restore nothing.

---

## Method 4 — SMS and call log

Android has no built-in export. Use **SMS Backup & Restore** (Play Store):

1. Install → **Set up a backup** → Back up SMS + call log.
2. Save to local file, then copy the XML to the PC (or upload to Drive).
3. After the reset: reinstall, **Restore**, pick the XML.

---

## Method 5 — Contacts

- **Synced to Google:** nothing to do. After signing in, contacts return.
- **Phone-only contacts:** *Contacts → Fix & manage → Export to file* → save `.vcf` to internal storage, then copy it off.
- **SIM contacts:** they live on the SIM and survive, but re-import them manually.

---

## Method 6 — Authenticator seeds (do not skip)

Google Authenticator: **⋮ → Transfer accounts → Export accounts** → select → it shows QR codes. **Screenshot them** or copy them to a password manager, then move them off the phone. Import after the reset.

Other authenticators (Aegis, Authy, Microsoft, 1Password): each has an export/backup path. Authy is multi-device — enable it before you wipe.

> If you skip this and the phone is your only 2FA device, you may lose access to accounts permanently. Recovering a 2FA-locked account can take days and sometimes fails.

---

## Method 7 — App-specific data

| App type | What to do |
|---|---|
| Password manager (Bitwarden, 1Password, KeePass) | Ensure sync/export works; keep the recovery kit |
| Banking | Note the activation process; some require a branch visit after a device change |
| Notes (Keep, Obsidian, Notion) | Sync or export |
| Chat apps (Telegram, Signal) | Telegram is cloud-based; Signal has an in-app backup (`.backup` file) |
| Games | Many use cloud saves; some are local-only |
| E-book/comic readers | Copy the library folder |
| Termux / dev tools | Copy `~/` if it matters |

`adb backup` is **not** an option any more: it was deprecated in Android 12, and most apps opt out of it. Do not rely on it.

---

## When the phone barely boots

You have ~60–120 seconds per boot. Strategy:

1. **Start the copy before the phone is ready.** Run the retry-loop script and leave it running across reboots. It will make progress every cycle.
2. **Prioritise.** Pull `DCIM` first, then WhatsApp, then everything else. A partial backup beats none.
3. **Use airplane mode** ([Fix 0](04-fixes.md#fix-0--stabilise-it-long-enough-to-back-up)) to reduce crashes from ~14/boot to ~2/boot.
4. **Turn the screen off.** Rendering the UI costs CPU. `adb shell input keyevent 26`.
5. **Do not use MTP** if ADB works — it is slower and less resumable.
6. **Recovery has no MTP** on stock Motorola. Do not count on it.
7. **Cloud sync is your friend.** If Google Photos was already backing up, your photos are safe. Check `photos.google.com` from a PC *before* panicking.
8. **SD card:** if the phone has one and media is stored there, remove it — it is not wiped.

---

## Restoring safely

After the fix, restore in this order and stop if anything misbehaves:

1. Google account sign-in → contacts, calendar, some settings.
2. Play Store → reinstall apps (do **not** use a full "device clone" restore).
3. Copy media folders back over MTP.
4. Restore WhatsApp from Drive.
5. Restore SMS/call log from the XML.
6. Import authenticator seeds.
7. Sign in to apps one by one.

### Never restore these

```text
/data/vendor/radio/            ← the trigger lives here
telephony.db                   ← APNs/subscriptions
/data/misc/radio/
/data/system/users/0/...       ← accounts/settings; use Google backup instead
```

If you use TWRP or a root backup tool, restore **only** `/sdcard` and app data you actually need — never a full `/data` image.

---

## Backup verification checklist

Before you wipe, confirm all of these exist on the PC **and** are non-zero size:

- [ ] `DCIM/` — open two photos to confirm they are real files
- [ ] `Pictures/`, `Download/`, `Documents/`
- [ ] WhatsApp Drive backup timestamp is today
- [ ] `Android/media/com.whatsapp/WhatsApp/Databases/` copied (if accessible)
- [ ] SMS `.xml` backup
- [ ] Contacts `.vcf` or Google sync confirmed
- [ ] Authenticator seeds exported and stored **off the phone**
- [ ] Password manager recovery kit accessible
- [ ] You know your Google password and screen lock

Only then run the factory reset.
