#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --site <site_name>    Backup specific WordPress site + PostgreSQL"
    echo "  --all                 Backup all WordPress sites + PostgreSQL"
    echo "  --first               Backup first WordPress site + PostgreSQL"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --site nilgiristores.in"
    echo "  $0 --all"
    echo "  $0 --first"
    echo ""
    echo "This script combines WordPress site backup with PostgreSQL database backup."
    echo "It calls the existing backup_wordpress.sh and backup_postgresql.sh scripts."
}

main() {
    echo "====================================================================="
    echo "          Combined WordPress + PostgreSQL Backup"
    echo "====================================================================="
    echo
    
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --site|--all|--first|"")
            echo "Step 1: Running PostgreSQL Backup..."
            echo "---------------------------------------------------------------------"
            bash "$SCRIPT_DIR/backup_postgresql.sh"
            postgresql_exit_code=$?
            
            echo
            echo "Step 2: Running WordPress Backup..."
            echo "---------------------------------------------------------------------"
            bash "$SCRIPT_DIR/backup_wordpress.sh" "$@"
            wordpress_exit_code=$?
            
            # Clean up PostgreSQL dump files after WordPress backup includes them in tar
            echo
            echo "Step 3: Cleaning up PostgreSQL dump files..."
            echo "---------------------------------------------------------------------"
            for domain_dir in /var/www/*; do
                if [[ -d "$domain_dir" ]]; then
                    domain_name=$(basename "$domain_dir")
                    postgres_dump="$domain_dir/${domain_name}_postgres_db.sql"
                    if [[ -f "$postgres_dump" ]]; then
                        rm -f "$postgres_dump"
                        echo "Removed: $postgres_dump"
                    fi
                fi
            done
            
            echo
            echo "====================================================================="
            echo "          Combined Backup Summary"
            echo "====================================================================="
            
            if [ $postgresql_exit_code -eq 0 ]; then
                echo "✓ PostgreSQL backup: Completed successfully"
            else
                echo "✗ PostgreSQL backup: Failed (exit code: $postgresql_exit_code)"
            fi
            
            if [ $wordpress_exit_code -eq 0 ]; then
                echo "✓ WordPress backup: Completed successfully"
            else
                echo "✗ WordPress backup: Failed (exit code: $wordpress_exit_code)"
            fi
            
            echo
            
            # Overall exit code
            if [ $postgresql_exit_code -eq 0 ] && [ $wordpress_exit_code -eq 0 ]; then
                echo "✓ Combined backup completed successfully!"
                echo "  PostgreSQL dump: {domain}_postgres_db.sql"
                echo "  MySQL dump: {domain}_mysql_db.sql (if applicable)"
                echo "  Both dumps are included in WordPress backup archive"
                exit 0
            else
                echo "✗ Combined backup completed with errors"
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"