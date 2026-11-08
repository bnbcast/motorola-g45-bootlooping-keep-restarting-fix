> [!IMPORTANT]
> **Repo ini ditulis oleh AI.** Diagnosis, skrip, dan dokumentasi dibuat oleh pemilik repo bersama **agen AI** (DeepSeek V4.1 Flash via OpenCode), lalu diperiksa terhadap log yang direkam.
>
> **Mau debug HP sendiri pakai repo ini?** Berikan **seluruh repo dan dokumentasinya** — `README.md`, `README.id.md`, `docs/00`–`docs/12`, `evidence/`, dan `scripts/` — ke asisten AI kamu, lalu minta ia mengikuti panduan ini langkah demi langkah. Setelah itu **selalu cek** setiap klaimnya dengan `getprop` dan `logcat` sebelum menjalankan apa pun. Anggap output AI sebagai titik awal yang kuat, bukan otoritas.

# Moto G45 5G Bootloop — Panduan Perbaikan & Pemulihan Lengkap

**Bahasa Indonesia** · [English](README.md)

| Perangkat | Motorola Moto G45 5G · `XT2363-9` · codename **`fogos`** · Snapdragon 6s Gen 3 (`SM6375`) |
|-----------|--------------------------------------------------------------------------------------------|
| Gejala | HP restart sendiri setiap **~2 menit**, terus-menerus — bertahan setelah 3x flash firmware & 2x factory reset |
| Akar masalah | **NV modem rusak di `modemst1` / `modemst2`** — modem gagal cek konsistensi tiap boot, crash `qcrilNrd` hanyalah gejala |
| **Perbaikannya** | **Hapus `modemst1` + `modemst2`** setelah unlock bootloader → modem bangun ulang NV bersih dari partisi `fsg` emas |
| Status | ✅ Stabil · Nol crash modem · Data LTE & suara jalan · IMEI utuh · Terverifikasi 2+ jam |

> **Koreksi (2026-11-08).** Versi sebelumnya menyebut factory reset sebagai perbaikan. **Itu salah** — reset hanya bertahan ~3 jam. Perbaikan sebenarnya ada di [`docs/12-confirmed-fix-nv-repair.md`](docs/12-confirmed-fix-nv-repair.md).

---

## 📋 Daftar Isi

1. [Mulai Cepat — Kalau HP Kamu Sedang Bootloop](#mulai-cepat--kalau-hp-kamu-sedang-bootloop)
2. [Sebelum Mulai — Yang Kamu Butuhkan](#sebelum-mulai--yang-kamu-butuhkan)
3. [Apa yang Sebenarnya Terjadi — Ceritanya](#apa-yang-sebenarnya-terjadi--ceritanya)
4. [Perbaikan — Langkah Demi Langkah](#perbaikan--langkah-demi-langkah)
5. [Cara Kami Verifikasi](#cara-kami-verifikasi)
6. [FAQ](#faq)
7. [Dokumentasi Lengkap](#dokumentasi-lengkap)
8. [Debug dengan AI + ADB](#debug-dengan-ai--adb)
9. [Kesalahan Kami (Supaya Kamu Tak Perlu Mengulang)](#kesalahan-kami-supaya-kamu-tak-perlu-mengulang)
10. [Penafian & Hukum](#penafian--hukum)

---

## 🚨 Mulai Cepat — Kalau HP Kamu Sedang Bootloop

| Langkah | Lakukan Ini | Kenapa |
|---------|-------------|--------|
| 1 | **Backup dulu** → [`docs/06-backup.md`](docs/06-backup.md) | Unlock bootloader hapus `/data` — kunci WhatsApp, seed 2FA, semuanya |
| 2 | Pastikan ini *bug yang sama* → [`docs/01-symptoms.md`](docs/01-symptoms.md) | Reboot 2 menit + `qcrilNrd` di crash buffer = sidik jarinya |
| 3 | Dapatkan internet tanpa Wi-Fi/SIM → [`docs/07-internet-without-wifi-or-sim.md`](docs/07-internet-without-wifi-or-sim.md) | `gnirehtet` reverse-tether lewat USB — tanpa root, tanpa Wi-Fi, tanpa SIM |
| 4 | **Catat IMEI** — tekan `*#06#` dan tulis kedua nomornya | Perbaikan hapus NV store yang nyimpen IMEI |
| 5 | **Unlock bootloader** → [`docs/12`](docs/12-confirmed-fix-nv-repair.md#unlocking-the-bootloader) | `fastboot erase` ditolak kalau masih terkunci |
| 6 | **Hapus NV modem** → `fastboot erase modemst1` lalu `fastboot erase modemst2` | **Ini perbaikannya.** Modem bangun ulang NV dari `fsg` emas |
| 7 | Verifikasi → `crash_count` = 0, baseband ada, IMEI tidak berubah | Satu boot bersih bukan bukti — pantau 30 menit, lalu reboot sekali |

> ⏱️ **Versi 30 detik:** [Penjelasan satu layar](docs/03-root-cause.md#the-short-version)

---

## 🛠️ Sebelum Mulai — Yang Kamu Butuhkan

Ini bukan perbaikan cuma-di-HP. Kamu butuh **PC** dan **kabel**, dan kebanyakan kegagalan terjadi *sebelum* perintah pertama.

| Wajib punya | Kenapa |
|-------------|--------|
| **PC/laptop Windows 10/11** (hak admin) | LMSA/Software Fix Motorola cuma Windows; semua skrip di sini PowerShell |
| **Kabel USB *data*** — bukan charge-only | Kabel charge-only nggak bawa ADB. Penyebab #1 "`adb devices` kosong" |
| **ADB terpasang** (Android SDK Platform-Tools) | Semua diagnosis dan perbaikan pakai ini |
| **USB debugging + "Always allow" + screen lock dimatikan** | Jendela boot cuma 1,5–3 menit; buka kunci HP makan waktu. Set lock ke **None** dulu |
| **Port USB langsung** (tanpa hub/dock) | Hub putus koneksi di tengah flash |
| **Internet di PC** + **disk 30–60 GB** | Platform-Tools, gnirehtet, firmware 2–5 GB, backup |
| **HP terisi > 50 %** | Boot pertama setelah erase NV bisa beberapa menit |
| **Password akun Google** | Factory Reset Protection tetap berlaku walau tanpa screen lock |
| **PIN screen lock diketahui** | Butuh buat matiin lock, dan pasang lagi nanti |
| **Seed 2FA diekspor, backup selesai** | Wipe hapus permanen |

**Checklist lengkap, driver, troubleshooting kabel, daftar "apa saya sudah siap?":** [`docs/00-requirements.md`](docs/00-requirements.md)

> Kamu **tidak** butuh root, custom ROM, atau tool berbayar. Kamu **butuh** bootloader yang bisa di-unlock — `fastboot erase modemst1/modemst2` ditolak selama terkunci.

---

## 📖 Apa yang Sebenarnya Terjadi — Ceritanya

HP kamu punya dua komputer di dalam:
- **AP** (Application Processor) — jalanin Android, aplikasi kamu, UI
- **Modem/Baseband** — urus radio, SIM, telepon, data seluler

Keduanya bicara lewat kanal **oemhook**, dijembatani daemon RIL Qualcomm `qcrilNrd`.

Di perangkat ini, Motorola bawa library vendor `libmotext_inf.so` yang handle traffic oemhook. Library itu punya bug:

```
Process:  /vendor/bin/hw/qcrilNrd  (uid 1001)
Signal:   SIGSEGV, SEGV_MAPERR, fault addr 0xffffffffffffff02
#00  libqcrilNr.so    qcril_qmi_oem_free_and_convert_ril_token_to_oem_token
#01  libqcrilNr.so    qcril_qmi_oemhook_agent_send
#02  libqcrilNr.so    mot_qcril_qmi_oemhook_agent_send
#03  libmotext_inf.so communicationThread      <-- proprietary Motorola
#04  libc.so          __pthread_start
```

Token yang merujuk koneksi modem yang sudah nggak ada (`0xffffffffffffff02` = `-254`, kode error dipakai sebagai pointer) di-dereference. `qcrilNrd` mati. `system_server` nunggu Binder call yang nggak pernah balik. Setelah ~60 detik **watchdog** bunuh sistem dan HP reboot. Setiap 2 menit. Selamanya.

**Crash itu gejala.** Di bawahnya, database NV modem sendiri (`modemst1`/`modemst2`) rusak. Modem assert tiap boot, layanan QMI-nya ilang, library nge-dereference token buat koneksi yang sudah pergi.

Itu alasannya:
- ❌ **OTA Android 15 nggak bantu** — ganti image AP, nggak sentuh NV modem
- ❌ **Flash LMSA nggak bantu** — alasan sama, nulis partisi salah
- ❌ **Nonaktifkin 13 package cuma kurangi rate crash** — app cuma *pengirim* traffic oemhook, bukan penyebab
- ❌ **Factory reset cuma nunda** — re-provision stack modem, nyembunyiin NV rusak beberapa jam, nggak sentuh `modemst1/2`
- ✅ **Hapus `modemst1` + `modemst2` memperbaikinya** — modem bangun ulang NV bersih dari partisi `fsg` emas

**Analisis lengkap:** [`docs/03-root-cause.md`](docs/03-root-cause.md)

---

## ⚡ Perbaikan — Langkah Demi Langkah

### Prasyarat (Baca Dulu Ini ⚠️)
- **Bootloader bisa di-unlock** — Motorola cuma unlock unit retail (XT2363-9 adalah retail). `fastboot erase` ditolak kalau terkunci.
- **Catat IMEI dulu** — tekan `*#06#` dan tulis kedua nomor. Erase hapus NV store yang nyimpen IMEI.
- **Backup sebelum unlock** — unlock hapus `/data` (kunci WhatsApp, seed 2FA, semua). Lihat [`panduan backup`](docs/06-backup.md).
- **JANGAN relock** — relock bootchain yang dimodifikasi (erase `modemst1/2` = state vendor dimodifikasi) akan hard-brick perangkat.

### Perintahnya

```bash
# 1. Catat IMEI dulu (tekan *#06#)
fastboot erase modemst1
# OKAY [  0.139s]

fastboot erase modemst2
# OKAY [  0.005s]

fastboot reboot

# 2. Verifikasi setelah boot
adb shell cat /sys/bus/msm_subsys/devices/subsys2/crash_count
# 0

adb shell getprop gsm.version.baseband
# M6375_HI434_03.562.01.121R

# 3. Konfirmasi IMEI nggak berubah (*#06#)
```

### Checklist Verifikasi
- ✅ Modem `crash_count` = 0 (semua 6 subsystem)
- ✅ Baseband ada (`M6375_HI434_03.562.01.121R`)
- ✅ SIM `LOADED`, LTE `IN_SERVICE`, data & suara jalan
- ✅ IMEI utuh (kedua cocok pre-repair)
- ✅ Uptime 2+ jam, nggak reboot, nggak restart framework
- ✅ Data pulih (9.4 GB staged push, 3.452 file verified)

---

## 🔬 Cara Kami Verifikasi

Nggak cuma "boot sekali" — pantauan berkelanjutan dengan cek otomatis:

| Metode | Apa yang Dilakukan |
|--------|-------------------|
| **Pantauan Stabilitas 4 Jam** | Monitor PowerShell custom (`thorough-watch.ps1`) polling tiap 60s: crash counter modem, uptime, baseband, state SIM, PID `qcrilNrd`, baterai, suhu. Nol anomali selama 2+ jam. |
| **Restore Bertahap dengan Gerbang** | 9.4 GB backup didorong 5 tahap. Setelah tiap tahap: `crash_count` = 0, uptime naik, baseband tetap. Semua 5 tahap lolos — 3.452 file, 100% cocok. |
| **Pindai Subsystem Mendalam** | Semua 6 subsystem Qualcomm dicek (`subsys0` ADSP → `subsys5` Venus): semua `crash_count = 0`. Nggak ada folder `ssrdump` (nggak ada dump assert modem). Satu tombstone thermal HAL tak terkait di boot, nggak pernah kembali. |

---

## ❓ FAQ

<details>
<summary><strong>Apakah perbaikan ini tahan update OTA?</strong></summary>
Ya. OTA nulis ulang partisi AP (`boot`, `dtbo`, `vendor_boot`, `super`), bukan `modemst1/2`. NV yang dibangun ulang tetap ada.
</details>

<details>
<summary><strong>Bisa nggak tanpa unlock bootloader?</strong></summary>
Nggak. `fastboot erase modemst1/modemst2` ditolak eksplisit saat terkunci. Unlock Motorola wajib (hanya unit retail).
</details>

<details>
<summary><strong>Apakah IMEI saya berisiko?</strong></summary>
Erase hapus NV store yang nyimpen IMEI, tapi modem nulis ulang dari partisi `fsg` emas di boot pertama. **Catet dulu** (`*#06#`) dan verifikasi sesudah. Pun kami cocok persis.
</details>

<details>
<summary><strong>Apakah custom ROM (LineageOS, Pixel Experience, dll) memperbaiki ini?</strong></summary>
Nggak. Custom ROM cuma ganti partisi AP. Mereka nggak pernah sentuh `modemst1/2`. Firmware modem dan NV-nya terpisah.
</details>

<details>
<summary><strong>Factory reset kelihatan jalan 3 jam — kenapa?</strong></summary>
Factory reset re-provision stack modem (nulis ulang `/data/vendor/radio`, bersihin DB telephony), nyembunyiin NV rusak sementara. Tapi nggak sentuh `modemst1/2`, jadi korupsinya tetap ada dan loop kembali.
</details>

<details>
<summary><strong>Crash `qcrilNrd` itu sebenarnya apa?</strong></summary>
**Gejala**, bukan penyebab. Layanan QMI modem ilang karena NV rusak. Library Motorola `libmotext_inf.so` nge-dereference token buat koneksi mati (`-254` dipakai sebagai pointer) → `SIGSEGV` di `qcrilNrd` → `system_server` blok → watchdog reboot.
</details>

<details>
<summary><strong>Bisa relock bootloader setelah perbaikan?</strong></summary>
**Tidak.** Relock dengan bootchain termodifikasi (erase `modemst1/2` = state vendor termodifikasi) akan hard-brick perangkat. Biarkan terbuka.
</details>

<details>
<summary><strong>Apakah perbaikan ini spesifik build V1UGS35H.75-14-9-3-1-4?</strong></summary>
Akar masalah (korup `modemst1/2`) dan perbaikan (hapus keduanya) bersifat build-agnostic untuk perangkat `fogos` manapun. Versi baseband bisa beda; verifikasi `gsm.version.baseband` ada setelah reboot.
</details>

**FAQ lengkap:** [`docs/09-faq.md`](docs/09-faq.md)

---

## 📚 Dokumentasi Lengkap

| Bagian | Apa yang Ditemukan |
|--------|-------------------|
| **Mulai Di Sini** | [`Requirements & Pre-flight Checklist`](docs/00-requirements.md) — PC, kabel, ADB, akun, seed 2FA, tes kabel |
| **Diagnosis** | [`Gejala`](docs/01-symptoms.md) · [`Pengumpulan Bukti`](docs/02-diagnosis.md) · [`Analisis Akar Masalah`](docs/03-root-cause.md) |
| **Perbaikan & Verifikasi** | [`Perbaikan Tervalidasi: NV Repair`](docs/12-confirmed-fix-nv-repair.md) · [`Tutorial Langkah Demi Langkah`](docs/05-tutorial.md) · [`Verifikasi Restore`](docs/13-restore-verification.md) |
| **Debug AI-Assisted** | [`Cara Kami Pakai AI + ADB`](docs/11-ai-assisted-debugging.md) — prompt, kesalahan, aturan verifikasi. **Kasih AI repo ini utk debug HP kamu.** |
| **Skrip & Bukti** | [`Skrip ADB`](scripts/adb/) (collect, verify, debloat) · [`Log Tersanitasi`](evidence/) (crash signature, timeline, snapshot device) |
| **Keamanan & Hukum** | [`Checklist Privasi/Redaksi`](PRIVACY.md) · [`Lisensi`](LICENSE) (MIT / CC BY 4.0) · [`Penafian`](#penafian--hukum) |

---

## 🤖 Debug dengan AI + ADB

Repo ini didiagnosis dengan AI di loop. Kami sarankan pendekatan sama — dengan rem pengaman. **AI nggak bisa liat HP kamu.** Ia nggak bisa jalanin `adb`, flash firmware, atau verifikasi nama package. Kamu kasih bukti; kamu verifikasi hasil.

### Yang Harus Dikasih ke AI

Tangkap ini selagi HP hidup, terus lampirkan filenya:

```bash
adb devices
adb shell getprop > props.txt
adb shell 'logcat -d -b crash' > crash.txt
adb shell 'dumpsys telephony.registry' > telephony.txt
adb shell 'dumpsys connectivity' > connectivity.txt
adb shell 'ls -l /data/tombstones' > tombstones.txt
```

Atau jalankan [`scripts/adb/collect-evidence.ps1`](scripts/adb/collect-evidence.ps1) (Windows) atau [`collect-evidence.sh`](scripts/adb/collect-evidence.sh) (Linux/macOS) sekali dan biarkan ambil semua sebelum reboot.

> **💡 Tips pro:** Tombstone bertahan lewat reboot. Kalau loop terlalu cepat buat `logcat` live, tarik `/data/tombstones` saja. Ini trik paling berguna di seluruh panduan.

### Template Prompt

```text
Kamu bantu saya debug HP Android lewat ADB. Jangan menebak.

Perangkat: Motorola Moto G45 5G (XT2363-9, codename fogos, SM6375)
Build: <ro.build.fingerprint>
Baseband: <gsm.version.baseband>
Gejala: <satu kalimat, sertakan waktunya>
Uptime sebelum reboot: <detik>

Lampiran: crash.txt, props.txt, telephony.txt, connectivity.txt

Aturan:
1. Mulai dari perintah read-only saja. Nggak erase, nggak flash, nggak uninstall.
2. Setiap klaim harus dikutip dari baris yang mendukung di file.
3. Kalau bukti kurang, bilang apa yang harus saya ambil lagi.
4. Beri satu hipotesis per langkah, lengkap prediksi yang bisa diuji.
5. Bilang apa yang akan membuktikan kamu salah.
```

### Aturan yang Menjaga Kejujuran

1. **Read-only dulu.** `getprop`, `logcat`, `dumpsys` — nggak nulis sampe kegagalan dipahami.
2. **Satu perubahan per tes.** Ganti tiga hal sekaligus dan kamu nggak belajar apa-apa.
3. **Tuntut kutipan.** Kalau nggak bisa kutip baris log, ia nebak.
4. **Tanya "apa yang buktiin kamu salah?"** Kalau jawabannya "nggak ada", buang.
5. **Sanitasi sebelum Tempel.** Serial, IMEI, nomor telp, SSID, nama akun — lihat [`PRIVACY.md`](PRIVACY.md).
6. **Verifikasi dengan waktu, bukan reboot.** 10+ menit uptime dan crash `qcrilNrd` = 0.

---

## 🎓 Kesalahan Kami (Supaya Kamu Tak Perlu Mengulang)

Daftar lengkap dengan pelajarannya ada di [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md). Versi singkat:

| Kesalahan | Pelajaran |
|-----------|-----------|
| **Salah ambil akar masalah** — pikir state `/data` lama pemicunya karena factory reset *kelihatan* jalan 3 jam | "Perbaikan" yang tahan jam bukan perbaikan. Uji lewat reboot dan lewat hari. |
| **Bilang jangan hapus `modemst`** — peringatan itu salah; itu justru perbaikannya (pas catet IMEI dulu) | Jangan biar takutan kehilangan data ngehentikan solusi asli — kelola risikonya. |
| **Flash firmware 3x** — nggak bisa perbaiki NV modem rusak | Flash partisi AP nggak pernah sentuh NV modem. Lapisan beda total. |
| **Nonaktifkin package sebagai "perbaikan"** — rate crash turun tapi penyebab tetap | App cuma *pengirim* traffic oemhook, bukan pemicunya. |
| **Balapan `logcat` di jendela 2 menit** — crash terus kelewat | Tombstone persisten menang. Tarik `/data/tombstones` aja. |
| **Habisin jendela buat buka layar kunci** — PIN/pattern bikin `/data` tetap enkripsi sampe unlock | Set lock ke **None** sementara. Aktifin "Always allow from this computer" buat ADB. |
| **Percaya success rate anekdot** — "~60%", "~90%" dari forum | Kalau nggak diukur, sebut anekdot — atau hapus. |
| **Pikir SIM/data/Wi-Fi mati bareng = hardware rusak** | Semuanya bergantung `system_server` + telephony; satu crash `qcrilNrd` robohkan semua. |
| **Backup terlambat** — kunci WhatsApp & seed 2FA hilang permanen | **Backup dulu.** [`docs/06-backup.md`](docs/06-backup.md) bilang persis apa dan gimana. |

---

## ⚖️ Penafian & Hukum

**Flash, wipe, dan `fastboot erase` bisa brick perangkat atau batalin garansi. Panduan ini diberikan apa adanya, tanpa jaminan. Kamu bertanggung jawab atas perangkat dan datamu sendiri. Tidak berafiliasi dengan Motorola, Qualcomm, atau Google.**

- Factory reset dan unlock bootloader **tidak bisa dibatalkan** untuk data di perangkat. **Backup dulu.**
- Nonaktifkan package di [`scripts/adb/debloat-optional.txt`](scripts/adb/debloat-optional.txt) bisa merusak VoLTE, panggilan darurat, atau OTA. Itu **opsional dan bisa dikembalikan**.
- Kalau HP masih garansi dan ini nggak bantu, pakai service center — jangan buka perangkat.

**Lisensi:** Kode = MIT, Tulisan = CC BY 4.0. Lihat [`LICENSE`](LICENSE).

---

## 🤝 Kontribusi

Koreksi, build `fogos` tambahan, atau laporan crash signature yang sama sangat diterima. Buka issue dengan **build fingerprint**, **versi baseband**, dan potongan **`logcat -b crash`** — dan sanitasi serial/IMEI dulu. Lihat [`PRIVACY.md`](PRIVACY.md) untuk checklist redaksi.

---

## 🤖 AI Co-authorship

Repo ini ditulis pemilik bersama **agen AI coding** (DeepSeek V4.1 Flash via OpenCode).

- **Manusia:** punya perangkat, jalanin tiap perintah, ambil keputusan destruktif, verifikasi hasil.
- **AI:** baca log, usulkan hipotesis, tulis skrip & dokumentasi, dan salah lebih dari sekali.

Kami ungkapin ini karena debugging AI-assisted berguna dan harus dinormalisasi — tapi juga karena **output AI butuh verifikasi**. Bukti dipublikasikan supaya kamu cek alurnya, nggak cuma percaya. Lihat [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md) untuk alur, prompt, dan kesalahan.

> Kalau kamu pakai AI di perangkat sendiri: verifikasi tiap klaim pakai `getprop`/`logcat`, sanitasi log sebelum dibagikan, dan jangan biar AI ajakin `erase`, `flash`, atau `uninstall` tanpa alasan jelas.

---

## 🔗 Link Cepat

- **📖 Repo Lengkap:** [github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix](https://github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix)
- **🌐 Live Site:** [bnbcast.github.io/motorola-g45-bootlooping-keep-restarting-fix](https://bnbcast.github.io/motorola-g45-bootlooping-keep-restarting-fix/)
- **🇬🇧 English Version:** [README.md](README.md)
- **🐛 Laporkan Issue:** [GitHub Issues](https://github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix/issues)

---

*© 2026 bnbcast. Dibangun dengan ❤️ untuk komunitas `fogos`.*