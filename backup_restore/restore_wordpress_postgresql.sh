#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help            Show this help"
    echo ""
    echo "This script combines WordPress site restore with PostgreSQL database restore."
    echo "It calls the existing restore_wordpress.sh and restore_postgresql.sh scripts."
    echo ""
    echo "The scripts will run in interactive mode to let you select:"
    echo "- Which WordPress backup to restore"
    echo "- Which PostgreSQL backup to restore"
}

main() {
    echo "====================================================================="
    echo "          Combined WordPress + PostgreSQL Restore"
    echo "====================================================================="
    echo
    
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            echo "Step 1: Running WordPress Restore..."
            echo "---------------------------------------------------------------------"
            bash "$SCRIPT_DIR/restore_wordpress.sh"
            wordpress_exit_code=$?
            
            echo
            echo "Step 2: Running PostgreSQL Restore..."
            echo "---------------------------------------------------------------------"
            bash "$SCRIPT_DIR/restore_postgresql.sh"
            postgresql_exit_code=$?
            
            echo
            echo "====================================================================="
            echo "          Combined Restore Summary"
            echo "====================================================================="
            
            if [ $wordpress_exit_code -eq 0 ]; then
                echo "✓ WordPress restore: Completed successfully (MySQL database)"
            else
                echo "✗ WordPress restore: Failed (exit code: $wordpress_exit_code)"
            fi
            
            if [ $postgresql_exit_code -eq 0 ]; then
                echo "✓ PostgreSQL restore: Completed successfully"
            else
                echo "✗ PostgreSQL restore: Failed (exit code: $postgresql_exit_code)"
            fi
            
            echo
            
            # Overall exit code
            if [ $wordpress_exit_code -eq 0 ] && [ $postgresql_exit_code -eq 0 ]; then
                echo "✓ Combined restore completed successfully!"
                echo "  Restored from {domain}_mysql_db.sql (WordPress/MySQL)"
                echo "  Restored from {domain}_postgres_db.sql (PostgreSQL)"
                exit 0
            else
                echo "✗ Combined restore completed with errors"
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