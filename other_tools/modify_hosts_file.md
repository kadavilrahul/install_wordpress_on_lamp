### Using the Hosts File to Access Multiple WordPress Installations
Modifying your local hosts file is a useful method for accessing different WordPress installations on separate servers.

1. Locate Your Hosts File
The location of your hosts file varies depending on your operating system:
Windows: 
```
C:\Windows\System32\drivers\etc\hosts
```
macOS and Linux:
```
/etc/hosts
```

2. Open the Hosts File with Administrative Privileges
You need administrative privileges to modify the hosts file.
Windows: Right-click on Notepad (or your preferred text editor) and select "Run as administrator." Then, open the hosts file from within Notepad.
macOS and Linux: Use the sudo command in the terminal to open the file with a text editor like nano or vim. For example:
```bash
sudo nano /etc/hosts
```

3. Add Your WordPress Installations
Add entries to the hosts file in the following format:
IP_Address   domain_name
Replace IP_Address with the IP address of your server and domain_name with the domain or subdomain you want to use to access the WordPress installation.
For your specific setup add like this at eh end of file

```
# WordPress Development Sites
135.181.193.176    nilgiristores.in
135.181.193.176    www.nilgiristores.in
135.181.203.43     silkroademart.com
135.181.203.43     www.silkroademart.com

# Email Server (if needed for testing)
94.136.184.39      mail.local
```

Steps to Implement:
 - Open Notepad as Administrator
 - Right-click on Notepad → "Run as administrator"
 - Open the hosts file
 - File → Open → Navigate to C:\Windows\System32\drivers\etc\hosts
 - Change file type to "All Files" to see the hosts file
 - Add the new entries
 - Copy the lines from the "WordPress Development Sites" section above
 - Paste them at the end of your existing hosts file
 - Save the file
 - Ctrl+S to save
 - Flush DNS cache
 - Open Command Prompt as administrator
 - Run: ipconfig /flushdns