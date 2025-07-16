# 🗂️ backup-recovery-practica

Un sistem complet de backup incremental și restaurare pentru Linux, dezvoltat în Bash. Include suport pentru:
- backup incremental,
- restaurare completă sau parțială,
- criptare cu parolă (AES-256),
- arhivare,
- verificare de integritate prin checksum,
- interfață grafică prietenoasă cu `zenity`.

---

## 📁 Structură generală

```
.
├── backup.sh           # Scriptul care face backup
├── restore.sh          # Scriptul pentru restaurare/verificare
├── main.sh             # Interfață grafică cu Zenity
├── config.conf         # Configurație generală
├── README.md           # Acest fișier
└── /backups            # Locație implicită pentru backup-uri
```

---

## ⚙️ Configurație (`config.conf`)

Fișierul permite personalizarea comportamentului:

```bash
SOURCE_DIR="/home/utilizator/Documents"
BACKUP_DIR="/home/utilizator/backups"
CHECKSUM_TYPE="sha256"
CREATE_ARCHIVE="true"
KEEP_UNCOMPRESSED="false"
ENCRYPT_BACKUP="true"
ENCRYPTION_PASSWORD=""
CLEANUP_OLD="true"
KEEP_BACKUPS="5"
EXCLUDE_PATTERNS="*.tmp *.log *.cache .git node_modules"
```

---

## 🚀 Utilizare prin meniu grafic (`main.sh`)

```bash
chmod +x main.sh
./main.sh
```

### Opțiuni disponibile:

1. **Creează backup** – pornește scriptul `backup.sh`, cu setările din `config.conf`.
   - Dacă `ENCRYPT_BACKUP=true`, cere parolă prin fereastră ascunsă.
2. **Restaurează complet** – alege backup și director destinație.
3. **Restaurează fișier specific** – selectează un fișier din backup.
4. **Verifică backup** – compară checksum-urile pentru integritate.
5. **Listează backup-uri** – afișează backup-urile salvate (inclusiv arhive criptate).
0. **Ieșire**

---

## 🔐 Criptare

Dacă ai activat criptarea (`ENCRYPT_BACKUP=true`), backup-ul va fi criptat cu `openssl aes-256-cbc`, iar extensia va fi `.tar.gz.enc`.

### Decriptare:
Se face automat din `restore.sh` dacă parola este furnizată prin `ENCRYPTION_PASSWORD` (prin `zenity` în interfața grafică).

---

## 📦 Format backup

Backup-ul are următoarea structură:

```
backup_YYYYMMDD_HHMMSS/
├── data/               # Fișierele efective salvate
└── metadata.csv        # Informații despre permisiuni, owner, checksum, timp modificare
```

---

## ✅ Verificare integritate

Verificarea se face automat după backup și manual din meniu. Se compară checksum-urile din `metadata.csv` cu cele reale.

---

## 🔁 Restaurare metadate

În timpul restaurării se aplică:
- permisiuni (`chmod`)
- owner/grup (`chown`) – doar dacă rulezi ca root
- timp de modificare (`touch -d`)
- opțional: se pot adăuga ACL și atribute extinse (viitor)

---

## 📅 Backup incremental

La fiecare rulare, sunt salvate doar fișierele care:
- s-au modificat (detectat prin checksum),
- sau nu existau anterior.

---

## 🧪 Cerințe

- Linux cu `bash`, `zenity`, `tar`, `openssl`
- Opțional: `cron` pentru rulare automată

---

## 🧠 Autor

Realizat ca temă practică pentru disciplina "Administrarea sistemelor Linux" / "Sisteme de operare".