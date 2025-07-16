#!/bin/bash

# Verifică dacă zenity este instalat
if ! command -v zenity &> /dev/null; then
    echo "Zenity nu este instalat. Instalează-l cu: sudo apt install zenity"
    exit 1
fi

# Director backup implicit (dacă nu e setat altfel)
CONFIG_FILE="config.conf"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

BACKUP_DIR="${BACKUP_DIR:-./backups}"

while true; do
    opt=$(zenity --list \
        --title="Meniu Backup & Restore" \
        --text="Alege o opțiune:" \
        --column="Opțiune" \
        "1. Creează backup" \
        "2. Restaurează complet" \
        "3. Restaurează fișier specific" \
        "4. Verifică backup" \
        "5. Listează backup-uri" \
        "0. Ieșire" \
        --height=300 --width=400)

    case "$opt" in
        "1. Creează backup")
        ENCRYPT_BACKUP_LINE=$(grep '^ENCRYPT_BACKUP=' config.conf 2>/dev/null)
        if echo "$ENCRYPT_BACKUP_LINE" | grep -q 'true'; then
            password=$(zenity --entry --title="Parolă criptare" --text="Introdu parola pentru criptarea backup-ului:" --hide-text)
            [ -z "$password" ] && continue
            export ENCRYPTION_PASSWORD="$password"
        fi

        source ./backup.sh
        main

        zenity --info --title="Backup" --text="✅ Backup finalizat cu succes!"
        ;;


        "2. Restaurează complet")
            backup_name=$(ls "$BACKUP_DIR" | grep -E '^backup_.*(\.tar\.gz|\.tar\.gz\.enc)?$' | \
                sed -E 's/\.tar\.gz(\.enc)?$//' | sort -u | \
                zenity --list --title="Selectează backup" --column="Backup-uri disponibile")
            [ -z "$backup_name" ] && continue

            if [ -f "$BACKUP_DIR/$backup_name.tar.gz.enc" ]; then
                password=$(zenity --entry --title="Parolă decriptare" --text="Backup criptat - introdu parola:" --hide-text)
                [ -z "$password" ] && continue
                export ENCRYPTION_PASSWORD="$password"
            fi

            destination=$(zenity --file-selection --directory --title="Selectează destinația pentru restaurare completă")
            [ -z "$destination" ] && continue


            "$SCRIPT_DIR/restore.sh" -r "$backup_name" -d "$destination"
            zenity --info --title="Restaurare completă" --text="✅ Restaurarea s-a finalizat!"
            ;;

        "3. Restaurează fișier specific")
        backup_name=$(ls "$BACKUP_DIR" | grep -E '^backup_.*(\.tar\.gz|\.tar\.gz\.enc)?$' | \
            sed -E 's/\.tar\.gz(\.enc)?$//' | sort -u | \
            zenity --list --title="Selectează backup" --column="Backup-uri disponibile")
        [ -z "$backup_name" ] && continue

        if [ -f "$BACKUP_DIR/$backup_name.tar.gz.enc" ]; then
            password=$(zenity --entry --title="Parolă decriptare" --text="Backup criptat - introdu parola:" --hide-text)
            [ -z "$password" ] && continue
            export ENCRYPTION_PASSWORD="$password"
        fi

        # 🧾 Aflăm fișierele din backup
        file_list=$("$SCRIPT_DIR/restore.sh" --list-files "$backup_name")
        selected_file=$(echo "$file_list" | zenity --list --title="Fișiere disponibile" --column="Fișier" --height=400 --width=600)
        [ -z "$selected_file" ] && continue

        destination=$(zenity --file-selection --directory --title="Selectează destinația")
        [ -z "$destination" ] && continue


        "$SCRIPT_DIR/restore.sh" -r "$backup_name" -f "$selected_file" -d "$destination"
        zenity --info --title="Restaurare fișier" --text="✅ Fișierul a fost restaurat!"
        ;;

        "4. Verifică backup")
    backup_name=$(ls "$BACKUP_DIR" | grep -E '^backup_.*(\.tar\.gz|\.tar\.gz\.enc)?$' | \
        sed -E 's/\.tar\.gz(\.enc)?$//' | sort -u | \
        zenity --list --title="Selectează backup" --column="Backup-uri disponibile")
    [ -z "$backup_name" ] && continue

    if [ -f "$BACKUP_DIR/$backup_name.tar.gz.enc" ]; then
        password=$(zenity --entry --title="Parolă decriptare" --text="Backup criptat - introdu parola:" --hide-text)
        [ -z "$password" ] && continue
        export ENCRYPTION_PASSWORD="$password"
    fi

    result=$("$SCRIPT_DIR/restore.sh" --verify "$backup_name" 2>&1)

    if echo "$result" | grep -q "::STATUS=OK"; then
        zenity --info --title="Verificare" --text="✅ Backup-ul este integru!"
    else
        zenity --warning --title="Verificare" --text="⚠️ Backup-ul are erori! Vezi terminalul pentru detalii."
    fi
    ;;

        "5. Listează backup-uri")
            lista=$("$SCRIPT_DIR/restore.sh" --list)
            zenity --info --title="Backup-uri disponibile" --text="$lista"
            ;;

        "0. Ieșire")
            break
            ;;

        *) ;;
    esac
done
