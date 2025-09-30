# Cafe Grader Installation Script

An automated installation script for the [Cafe Grader](https://github.com/nattee/cafe-grader-web) system - a web-based programming contest grading platform.

## Overview

This script automates the complete installation and configuration of Cafe Grader on Ubuntu/Debian systems. It handles all dependencies, database setup, system configuration, and service management to get a fully functional grading system running.

## Features

- **Fully Automated**: One-script installation with interactive configuration
- **Complete Setup**: Installs all dependencies, configures services, and sets up databases
- **Production Ready**: Configures systemd services, security settings, and performance optimizations
- **Helper Scripts**: Generates start/stop/status scripts for easy management
- **Secure Configuration**: Sets up proper user permissions and database security

## Prerequisites

- Ubuntu 18.04+ or Debian 10+ (recommended)
- Root/sudo access
- Internet connection for package downloads
- At least 4GB RAM and 10GB disk space

## Quick Start

1. **Download the script:**
   ```bash
   curl -O https://raw.githubusercontent.com/folkiesss/grader-install-script/main/grader-install.sh
   chmod +x grader-install.sh
   ```

2. **Run the installation:**
   ```bash
   ./grader-install.sh
   ```

3. **Follow the interactive prompts** to configure your installation

4. **Reboot your system** (required for kernel changes)

5. **Start Cafe Grader:**
   ```bash
   ~/cafe_grader/start_grader.sh
   ```

## Configuration Options

During installation, you'll be prompted to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Main Database Name | `grader` | Primary MySQL database |
| Queue Database Name | `grader_queue` | Queue management database |
| Database Username | `grader_user` | MySQL user for the application |
| Database Password | `grader_pass` | MySQL password (hidden input) |
| Installation Directory | `~/cafe_grader` | Where to install the application |
| Number of Workers | `4` | Grader worker processes |
| Web Server Port | `3000` | HTTP port for the web interface |

## What Gets Installed

### System Packages
- **Web Server**: Apache2 with development headers
- **Database**: MySQL Server
- **Runtime**: Node.js 22.x, Ruby (from .ruby-version)
- **Development Tools**: Git, build essentials, various libraries

### Security & Isolation
- **IOI Isolate**: Secure sandbox for code execution
- **System Hardening**: Disabled swap, address space randomization
- **cgroup Memory**: Kernel configuration for resource control

### Application Components
- **Cafe Grader Web**: Main web application
- **Solid Queue**: Background job processing
- **Database Schema**: Properly migrated and seeded
- **Asset Pipeline**: Precompiled for production

### System Services
- `solid_queue.service`: Background job processor
- `isolate.service`: Security sandbox service
- `set-ioi-isolate.service`: System configuration service

## Post-Installation

### Generated Helper Scripts

The installer creates convenient management scripts in your installation directory:

```bash
~/cafe_grader/start_grader.sh    # Start all services
~/cafe_grader/stop_grader.sh     # Stop all services
~/cafe_grader/status_grader.sh   # Check service status
```

### Configuration Files

Your installation details are saved to:
- `~/cafe_grader/installation_config.txt` - Complete configuration record
- `~/cafe_grader/web/config/database.yml` - Database configuration
- `~/cafe_grader/web/config/worker.yml` - Worker configuration

### Accessing the Application

After installation and reboot:
1. Start the services: `~/cafe_grader/start_grader.sh`
2. Open your browser to: `http://localhost:3000` (or your configured port)
3. Default admin login is typically created during the seed process

## System Requirements

### Minimum
- 2 CPU cores
- 4GB RAM
- 10GB disk space
- Ubuntu 18.04+

### Recommended
- 4+ CPU cores
- 8GB+ RAM
- 20GB+ disk space
- SSD storage for better I/O performance

## Troubleshooting

### Common Issues

**Installation fails during RVM setup:**
```bash
# Log out and log back in, then run:
source /etc/profile.d/rvm.sh
./grader-install.sh
```

**Services won't start after reboot:**
```bash
# Check service status:
sudo systemctl status solid_queue
sudo systemctl status isolate

# Restart services:
sudo systemctl restart solid_queue
~/cafe_grader/start_grader.sh
```

**Database connection errors:**
```bash
# Verify MySQL is running:
sudo systemctl status mysql

# Test database connection:
mysql -u grader_user -p grader
```

### Log Files

Check these locations for debugging:
- Application logs: `~/cafe_grader/web/log/`
- System logs: `sudo journalctl -u solid_queue`
- Installation output: Terminal output during script execution

## Security Notes

- The script disables swap and address space randomization for grading security
- Database passwords are stored in plain text in config files (consider encryption for production)
- The web server runs on all interfaces (0.0.0.0) - configure firewall accordingly
- Default credentials should be changed after installation

## Contributing

This installation script is designed to work with the official [Cafe Grader](https://github.com/nattee/cafe-grader-web) project. For issues with the grader itself, please refer to the main project repository.

For script-specific issues:
1. Check the troubleshooting section above
2. Verify your system meets the prerequisites
3. Run with verbose output: `bash -x grader-install.sh`

## License

This installation script is provided as-is for educational and development purposes. Please refer to the [Cafe Grader project](https://github.com/nattee/cafe-grader-web) for licensing information about the main application.

## Acknowledgments

- [Cafe Grader](https://github.com/nattee/cafe-grader-web) - The main grading platform
- [IOI Isolate](https://github.com/ioi/isolate) - Secure sandbox system
- Ubuntu/Debian communities for package management and system tools