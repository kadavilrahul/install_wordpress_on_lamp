# 🌐 Apache2 SSL Domain Setup Helper

A collection of scripts to automate HTML domain/subdomain setup on Debian systems with Apache2 and SSL certification.

## 🚀 Features

The scripts handle the complete setup process including Apache2 configuration, directory structure creation, and SSL certification via Certbot, making domain/subdomain deployment quick and secure.

## 📋 Prerequisites

* 🖥️ Debian-based system (Debian/Ubuntu)
* 🔑 Root/sudo privileges
* 🌐 Registered domain name
* 📝 DNS records pointing to your server IP

## 🛠️ Installation

1. Clone the repository:

```bash
git clone https://github.com/kadavilrahul/apache_and_ssl.git && cd apache_and_ssl
```

2. Execute the appropriate script:

For main domain:
```bash
bash maindomain.sh
```

For subdomain:
```bash
bash subdomain.sh
```

## 💡 Script Workflow

During execution, you'll be prompted for:
* 🔹 Subdomain name (e.g., `new.example.com`)
* 🔹 Main domain name (e.g., `example.com`)
* 🔹 Web root path (default: `/var/www/$SUBDOMAIN`)
* 🔹 Apache configuration path (default: `/etc/apache2/sites-available/$SUBDOMAIN.conf`)

The script automatically:
* 📦 Updates system packages
* 🔧 Installs Apache2, Certbot, and Python3-Certbot-Apache
* 📁 Creates and configures web directories
* 📄 Sets up Apache virtual host
* 🔒 Obtains SSL certification

## ✅ Verification

To verify SSL certificate installation:

```bash
sudo certbot certificates
```

## ⚙️ Configuration Options

Customize these variables either in the script or through prompts:
* 🔹 SUBDOMAIN
* 🔹 MAIN_DOMAIN
* 🔹 WEB_ROOT
* 🔹 APACHE_CONF

## ⚠️ Important Notes

* 🔹 Ensure proper DNS configuration before script execution
* 🔹 Valid domain registration required
* 🔹 DNS records must point to your server IP

## 🔐 Security Best Practices

* 🔒 SSL certification via Certbot ensures HTTPS security
* 🔄 Regular system updates recommended
* 🛡️ Consider implementing additional security measures:
  * Firewall configuration
  * Regular system backups
  * Security monitoring

## 📜 License

MIT License

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

For issues and feature requests, please use the GitHub Issues page.
