# Chrome Remote Desktop Ubuntu Configuration

A guide and automated script to configure Chrome Remote Desktop on Ubuntu to reuse your existing X session instead of launching a new virtual desktop.

## Problem

By default, Chrome Remote Desktop creates a new virtual X session, which means you get a separate desktop environment that's isolated from your physical display. This can be problematic if you want to:
- Access the same desktop you see on your physical monitor
- Share your existing session with all your open applications
- Avoid the overhead of running a separate X server

## Solution

This configuration modifies Chrome Remote Desktop to reuse your existing X session, allowing you to access your current desktop remotely.

## Prerequisites

- Ubuntu (tested on Ubuntu 17.10, 18.04, 20.04, 22.04, and later)
- Google Chrome browser installed
- Chrome Remote Desktop extension installed

## Installation

### Step 1: Install Chrome Remote Desktop

1. Visit [Chrome Remote Desktop](https://remotedesktop.google.com/headless) in your Chrome browser
2. Follow the installation instructions provided on that page
3. The installation will download and set up Chrome Remote Desktop on your system

### Step 2: Initial Setup

1. Open Chrome and go to [Chrome Remote Desktop](https://remotedesktop.google.com/headless)
2. Click the "Turn on" button
3. Name your device and set a PIN

## Configuration

### Automated Configuration (Recommended)

Use the provided script to automatically configure Chrome Remote Desktop:

```bash
sudo ./configure-chrome-remote-desktop.sh
```

The script will:
- Stop Chrome Remote Desktop if it's running
- Create a backup of the original configuration file
- Detect your current DISPLAY number
- Configure the resolution (default: 1920x1080, you can customize it)
- Modify the Chrome Remote Desktop configuration file
- Preserve file permissions
- Automatically restart Chrome Remote Desktop at the end

### Manual Configuration

If you prefer to configure manually:

1. **Stop Chrome Remote Desktop:**
   ```bash
   /opt/google/chrome-remote-desktop/chrome-remote-desktop --stop
   ```

2. **Edit the configuration file:**
   ```bash
   sudo nano /opt/google/chrome-remote-desktop/chrome-remote-desktop
   ```

3. **Find and modify `DEFAULT_SIZES`:**
   ```python
   DEFAULT_SIZES = "1920x1080"  # Change to your desired resolution
   ```

4. **Set the X display number:**
   First, check your current display:
   ```bash
   echo $DISPLAY
   ```
   
   Then set `FIRST_X_DISPLAY_NUMBER` to match (usually 0 or 1):
   ```python
   FIRST_X_DISPLAY_NUMBER = 0  # or 1, depending on your system
   ```

5. **Comment out the display search loop:**
   Find this section and comment it out:
   ```python
   #while os.path.exists(X_LOCK_FILE_TEMPLATE % display):
   #  display += 1
   ```

6. **Modify `launch_session()` function:**
   In the `XDesktop` class, find the `launch_session()` method and replace it with:
   ```python
   def launch_session(self, *args, **kwargs):
     self._init_child_env()
     self._setup_gnubby()
     #self._launch_server(server_args)
     #if not self._launch_pre_session():
     #  # If there was no pre-session script, launch the session immediately.
     #  self.launch_desktop_session()
     #self.server_inhibitor.record_started(MINIMUM_PROCESS_LIFETIME,
     #                                     backoff_time)
     #self.session_inhibitor.record_started(MINIMUM_PROCESS_LIFETIME,
     #                                    backoff_time)
     display = self.get_unused_display_number()
     self.child_env["DISPLAY"] = ":%d" % display
   ```

7. **Save and exit the editor**

8. **Start Chrome Remote Desktop:**
   ```bash
   /opt/google/chrome-remote-desktop/chrome-remote-desktop --start
   ```

## Usage

After configuration:

1. Go to [Chrome Remote Desktop](https://remotedesktop.google.com/headless) in your Chrome browser
2. Click on your device name
3. Enter your PIN
4. You should now see your existing desktop session, not a new virtual one

## Troubleshooting

### Display Number Issues

If you're unsure about your display number:
- Ubuntu 17.10 and lower: Usually `0`
- Ubuntu 18.04: Usually `1`
- Ubuntu 20.04+: Can be `0` or `1` depending on your setup

Check with:
```bash
echo $DISPLAY
```

The number after the colon (`:`) is your display number.

### Chrome Remote Desktop Won't Start

1. Check if it's already running:
   ```bash
   ps aux | grep chrome-remote-desktop
   ```

2. Stop it if needed:
   ```bash
   /opt/google/chrome-remote-desktop/chrome-remote-desktop --stop
   ```

3. Check the logs:
   ```bash
   cat ~/.config/chrome-remote-desktop/chrome_remote_desktop_*.log
   ```

### Resolution Issues

If the resolution doesn't match your screen:
1. Edit the configuration file
2. Change `DEFAULT_SIZES` to match your screen resolution
3. Restart Chrome Remote Desktop

## Reverting Changes

If you need to revert to the default behavior, the script automatically creates a backup of the original configuration file before making any changes. The backup is saved with a timestamp in the filename.

To restore from the backup:

1. Stop Chrome Remote Desktop:
   ```bash
   /opt/google/chrome-remote-desktop/chrome-remote-desktop --stop
   ```

2. Find your backup file (it will be in `/opt/google/chrome-remote-desktop/` with a name like `chrome-remote-desktop.backup.YYYYMMDD_HHMMSS`)

3. Restore the backup:
   ```bash
   sudo cp /opt/google/chrome-remote-desktop/chrome-remote-desktop.backup.YYYYMMDD_HHMMSS /opt/google/chrome-remote-desktop/chrome-remote-desktop
   ```

4. Start Chrome Remote Desktop:
   ```bash
   sudo /opt/google/chrome-remote-desktop/chrome-remote-desktop --start
   ```

Alternatively, you can reinstall Chrome Remote Desktop, which will restore the original configuration file.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This configuration modifies system files. Use at your own risk. Always backup your configuration before making changes.

## Acknowledgments

This configuration is based on community solutions for making Chrome Remote Desktop work with existing X sessions on Ubuntu.

