#!/bin/bash

# Sistem de backup incremental pentru Linux
# Autor: [Numele tău]
# Data: $(date +%Y-%m-%d)

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
METADATA_FILE="$CURRENT_BACKUP/metadata.txt"
CHECKSUM_FILE="$CURRENT_BACKUP/checksums.txt"

# Funcții utilitare
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

create_backup_structure() {
    log_message "Creez structura de backup..."
    mkdir -p "$CURRENT_BACKUP"
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"
    touch "$METADATA_FILE"
    touch "$CHECKSUM_FILE"
}

find_last_backup() {
    LAST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | sort | tail -2 | head -1)
    if [ -n "$LAST_BACKUP" ] && [ "$LAST_BACKUP" != "$CURRENT_BACKUP" ]; then
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
    local relative_path=$(realpath --relative-to="$SOURCE_DIR" "$source_file")
    local backup_file="$CURRENT_BACKUP/data/$relative_path"
    
    # Creez directorul dacă nu există
    mkdir -p "$(dirname "$backup_file")"
    
    # Copiez fișierul păstrând atributele
    cp -p "$source_file" "$backup_file"
    
    # Salvez metadata
    echo "$relative_path" >> "$METADATA_FILE"
    
    # Calculez și salvez checksum
    local checksum=$(calculate_checksum "$source_file")
    echo "$relative_path:$checksum" >> "$CHECKSUM_FILE"
    
    # Salvez permisiuni și owner
    local permissions=$(stat -c "%a" "$source_file")
    local owner=$(stat -c "%U:%G" "$source_file")
    echo "$relative_path:$permissions:$owner" >> "$CURRENT_BACKUP/permissions.txt"
}

perform_backup() {
    log_message "Încep procesul de backup..."
    
    # Găsesc ultimul backup
    if find_last_backup; then
        INCREMENTAL=true
        log_message "Efectuez backup incremental"
    else
        INCREMENTAL=false
        log_message "Efectuez backup complet"
    fi
    
    # Creez directorul pentru date
    mkdir -p "$CURRENT_BACKUP/data"
    
    local file_count=0
    local backed_up_count=0
    
    # Parcurg toate fișierele din SOURCE_DIR
    while IFS= read -r -d '' file; do
        ((file_count++))
        
        if [ -f "$file" ]; then
            if ! $INCREMENTAL || file_changed "$file" "$LAST_BACKUP"; then
                backup_file "$file"
                ((backed_up_count++))
                log_message "Backup: $file"
            fi
        fi
        
        # Progres la fiecare 100 de fișiere
        if (( file_count % 100 == 0 )); then
            log_message "Procesate: $file_count fișiere, backup: $backed_up_count"
        fi
        
    done < <(find "$SOURCE_DIR" -type f -print0)
    
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
    if [ "$ENCRYPT_BACKUP" = "true" ] && [ -n "$ENCRYPTION_PASSWORD" ]; then
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
    create_archive
    encrypt_backup
    cleanup_old_backups
    
    log_message "=== Backup finalizat cu succes ==="
    log_message "Locația backup: $CURRENT_BACKUP"
}

# Verifică dacă scriptul este executat direct
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi