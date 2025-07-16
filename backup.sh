#!/bin/bash

# Sistem de backup incremental pentru Linux


# Încărcare configurație
CONFIG_FILE="config.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Eroare: Fișierul de configurație $CONFIG_FILE nu a fost găsit!"
    exit 1
fi

source "$CONFIG_FILE"

# Variabile globale
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_BACKUP="$BACKUP_DIR/backup_$TIMESTAMP"
METADATA_FILE="$CURRENT_BACKUP/metadata.csv"

# Funcții utilitare
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}
create_backup_structure() {
    log_message "Creez structura de backup..."
    mkdir -p "$CURRENT_BACKUP"
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"

    # Creez fișierul CSV cu antet
    local metadata_csv="$CURRENT_BACKUP/metadata.csv"
    echo "path;checksum;permissions;owner;mtime" > "$metadata_csv"
}


find_last_backup() {
    # Exclud backup-ul curent din căutare
    LAST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" ! -name "backup_$TIMESTAMP" | sort | tail -1)
    if [ -n "$LAST_BACKUP" ] && [ -d "$LAST_BACKUP" ]; then
        log_message "Găsit backup anterior: $LAST_BACKUP"
        return 0
    else
        log_message "Nu există backup anterior. Se va crea backup complet."
        return 1
    fi
}
calculate_checksum() {
    local file="$1"
    case "$CHECKSUM_TYPE" in
        "md5")
            md5sum "$file" 2>/dev/null | cut -d' ' -f1
            ;;
        "sha256")
            sha256sum "$file" 2>/dev/null | cut -d' ' -f1
            ;;
        *)
            echo "Tip checksum necunoscut: $CHECKSUM_TYPE" >&2
            return 1
            ;;
    esac
}

file_changed() {
    local file="$1"
    local last_backup="$2"
    
    if [ -z "$last_backup" ]; then
        return 0  # Nu există backup anterior, toate fișierele sunt noi
    fi
    
    local last_checksum_file="$last_backup/checksums.txt"
    if [ ! -f "$last_checksum_file" ]; then
        return 0  # Nu există fișier de checksum anterior
    fi
    
    local current_checksum=$(calculate_checksum "$file")
    local relative_path=$(realpath --relative-to="$SOURCE_DIR" "$file")
    local last_checksum=$(grep "^$relative_path:" "$last_checksum_file" 2>/dev/null | cut -d':' -f2)
    
    if [ "$current_checksum" != "$last_checksum" ]; then
        return 0  # Fișierul s-a modificat
    else
        return 1  # Fișierul nu s-a modificat
    fi
}
backup_file() {
    local source_file="$1"
    local relative_path
    relative_path=$(realpath --relative-to="$SOURCE_DIR" "$source_file")
    local backup_file="$CURRENT_BACKUP/data/$relative_path"

    # Creez directorul dacă nu există
    mkdir -p "$(dirname "$backup_file")"

    # Copiez fișierul păstrând atributele
    cp -p "$source_file" "$backup_file"

    # Colectez toate metadatele necesare
    local checksum
    checksum=$(calculate_checksum "$source_file")

    local permissions
    permissions=$(stat -c "%a" "$source_file")

    local owner
    owner=$(stat -c "%U:%G" "$source_file")

    local mtime
    mtime=$(stat -c "%Y" "$source_file")

    # Scriu într-un singur rând CSV
    echo "$relative_path;$checksum;$permissions;$owner;$mtime" >> "$CURRENT_BACKUP/metadata.csv"

}

verify_backup() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/metadata.csv"

    log_message "Verific integritatea backup-ului $backup_dir..."

    if [ ! -f "$metadata_file" ]; then
        log_message "Eroare: Fișierul metadata.csv nu există"
        return 1
    fi

    local errors=0
    local total=0

    tail -n +2 "$metadata_file" | while IFS=';' read -r path checksum permissions owner mtime; do
        ((total++))
        local full_path="$backup_dir/data/$path"

        if [ ! -f "$full_path" ]; then
            log_message "Eroare: Lipsește fișierul $path"
            ((errors++))
            continue
        fi

        local actual_checksum=""
        case "$CHECKSUM_TYPE" in
            "md5")
                actual_checksum=$(md5sum "$full_path" 2>/dev/null | cut -d' ' -f1)
                ;;
            "sha256")
                actual_checksum=$(sha256sum "$full_path" 2>/dev/null | cut -d' ' -f1)
                ;;
        esac

        if [ "$actual_checksum" != "$checksum" ]; then
            log_message "Eroare checksum: $path"
            ((errors++))
        fi
    done

    log_message "Verificare completă: $errors erori din $total fișiere"

    if [ "$errors" -eq 0 ]; then
        log_message "✅ Backup-ul este integru!"
        return 0
    else
        log_message "❌ Backup-ul are erori de integritate!"
        return 1
    fi
}

perform_backup() {
    log_message "Încep procesul de backup..."
    
    if find_last_backup; then
        INCREMENTAL=true
        log_message "Efectuez backup incremental"
    else
        INCREMENTAL=false
        log_message "Efectuez backup complet"
    fi

    mkdir -p "$CURRENT_BACKUP/data"
    
    local file_count=0
    local backed_up_count=0

    #  Construiește lista de excluderi O DATĂ
    EXCLUDE_ARGS=()
    for pattern in $EXCLUDE_PATTERNS; do
        EXCLUDE_ARGS+=( ! -name "$pattern" )
    done

    # Parcurg toate fișierele filtrate
    while IFS= read -r -d '' file; do
        ((file_count++))
        
        if [ -f "$file" ]; then
            if ! $INCREMENTAL || file_changed "$file" "$LAST_BACKUP"; then
                backup_file "$file"
                ((backed_up_count++))
                log_message "Backup: $file"
            fi
        fi

        if (( file_count % 100 == 0 )); then
            log_message "Procesate: $file_count fișiere, backup: $backed_up_count"
        fi

    done < <(find "$SOURCE_DIR" -type f "${EXCLUDE_ARGS[@]}" -print0)

    log_message "Backup finalizat: $backed_up_count/$file_count fișiere"
}


create_archive() {
    if [ "$CREATE_ARCHIVE" = "true" ]; then
        log_message "Creez arhiva..."
        cd "$BACKUP_DIR"
        tar -czf "backup_$TIMESTAMP.tar.gz" "backup_$TIMESTAMP"
        if [ $? -eq 0 ]; then
            log_message "Arhiva creată cu succes: backup_$TIMESTAMP.tar.gz"
            if [ "$KEEP_UNCOMPRESSED" = "false" ]; then
                rm -rf "backup_$TIMESTAMP"
                log_message "Șters backup necomprimat"
            fi
        else
            log_message "Eroare la crearea arhivei!"
        fi
    fi
}
encrypt_backup() {
    if [ "$ENCRYPT_BACKUP" = "true" ]; then
        # Dacă parola nu e setată, o cerem de la utilizator
        if [ -z "$ENCRYPTION_PASSWORD" ]; then
            log_message "⚠️ Variabila ENCRYPTION_PASSWORD este goală. Cer parola din terminal..."
            read -s -p "Introduceți parola pentru criptarea backup-ului: " ENCRYPTION_PASSWORD
            echo
        else
            log_message "✅ Parola pentru criptare a fost primită din mediul extern."
        fi

        log_message "Criptez backup-ul..."
        if [ -f "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz" ]; then
            openssl aes-256-cbc -salt -in "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz" \
                -out "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz.enc" \
                -k "$ENCRYPTION_PASSWORD"
            if [ $? -eq 0 ]; then
                log_message "Backup criptat cu succes"
                rm "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
            else
                log_message "Eroare la criptarea backup-ului!"
            fi
        fi
    fi
}

verify_encrypted_backup() {
    if [ "$ENCRYPT_BACKUP" = "true" ]; then
        local encrypted_file="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz.enc"

        if [ -f "$encrypted_file" ]; then
            log_message "Verific backup-ul criptat..."

            # Tentaivă de decriptare și listare conținut
            if openssl aes-256-cbc -d -in "$encrypted_file" -k "$ENCRYPTION_PASSWORD" -out - 2>/dev/null | tar -tzf - &>/dev/null; then
                log_message "✅ Verificare reușită: Backup-ul criptat este valid."
            else
                log_message "❌ Eroare: Backup-ul criptat nu a putut fi verificat! Poate fi corupt sau parola este greșită."
            fi
        fi
    fi
}

cleanup_old_backups() {
    if [ "$CLEANUP_OLD" = "true" ] && [ "$KEEP_BACKUPS" -gt 0 ]; then
        log_message "Curăț backup-uri vechi..."
        local backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | wc -l)
        
        if [ "$backup_count" -gt "$KEEP_BACKUPS" ]; then
            local to_delete=$((backup_count - KEEP_BACKUPS))
            find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | sort | head -n "$to_delete" | while read -r old_backup; do
                log_message "Șterge backup vechi: $old_backup"
                rm -rf "$old_backup"
            done
        fi
    fi
}

# Funcția principală
main() {
    log_message "=== Începe backup-ul ==="
    
    # Verificări preliminare
    if [ ! -d "$SOURCE_DIR" ]; then
        log_message "Eroare: Directorul sursă $SOURCE_DIR nu există!"
        exit 1
    fi
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "Creez directorul de backup: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Execut procesul de backup
    create_backup_structure
    perform_backup
    verify_backup "$CURRENT_BACKUP"
    create_archive
    encrypt_backup
    verify_encrypted_backup
    cleanup_old_backups
    
    log_message "=== Backup finalizat cu succes ==="
    log_message "Locația backup: $CURRENT_BACKUP"
}

# Verifică dacă scriptul este executat direct
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi