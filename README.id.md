> [!IMPORTANT]
> **Repo ini ditulis oleh AI.** Diagnosis, skrip, dan dokumentasi dibuat oleh pemilik repo bersama **agen AI** (DeepSeek V4.1 Flash via OpenCode), lalu diperiksa terhadap log yang direkam.
>
> **Mau debug HP sendiri pakai repo ini?** Berikan **seluruh repo dan dokumentasinya** — `README.md`, `README.id.md`, `docs/00`–`docs/12`, `evidence/`, dan `scripts/` — ke asisten AI kamu, lalu minta ia mengikuti panduan ini langkah demi langkah. Setelah itu **selalu cek** setiap klaimnya dengan `getprop` dan `logcat` sebelum menjalankan apa pun. Anggap output AI sebagai titik awal yang kuat, bukan otoritas.

# Moto G45 5G bootloop — diagnosis lengkap, perbaikan, dan panduan pemulihan

**Bahasa Indonesia** · [English](README.md)

**Perangkat:** Motorola Moto G45 5G · `XT2363-9` · codename **`fogos`** · Snapdragon 6s Gen 3 (`SM6375`)
**Gejala:** HP restart sendiri setiap **~2 menit**, terus-menerus, dan tetap terjadi setelah tiga kali flash firmware dan dua kali factory reset
**Akar masalah:** **NV modem rusak di `modemst1` / `modemst2`** — modem gagal cek konsistensi tiap boot, dan crash `qcrilNrd` hanyalah gejalanya
**Yang benar-benar memperbaiki:** **menghapus `modemst1` + `modemst2`** setelah bootloader di-unlock, sehingga modem membangun ulang NV dari `fsg`
**Status:** stabil, nol crash modem, data LTE dan suara jalan, IMEI utuh — diverifikasi pada boot pertama setelah perbaikan, lalu dipantau terus-menerus

> **Koreksi (2026-11-08).** Versi sebelumnya repo ini menyebut factory reset sebagai perbaikan dan
> state `/data` lama sebagai pemicu. Itu **salah** — reset hanya bertahan sekitar tiga jam lalu
> loop kembali. Perbaikan sebenarnya ada di
> [`docs/12-confirmed-fix-nv-repair.md`](docs/12-confirmed-fix-nv-repair.md).

Repo ini adalah tulisan yang sudah disanitasi dan bisa direproduksi dari satu perangkat: apa yang rusak, kenapa, apa yang kami coba, apa yang berhasil, apa yang **tidak**, dan cara melindungi data sebelum wipe.

> **Tidak berafiliasi dengan Motorola, Qualcomm, atau Google.** Semua isi di sini berasal dari satu perangkat ditambah pengetahuan umum Android/Qualcomm. Baca [Penafian](#penafian) sebelum menjalankan apa pun.

---

## Sebelum mulai — yang kamu butuhkan

Ini bukan perbaikan yang cukup dilakukan di HP saja. Kamu butuh **PC** dan **kabel**, dan sebagian besar kegagalan terjadi sebelum perintah pertama.

| Yang wajib ada | Kenapa |
|---|---|
| **PC/laptop Windows 10/11** (hak admin) | LMSA/Software Fix Motorola hanya untuk Windows; semua skrip di sini PowerShell |
| **Kabel USB *data*** — bukan kabel charge-only | Kabel charge-only tidak bisa membawa ADB. Ini penyebab #1 "`adb devices` kosong" |
| **ADB terpasang** (Android SDK Platform-Tools) | Semua diagnosis dan perbaikan memakai ini |
| **USB debugging + "Always allow" + screen lock dimatikan** | Jendela boot hanya 1,5–3 menit; buka kunci HP makan waktu. Set lock ke **None** sementara |
| **Port USB langsung** (tanpa hub/dock) | Hub memutus koneksi di tengah flash |
| **Internet di PC** + **disk kosong 30–60 GB** | Platform-Tools, gnirehtet, firmware 2–5 GB, backup |
| **HP terisi > 50 %** | Boot pertama setelah erase NV bisa beberapa menit |
| **Password akun Google** | Factory Reset Protection tetap berlaku walau tanpa screen lock |
| **PIN screen lock diketahui** | Kamu butuh untuk mematikan lock, dan memasangnya lagi nanti |
| **Seed 2FA sudah diekspor, backup sudah selesai** | Wipe menghapusnya permanen |

**Checklist lengkap, driver, troubleshooting kabel, dan daftar "apa saya sudah siap?":** [`docs/00-requirements.md`](docs/00-requirements.md)

> Kamu **tidak** butuh root, custom ROM, atau tool berbayar. Kamu **butuh** bootloader yang bisa di-unlock — `fastboot erase modemst1/modemst2` ditolak selama terkunci.

---

## Ringkasan cepat — kalau HP kamu sedang bootloop sekarang

| # | Lakukan ini | Kenapa |
|---|---|---|
| 1 | **Backup dulu** → [`docs/06-backup.md`](docs/06-backup.md) | Unlock bootloader menghapus `/data`, termasuk kunci dekripsi WhatsApp dan seed authenticator 2FA |
| 2 | Pastikan ini *bug yang sama* → [`docs/01-symptoms.md`](docs/01-symptoms.md) | Reboot loop ~2 menit dengan `qcrilNrd` di crash buffer adalah sidik jarinya |
| 3 | Dapatkan internet tanpa Wi-Fi/SIM → [`docs/07-internet-without-wifi-or-sim.md`](docs/07-internet-without-wifi-or-sim.md) | `gnirehtet` melakukan reverse tether lewat USB — tanpa root, tanpa Wi-Fi, tanpa SIM |
| 4 | **Catat IMEI** — tekan `*#06#` dan tulis kedua nomornya | Perbaikan ini menghapus NV store yang menyimpan IMEI |
| 5 | **Unlock bootloader** → [`docs/12`](docs/12-confirmed-fix-nv-repair.md#unlocking-the-bootloader) | `erase modemst1/2` ditolak selama bootloader terkunci |
| 6 | **Hapus NV modem** → `fastboot erase modemst1` lalu `fastboot erase modemst2` | **Inilah perbaikannya.** Modem membangun ulang NV dari partisi `fsg` |
| 7 | Verifikasi → `crash_count` tetap `0`, baseband ada, IMEI tidak berubah | Satu boot bersih bukan bukti — pantau 30 menit, lalu reboot sekali |

Kalau kamu punya 30 detik, baca [penjelasan satu layar](docs/03-root-cause.md#the-short-version).

---

## Kondisi akhir (terverifikasi)

![Android 15, build V1UGS35H.75-14-9-3-1-4, security patch 1 September 2026](assets/android15-latest-build.png)

Setelah perbaikan: **Android 15**, build `V1UGS35H.75-14-9-3-1-4`, security patch **1 September 2026**, baseband `M6375_HI434_03.562.01.121R`, `IN_SERVICE` di LTE, data dan suara jalan, **nol crash modem**.

HP ini melewati **tiga kali flash firmware** dan **dua kali factory reset** sebelum perbaikan sebenarnya. Semuanya tidak menyentuh `modemst1`/`modemst2`. Menghapus kedua partisi itu — yang butuh bootloader unlocked — adalah yang memulihkannya.

---

## Sebenarnya apa yang terjadi

HP punya dua komputer: **AP** (Android, aplikasi kamu) dan **modem/baseband** (radio, SIM, telepon, data). Keduanya bicara lewat kanal bernama **oemhook**, dijembatani oleh daemon RIL Qualcomm `qcrilNrd`.

Di perangkat ini, Motorola menyertakan library vendor `libmotext_inf.so` yang menangani lalu lintas oemhook. Library itu mengandung bug:

```
Process:  /vendor/bin/hw/qcrilNrd  (uid 1001)
Signal:   SIGSEGV, SEGV_MAPERR, fault addr 0xffffffffffffff02
#00  libqcrilNr.so    qcril_qmi_oem_free_and_convert_ril_token_to_oem_token
#01  libqcrilNr.so    qcril_qmi_oemhook_agent_send
#02  libqcrilNr.so    mot_qcril_qmi_oemhook_agent_send
#03  libmotext_inf.so communicationThread      <-- proprietary Motorola
#04  libc.so          __pthread_start
```

Sebuah token yang merujuk koneksi modem yang sudah tidak ada (`0xffffffffffffff02` = `-254`, kode error yang dipakai sebagai pointer) di-dereference. `qcrilNrd` mati. `system_server` menunggu Binder call yang tidak akan pernah kembali. Setelah ~60 detik **watchdog** mematikan sistem dan HP reboot. Ulang setiap 2 menit.

Crash ini **gejala**. Di bawahnya, database NV modem (`modemst1`/`modemst2`) rusak, jadi modem gagal cek konsistensi tiap boot dan layanan QMI-nya hilang. Library lalu mem-dereference token untuk koneksi yang sudah lenyap.

Karena itu:

- **OTA Android 15 tidak membantu** — ia mengganti image, bukan NV modem.
- **Flash LMSA tidak membantu** — alasannya sama; ia menulis ulang partisi yang bukan sumber NV modem.
- **Menonaktifkan 13 package hanya menurunkan frekuensi crash** — aplikasi adalah *pengirim* lalu lintas oemhook, bukan penyebabnya.
- **Factory reset hanya menunda** — ia reprovision stack modem, yang menutupi NV rusak selama beberapa jam, tapi tidak pernah menyentuh `modemst1/2`.
- **Menghapus `modemst1` + `modemst2` memperbaikinya** — modem membangun ulang database NV yang bersih dari partisi `fsg`.

Analisis lengkap, termasuk kenapa factory reset *tampak* berhasil dan kenapa sebenarnya tidak: **[`docs/03-root-cause.md`](docs/03-root-cause.md)**.

---

## Peta repositori

```
README.md                     versi English
README.id.md                  kamu di sini (Bahasa Indonesia)
docs/
  00-requirements.md          PC, kabel, ADB, driver, akun, checklist pra-terbang
  01-symptoms.md              bedakan bootloop ini vs. penyebab lain
  02-diagnosis.md             kumpulkan bukti dengan ADB; baca tombstone
  03-root-cause.md            mekanika crash, dan teori yang salah (disimpan sebagai catatan)
  04-fixes.md                 perbaikan berurut + langkah pasti + apa yang dihancurkan
  05-tutorial.md              panduan bahasa sederhana, dari awal sampai akhir
  06-backup.md                apa yang harus dibackup, apa yang tidak bisa diselamatkan, caranya
  07-internet-without-wifi-or-sim.md   reverse tethering USB dengan gnirehtet
  08-hardening.md             OPSIONAL debloat + monitoring stabilitas
  09-faq.md                   "bisa kambuh?", garansi, root, LineageOS...
  10-evidence-index.md        isi evidence/ dan cara sanitasinya
  11-ai-assisted-debugging.md cara debug pakai AI + ADB, dan kesalahan yang kami lakukan
  12-confirmed-fix-nv-repair.md  PERBAIKANNYA: unlock, hapus modemst1/2, verifikasi
scripts/
  adb/                        .ps1 + .sh portabel: collect, disable, re-enable, verify
  windows/                    tether keeper + watchdog (path bisa diatur)
evidence/                     crash signature, snapshot, log yang sudah disanitasi
PRIVACY.md                    persis apa yang dihapus sebelum dipublikasikan
LICENSE                       MIT (kode) / CC BY 4.0 (tulisan)
```

---

## Versi singkat perbaikannya

```text
1. Tekan *#06# dan catat kedua IMEI.
2. Unlock bootloader (kode unlock Motorola; HP ter-wipe).
3. fastboot erase modemst1
   fastboot erase modemst2
   fastboot reboot
4. Tekan *#06# lagi — IMEI harus sama.
```

Semua isi repo ini ada karena urutan itu tidak berguna kalau kamu belum backup, tidak bisa memastikan loop-mu bug yang sama, atau erase-nya tidak berhasil.

---

## Debug dengan AI + ADB (disarankan)

Repo ini sendiri didiagnosis dengan bantuan AI. Kamu juga bisa. Kuncinya: **AI tidak bisa melihat HP-mu**, jadi kamu yang harus memberi bukti, dan kamu yang harus memverifikasi.

### Yang AI bagus untuk ini

- Membaca crash buffer native (`SIGSEGV`, pointer beracun, backtrace)
- Menghubungkan gejala yang tampak tidak berhubungan (SIM → data → Wi-Fi → reboot = satu dependensi bersama)
- Menulis skrip sekali-jalan, karena jendela boot cuma ~2 menit
- Menerjemahkan istilah vendor: `qcrilNrd`, `oemhook`, `RegRAT`, `APMState`, `modemst1/2`
- Membantu menyanitasi log sebelum kamu tempel di publik

### Yang AI tidak bisa

- Melihat HP-mu, menjalankan `adb`, atau flash firmware
- Menjamin nama package/prop itu benar — sering halusinasi, jadi cek dengan `pm list packages` / `getprop`
- Memastikan perbaikan berhasil — hanya uptime 10+ menit tanpa crash `qcrilNrd` yang bisa

### Alur yang kami pakai

Ini alur di balik [`evidence/timeline.txt`](evidence/timeline.txt):

```
1. AMATI      Apa yang terjadi, urutannya, berapa lama antar reboot?
2. REKAM      Ambil bukti selagi HP hidup (atau dari storage yang persisten).
3. HIPOTESIS  Satu kalimat: "X menyebabkan Y karena Z."
4. PREDIKSI   "Kalau X penyebabnya, melakukan A harus mengubah B."
5. UJI        Satu perubahan per percobaan. Catat hasilnya.
6. KOREKSI    Kalau prediksi gagal, buang hipotesisnya. Jangan ditambal.
```

Langkah 6 yang paling penting. Hipotesis kedua kami (state `/data` lama) salah: factory reset cuma menunda loop sekitar tiga jam. Perbaikan baru berhasil setelah hipotesis itu dibuang dan kami kembali ke penyebab sebenarnya — NV modem yang rusak.

### Yang perlu direkam dulu

```bash
adb devices
adb shell getprop > props.txt
adb shell 'cat /proc/uptime'
adb shell getprop ro.boot.bootreason
adb shell 'logcat -d -b crash' > crash.txt
adb shell 'logcat -d -b system' > system.txt
adb shell 'dumpsys telephony.registry' > telephony.txt
adb shell 'dumpsys connectivity' > connectivity.txt
adb shell 'ls -l /data/tombstones' > tombstones.txt
```

Atau pakai skrip yang sudah disediakan:

- [`scripts/adb/collect-evidence.ps1`](scripts/adb/collect-evidence.ps1) (Windows)
- [`scripts/adb/collect-evidence.sh`](scripts/adb/collect-evidence.sh) (Linux/macOS)

> **Tombstone bertahan setelah reboot.** Kalau loop terlalu cepat untuk `logcat` langsung, ambil `/data/tombstones` — isinya tetap ada sampai factory reset berikutnya. Ini trik paling berguna di seluruh panduan ini.

### Template prompt (Bahasa Indonesia)

```text
Kamu membantu saya debug HP Android lewat ADB. Jangan menebak.

Perangkat: Motorola Moto G45 5G (XT2363-9, codename fogos, SM6375)
Build: <ro.build.fingerprint>
Baseband: <gsm.version.baseband>
Gejala: <satu kalimat, sertakan waktunya>
Uptime sebelum reboot: <detik>

Lampiran:
- crash.txt   (logcat -b crash)
- props.txt   (getprop)
- telephony.txt
- connectivity.txt

Aturan:
1. Mulai dari perintah read-only. Jangan erase, flash, atau uninstall.
2. Setiap klaim harus dikutip dari baris yang mendukung di file.
3. Kalau bukti kurang, bilang apa yang harus saya ambil lagi.
4. Beri satu hipotesis per langkah, lengkap dengan prediksi yang bisa diuji.
5. Bilang apa yang akan membuktikan kamu salah.
```

Aturan terakhir itu penting. AI yang tidak bisa salah tidak berguna untuk debugging.

### Sanitasi sebelum ditempel

Log penuh identifier. **Jangan pernah tempel output mentah ke issue publik atau chat.** Minimal hapus:

- `ro.serialno`, `ro.boot.serialno`, `ro.vendor.boot.serialno`
- IMEI / MEID / ICCID / IMSI / nomor telepon
- SSID Wi-Fi, BSSID, alamat MAC
- Nama akun Google dan nilai `authuser=`
- Nama perangkat Bluetooth
- Path lokal (`C:\Users\…`)

Checklist lengkap: [`PRIVACY.md`](PRIVACY.md).

### Kesalahan yang kami lakukan (jangan diulang)

1. **Menyimpulkan pemicunya ada di `/data`.** Ini kesalahan yang mahal. Factory reset tampak berhasil, tapi loop kembali sekitar tiga jam kemudian. Penyebabnya NV modem yang rusak, bukan `/data`. Pelajarannya: perbaikan yang bertahan beberapa jam bukan perbaikan — uji lewat reboot dan lewat hari.
2. **Pakai LMSA "no factory delete".** Terasa lebih aman, tapi pemicunya memang bukan di `/data`, jadi opsi itu tidak berpengaruh. Tool ini juga tidak pernah menyentuh `modemst1/2`.
3. **Mengoreksi mitos "factory reset membersihkan NVRAM modem" secara berlebihan.** Mitos itu tidak tepat (recovery memang tidak menyentuh `modemst1`/`modemst2`), tapi kami lalu menyimpulkan NVRAM modem tidak mungkin terlibat — padahal justru itulah penyebabnya.
4. **Menganggap menonaktifkan package sebagai solusi.** Crash melambat, bukan hilang. Aplikasi cuma pengirim, bukan penyebab.
5. **Balapan dengan `logcat`.** Jendela 2 menit bikin crash lewat terus. Solusinya: ambil tombstone yang persisten.
6. **Menghabiskan jendela boot untuk buka layar kunci.** PIN/pattern membuat `/data` tetap terenkripsi sampai unlock, jadi ADB tidak bisa dipakai. Set lock ke **None** sementara.
7. **Tidak mencentang "Always allow from this computer".** Setiap reboot harus authorize ulang — tidak mungkin dilakukan dalam 2 menit.
8. **Menolak mencoba `fastboot erase modemst1/modemst2`.** Justru ini perbaikannya. Risiko IMEI nyata tapi bisa dikelola: catat IMEI dulu, erase, lalu pastikan tidak berubah.
9. **Percaya angka success rate anekdot.** "~60%" dan "~90%" di draf awal itu karangan dari forum, bukan pengukuran. Kalau tidak diukur, bilang anekdot — atau hapus.
10. **Mengira SIM/data/Wi-Fi mati bersamaan = hardware rusak.** Semuanya bergantung pada `system_server` + telephony; `qcrilNrd` yang macet menjatuhkan semuanya sekaligus. Satu penyebab, banyak gejala.
11. **Backup terlambat.** Kunci WhatsApp dan seed 2FA ada di `/data` dan hilang permanen saat unlock/reset. Backup dulu: [`docs/06-backup.md`](docs/06-backup.md).

Panduan lengkap (English): [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md).

---

## Penafian

Flash, wipe, dan `pm disable-user` bisa brick perangkat atau membatalkan garansi. Panduan ini diberikan **apa adanya, tanpa jaminan**. Kamu bertanggung jawab atas perangkat dan datamu sendiri.

- Factory reset dan unlock bootloader **tidak bisa dibatalkan** untuk data di perangkat. Backup dulu.
- Menonaktifkan package di [`scripts/adb/debloat-optional.txt`](scripts/adb/debloat-optional.txt) bisa merusak VoLTE, panggilan darurat, atau OTA. Itu **opsional dan bisa dikembalikan**.
- Kalau HP masih garansi dan perbaikan ini tidak membantu, pakai service center — jangan buka perangkatnya.

---

## Kontribusi

Koreksi, build `fogos` tambahan, atau laporan crash signature yang sama sangat diterima. Buka issue dengan **build fingerprint**, **versi baseband**, dan potongan **`logcat -b crash`** — dan sanitasi serial/IMEI dulu. Lihat [`PRIVACY.md`](PRIVACY.md) untuk checklist redaksi yang dipakai di sini.

---

## Lisensi dan AI

- Kode: **MIT**
- Tulisan/dokumentasi: **CC BY 4.0**

Repo ini **ditulis bersama AI**: diagnosis, skrip, dan dokumentasi disusun oleh pemilik repo bersama agen AI, lalu diverifikasi terhadap bukti di [`evidence/`](evidence/). Gunakan AI untuk debug perangkatmu — tapi verifikasi setiap klaim, dan jangan pernah menempel log mentah ke publik.
