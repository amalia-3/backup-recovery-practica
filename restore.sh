#!/bin/bash

# Script de restore pentru sistemul de backup


# Încărcare configurație
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Eroare: Fișierul de configurație $CONFIG_FILE nu a fost găsit!"
    exit 1
fi

source "$CONFIG_FILE"

# Variabile globale
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
LOG_FILE="$BACKUP_DIR/restore.log"

# Funcții utilitare
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

show_usage() {
    echo "Utilizare: $0 [opțiuni]"
    echo "Opțiuni:"
    echo "  -l, --list              Listează backup-urile disponibile"
    echo "  -r, --restore BACKUP    Restaurează backup-ul specificat"
    echo "  -d, --destination DIR   Directorul destinație pentru restore"
    echo "  -f, --file FILE         Restaurează doar fișierul specificat"
    echo "  -v, --verify BACKUP     Verifică integritatea backup-ului"
    echo "  --list-files BACKUP     Listează fișierele dintr-un backup"
    echo "  -h, --help              Afișează acest mesaj"
    echo ""
    echo "Exemple:"
    echo "  $0 -l                                    # Listează backup-urile"
    echo "  $0 -r backup_20241209_143022             # Restaurează backup-ul complet"
    echo "  $0 -r backup_20241209_143022 -d /tmp     # Restaurează în /tmp"
    echo "  $0 -f document.txt -r backup_20241209_143022  # Restaurează doar document.txt"
}

list_backups() {
    log_message "Listez backup-urile disponibile..."
    echo "Backup-uri disponibile în $BACKUP_DIR:"
    echo "----------------------------------------"
    
    # Caută directoare de backup
    local backups_found=false
    for backup_dir in "$BACKUP_DIR"/backup_*; do
        if [ -d "$backup_dir" ]; then
            backups_found=true
            local backup_name=$(basename "$backup_dir")
            local backup_date=$(echo "$backup_name" | sed 's/backup_//' | sed 's/_/ /')
            local file_count=0
            if [ -f "$backup_dir/metadata.csv" ]; then
                file_count=$(($(wc -l < "$backup_dir/metadata.csv") - 1))
            fi

            echo "  $backup_name (Data: $backup_date, Fișiere: $file_count)"
        fi
    done
    
    # Caută arhive
    for archive in "$BACKUP_DIR"/backup_*.tar.gz; do
        if [ -f "$archive" ]; then
            backups_found=true
            local archive_name=$(basename "$archive" .tar.gz)
            local archive_date=$(echo "$archive_name" | sed 's/backup_//' | sed 's/_/ /')
            echo "  $archive_name (Arhivă, Data: $archive_date)"
        fi
    done
    
    # Caută arhive criptate
    for encrypted in "$BACKUP_DIR"/backup_*.tar.gz.enc; do
        if [ -f "$encrypted" ]; then
            backups_found=true
            local enc_name=$(basename "$encrypted" .tar.gz.enc)
            local enc_date=$(echo "$enc_name" | sed 's/backup_//' | sed 's/_/ /')
            echo "  $enc_name (Criptat, Data: $enc_date)"
        fi
    done
    
    if [ "$backups_found" = false ]; then
        echo "  Nu s-au găsit backup-uri în $BACKUP_DIR"
    fi
}

decrypt_backup() {
    local encrypted_file="$1"
    local decrypted_file="$2"
    
    if [ ! -f "$encrypted_file" ]; then
        log_message "Eroare: Fișierul criptat nu există: $encrypted_file"
        return 1
    fi
    
    if [ -z "$ENCRYPTION_PASSWORD" ]; then
        echo -n "Introduceți parola pentru decriptare: "
        read -s password
        echo
    else
        password="$ENCRYPTION_PASSWORD"
    fi
    
    log_message "Decriptez backup-ul..."
    openssl aes-256-cbc -d -in "$encrypted_file" -out "$decrypted_file" -k "$password"
    
    if [ $? -eq 0 ]; then
        log_message "Backup decriptat cu succes"
        return 0
    else
        log_message "Eroare la decriptarea backup-ului!"
        return 1
    fi
}

extract_archive() {
    local archive_file="$1"
    local extract_dir="$2"
    
    log_message "Extrag arhiva $archive_file..."
    cd "$extract_dir"
    tar -xzf "$archive_file"
    
    if [ $? -eq 0 ]; then
        log_message "Arhiva extrasă cu succes"
        return 0
    else
        log_message "Eroare la extragerea arhivei!"
        return 1
    fi
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
        # Ignoră linia de antet
        [[ "$path" == "cale_relativa" ]] && continue

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
    done < <(tail -n +2 "$metadata_file")

    log_message "Verificare completă: $errors erori din $total fișiere"

    if [ "$errors" -eq 0 ]; then
        log_message "Backup-ul este integru!"
        echo "INTEGRU"
        return 0
    else
        log_message "Backup-ul are erori de integritate!"
        echo "ERORI"
        return 1
    fi

}

restore_permissions() {
    local backup_dir="$1"
    local dest_dir="$2"
    local metadata_file="$backup_dir/metadata.csv"

    log_message "Restabilesc permisiuni, owner și timpuri pentru fișiere..."

    if [ ! -f "$metadata_file" ]; then
        log_message "Eroare: Fișierul metadata.csv nu există"
        return 1
    fi

    tail -n +2 "$metadata_file" | while IFS=';' read -r path checksum permissions owner mtime; do
        local full_path="$dest_dir/$path"
        local user_group=$(echo "$owner" | tr ':' ' ')

        if [ -f "$full_path" ]; then
            chmod "$permissions" "$full_path" 2>/dev/null

            if [ "$EUID" -eq 0 ]; then
                chown $user_group "$full_path" 2>/dev/null
            fi

            touch -d @"$mtime" "$full_path" 2>/dev/null
        fi
    done

    log_message "Restaurarea permisiunilor completă."
}
list_files() {
    local backup_name="$1"
    local backup_path="$BACKUP_DIR/$backup_name"
    local temp_dir=""
    local cleanup_temp=false

    echo "🔍 Listăm fișierele din backup: $backup_name"

    if [ -d "$backup_path" ]; then
        :
    elif [ -f "$backup_path.tar.gz" ]; then
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        extract_archive "$backup_path.tar.gz" "$temp_dir"
        backup_path="$temp_dir/$backup_name"
    elif [ -f "$backup_path.tar.gz.enc" ]; then
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        local temp_archive="$temp_dir/backup.tar.gz"
        decrypt_backup "$backup_path.tar.gz.enc" "$temp_archive"
        extract_archive "$temp_archive" "$temp_dir"
        backup_path="$temp_dir/$backup_name"
    else
        echo "Eroare: Nu am găsit backup-ul $backup_name"
        return 1
    fi

    if [ -d "$backup_path/data" ]; then
        find "$backup_path/data" -type f | sed "s|$backup_path/data/||"
    else
        echo "Nu s-au găsit fișiere salvate în backup."
        return 1
    fi

    # Cleanup
    if [ "$cleanup_temp" = true ] && [ -n "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
}


restore_backup() {
    local backup_name="$1"
    local destination="$2"
    local specific_file="$3"
    
    log_message "Încep restaurarea backup-ului: $backup_name"
    
    # Determină calea completă către backup
    local backup_path="$BACKUP_DIR/$backup_name"
    local temp_dir=""
    local cleanup_temp=false
    
    # Verifică dacă backup-ul există ca director
    if [ -d "$backup_path" ]; then
        log_message "Găsit backup director: $backup_path"
    # Verifică dacă există ca arhivă
    elif [ -f "$backup_path.tar.gz" ]; then
        log_message "Găsit backup arhivă: $backup_path.tar.gz"
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        extract_archive "$backup_path.tar.gz" "$temp_dir"
        backup_path="$temp_dir/$backup_name"
    # Verifică dacă există ca arhivă criptată
    elif [ -f "$backup_path.tar.gz.enc" ]; then
        log_message "Găsit backup criptat: $backup_path.tar.gz.enc"
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        local temp_archive="$temp_dir/backup.tar.gz"
        decrypt_backup "$backup_path.tar.gz.enc" "$temp_archive"
        extract_archive "$temp_archive" "$temp_dir"
        backup_path="$temp_dir/$backup_name"
    else
        log_message "Eroare: Backup-ul $backup_name nu a fost găsit!"
        return 1
    fi
    
    # Verifică integritatea înainte de restore
    if ! verify_backup "$backup_path"; then
        log_message "Avertisment: Backup-ul are probleme de integritate!"
        echo -n "Continuați oricum? (y/n): "
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            return 1
        fi
    fi
    
    # Creează directorul destinație dacă nu există
    mkdir -p "$destination"
    
    # Restaurează fișierele
    if [ -n "$specific_file" ]; then
    # Caută fișierul indiferent de subdirector
    local source_file
    source_file=$(find "$backup_path/data" -type f -name "$(basename "$specific_file")" | head -n 1)

    if [ -n "$source_file" ] && [ -f "$source_file" ]; then
        # Cale relativă pentru destinație
        local relative_path=${source_file#"$backup_path/data/"}
        local dest_file="$destination/$relative_path"

        mkdir -p "$(dirname "$dest_file")"
        cp -p "$source_file" "$dest_file"
        log_message "Restaurat fișier: $relative_path"
    else
        log_message "Eroare: Fișierul $specific_file nu a fost găsit în backup"
        return 1
    fi

    else
        # Restaurează toate fișierele
        if [ -d "$backup_path/data" ]; then
            cp -rp "$backup_path/data/"* "$destination/"
            log_message "Restaurate toate fișierele în $destination"
        else
            log_message "Eroare: Nu s-au găsit date în backup"
            return 1
        fi
    fi
    
    # Restaurează permisiunile
    restore_permissions "$backup_path" "$destination"
    
    # Curăță fișierele temporare
    if [ "$cleanup_temp" = true ] && [ -n "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
    
    log_message "Restaurare completă cu succes!"
    return 0
}

# Procesare argumente
BACKUP_NAME=""
DESTINATION=""
SPECIFIC_FILE=""
ACTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--list)
            ACTION="list"
            shift
            ;;
        -r|--restore)
            ACTION="restore"
            BACKUP_NAME="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -f|--file)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        -v|--verify)
            ACTION="verify"
            BACKUP_NAME="$2"
            shift 2
            ;;
        --list-files)
            ACTION="list-files"
            BACKUP_NAME="$2"
            shift 2
            ;;
  
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Opțiune necunoscută: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Execută acțiunea
case "$ACTION" in
    "list")
        list_backups
        ;;
    "restore")
        if [ -z "$BACKUP_NAME" ]; then
            echo "Eroare: Trebuie să specifici numele backup-ului pentru restaurare"
            show_usage
            exit 1
        fi
        
        if [ -z "$DESTINATION" ]; then
            DESTINATION=$(zenity --file-selection --directory --title="Alege un director pentru restaurare completă")
            if [ -z "$DESTINATION" ]; then
                zenity --error --text="Nu ai selectat niciun director. Restaurarea a fost anulată."
                exit 1
            fi
        fi

        
        restore_backup "$BACKUP_NAME" "$DESTINATION" "$SPECIFIC_FILE"
        ;;
    
        "verify")
    if [ -z "$BACKUP_NAME" ]; then
        echo "Eroare: Trebuie să specifici numele backup-ului pentru verificare"
        show_usage
        exit 1
    fi

    backup_path="$BACKUP_DIR/$BACKUP_NAME"
    temp_dir=""
    cleanup_temp=false

    if [ -d "$backup_path" ]; then
        :
    elif [ -f "$backup_path.tar.gz" ]; then
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        extract_archive "$backup_path.tar.gz" "$temp_dir"

        if [ -f "$temp_dir/metadata.csv" ] && [ -d "$temp_dir/data" ]; then
            backup_path="$temp_dir"
        else
            subdir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            if [ -f "$subdir/metadata.csv" ] && [ -d "$subdir/data" ]; then
                backup_path="$subdir"
            else
                log_message "Eroare: Structura backup-ului $BACKUP_NAME nu a fost recunoscută după extragere"
                echo "::STATUS=ERROR"
                exit 1
            fi
        fi

    elif [ -f "$backup_path.tar.gz.enc" ]; then
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        temp_archive="$temp_dir/backup.tar.gz"
        decrypt_backup "$backup_path.tar.gz.enc" "$temp_archive"
        extract_archive "$temp_archive" "$temp_dir"

        if [ -f "$temp_dir/metadata.csv" ] && [ -d "$temp_dir/data" ]; then
            backup_path="$temp_dir"
        else
            subdir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            if [ -f "$subdir/metadata.csv" ] && [ -d "$subdir/data" ]; then
                backup_path="$subdir"
            else
                log_message "Eroare: Structura backup-ului $BACKUP_NAME nu a fost recunoscută după decriptare"
                echo "::STATUS=ERROR"
                exit 1
            fi
        fi
    else
        log_message "Eroare: Backup-ul $BACKUP_NAME nu a fost găsit!"
        echo "::STATUS=ERROR"
        exit 1
    fi

    verify_backup "$backup_path"
    result=$?

    if [ "$cleanup_temp" = true ] && [ -n "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi

    if [ "$result" -eq 0 ]; then
        echo "::STATUS=OK"
    else
        echo "::STATUS=ERROR"
    fi
    ;;

    "list-files")
        if [ -z "$BACKUP_NAME" ]; then
            echo "Eroare: Trebuie să specifici numele backup-ului pentru listare fișiere"
            exit 1
        fi
        list_files "$BACKUP_NAME"
        ;;


    *)
        echo "Trebuie să specifici o acțiune!"
        show_usage
        exit 1
        ;;
esac