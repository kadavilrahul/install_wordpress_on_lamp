# Minimal Versions - Reference Implementation

This directory contains simplified versions of the WordPress LAMP stack management scripts. These are provided for **reference and educational purposes only**.

## ⚠️ Important Notice

**For production use, please use the full-featured scripts in the main directory.**

The minimal versions here demonstrate core functionality but lack many important features:
- Advanced error handling
- Comprehensive logging
- Security hardening
- Configuration management
- Backup and recovery options
- Performance optimizations

## Files in this Directory

| File | Purpose | Lines | Status |
|------|---------|-------|--------|
| `run_minimal.sh` | Basic LAMP installer | ~190 | Reference only |
| `backup_restore_minimal.sh` | Simple backup/restore | ~280 | Reference only |
| `mysql_remote_minimal.sh` | Basic MySQL remote access | ~142 | Reference only |
| `rclone_minimal.sh` | Simple cloud backup | ~225 | Reference only |
| `miscellaneous_minimal.sh` | Basic utilities installer | ~239 | Reference only |
| `troubleshooting_minimal.sh` | Simple diagnostics | ~276 | Reference only |

## Use Cases for Minimal Versions

1. **Learning** - Understand core functionality without complexity
2. **Customization** - Starting point for custom implementations
3. **Resource-constrained environments** - When minimal footprint is required
4. **Educational purposes** - Teaching script development concepts

## Comparison with Full Versions

| Feature | Minimal | Full-Featured |
|---------|---------|---------------|
| Core functionality | ✅ | ✅ |
| Error handling | Basic | Comprehensive |
| Logging | Minimal | Detailed |
| Security features | Basic | Advanced |
| Configuration options | Limited | Extensive |
| Automation support | Basic | Full |
| Production ready | ❌ | ✅ |

## Recommendation

**Use the full-featured scripts in the parent directory** for any serious deployment. They provide:

- Production-grade reliability
- Comprehensive error handling
- Advanced security features
- Detailed logging and diagnostics
- Extensive configuration options
- Automation and monitoring support

The minimal versions are best used for learning, experimentation, or as starting points for highly customized implementations.