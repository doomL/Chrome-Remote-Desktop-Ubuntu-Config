#!/bin/bash

# Chrome Remote Desktop Ubuntu Configuration Script
# This script configures Chrome Remote Desktop to reuse the existing X session

set -e

CONFIG_FILE="/opt/google/chrome-remote-desktop/chrome-remote-desktop"
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Check if Chrome Remote Desktop is installed
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Chrome Remote Desktop not found at $CONFIG_FILE"
    print_info "Please install Chrome Remote Desktop first from:"
    print_info "https://remotedesktop.google.com/headless"
    exit 1
fi

print_info "Chrome Remote Desktop configuration script"
print_info "=========================================="
echo

# Stop Chrome Remote Desktop if running
print_info "Stopping Chrome Remote Desktop..."
if pgrep -f "chrome-remote-desktop" > /dev/null; then
    /opt/google/chrome-remote-desktop/chrome-remote-desktop --stop 2>/dev/null || true
    sleep 2
    print_info "Chrome Remote Desktop stopped"
else
    print_info "Chrome Remote Desktop is not running"
fi

# Create backup
print_info "Creating backup of configuration file..."
cp "$CONFIG_FILE" "$BACKUP_FILE"
print_info "Backup created: $BACKUP_FILE"

# Get current DISPLAY number
CURRENT_DISPLAY="${DISPLAY:-:0}"
DISPLAY_NUMBER=$(echo "$CURRENT_DISPLAY" | sed 's/.*:\([0-9]*\).*/\1/')

if [ -z "$DISPLAY_NUMBER" ]; then
    print_warning "Could not detect DISPLAY number, defaulting to 0"
    DISPLAY_NUMBER=0
fi

print_info "Detected DISPLAY number: $DISPLAY_NUMBER"

# Ask for resolution
echo
read -p "Enter desired resolution (default: 1920x1080): " RESOLUTION
RESOLUTION=${RESOLUTION:-1920x1080}

print_info "Setting resolution to: $RESOLUTION"
print_info "Setting display number to: $DISPLAY_NUMBER"

# Create Python script to modify the file
PYTHON_SCRIPT=$(mktemp)
cat > "$PYTHON_SCRIPT" << 'PYEOF'
import re
import sys

config_file = sys.argv[1]
resolution = sys.argv[2]
display_number = int(sys.argv[3])
temp_file = sys.argv[4]

with open(config_file, "r") as f:
    content = f.read()

# 1. Update DEFAULT_SIZES
content = re.sub(
    r'^DEFAULT_SIZES = "[^"]*"',
    'DEFAULT_SIZES = "{}"'.format(resolution),
    content,
    flags=re.MULTILINE
)

# 2. Update FIRST_X_DISPLAY_NUMBER
content = re.sub(
    r'^FIRST_X_DISPLAY_NUMBER = \d+',
    'FIRST_X_DISPLAY_NUMBER = {}'.format(display_number),
    content,
    flags=re.MULTILINE
)

# 3. Comment out the display search loop (if not already commented)
content = re.sub(
    r'^(\s+)while os\.path\.exists\(X_LOCK_FILE_TEMPLATE % display\):',
    r'\1#while os.path.exists(X_LOCK_FILE_TEMPLATE % display):',
    content,
    flags=re.MULTILINE
)
content = re.sub(
    r'^(\s+)display \+= 1',
    r'\1#  display += 1',
    content,
    flags=re.MULTILINE
)

# 4. Replace launch_session in XDesktop class
# First check if it's already correctly modified
already_modified = re.search(
    r'def launch_session\(self, \*args, \*\*kwargs\):.*?display\s*=\s*self\.get_unused_display_number\(\).*?self\.child_env\["DISPLAY"\]\s*=\s*":%d"\s*%\s*display',
    content,
    re.MULTILINE | re.DOTALL
)

if already_modified:
    print("launch_session method already correctly configured", file=sys.stderr)
else:
    # Look for the pattern: def launch_session(self, *args, **kwargs): followed by logging.info and super call
    replacement = '''  def launch_session(self, *args, **kwargs):
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
    self.child_env["DISPLAY"] = ":%d" % display'''

    # Try to find and replace the launch_session method
    # Pattern 1: Original pattern with logging.info and super call
    pattern1 = r'(  def launch_session\(self, \*args, \*\*kwargs\):\s+logging\.info\("Launching X server and X session\."\)\s+super\(XDesktop, self\)\.launch_session\(\*args, \*\*kwargs\))'
    
    # Pattern 2: Alternative pattern - function definition and super call (more flexible)
    pattern2 = r'(  def launch_session\(self, \*args, \*\*kwargs\):.*?super\(XDesktop, self\)\.launch_session\(\*args, \*\*kwargs\))'
    
    # Pattern 3: Pattern that might have different spacing
    pattern3 = r'(  def launch_session\(self, \*args, \*\*kwargs\):.*?logging\.info.*?super\(XDesktop, self\)\.launch_session)'

    replaced = False
    for pattern in [pattern1, pattern2, pattern3]:
        if re.search(pattern, content, re.MULTILINE | re.DOTALL):
            content = re.sub(
                pattern,
                replacement,
                content,
                flags=re.MULTILINE | re.DOTALL
            )
            replaced = True
            break
    
    if not replaced:
        print("Warning: Could not find original launch_session method pattern to replace", file=sys.stderr)
        print("The method may already be modified or have a different structure.", file=sys.stderr)
        print("Continuing with other modifications...", file=sys.stderr)

# Write to temp file
with open(temp_file, "w") as f:
    f.write(content)

print("Success")
PYEOF

# Run Python script
PYTHON_OUTPUT=$(python3 "$PYTHON_SCRIPT" "$CONFIG_FILE" "$RESOLUTION" "$DISPLAY_NUMBER" "$CONFIG_FILE.tmp" 2>&1)
PYTHON_EXIT=$?

if [ $PYTHON_EXIT -eq 0 ] && [ -f "$CONFIG_FILE.tmp" ]; then
    # Preserve original permissions
    ORIG_PERMS=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null || echo "755")
    # Replace original file with modified version
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    # Restore execute permissions
    chmod "$ORIG_PERMS" "$CONFIG_FILE" 2>/dev/null || chmod +x "$CONFIG_FILE"
    rm -f "$PYTHON_SCRIPT"
    print_info "Configuration file updated successfully"
    # Show any warnings from Python script
    if echo "$PYTHON_OUTPUT" | grep -q "Warning"; then
        echo "$PYTHON_OUTPUT" | grep "Warning" | while read line; do
            print_warning "$line"
        done
    fi
    if echo "$PYTHON_OUTPUT" | grep -q "already correctly configured"; then
        print_info "launch_session method was already correctly configured"
    fi
else
    print_error "Failed to modify configuration file"
    echo "$PYTHON_OUTPUT"
    rm -f "$PYTHON_SCRIPT" "$CONFIG_FILE.tmp"
    exit 1
fi

# Verify changes
echo
print_info "Verifying changes..."

if grep -q "DEFAULT_SIZES = \"$RESOLUTION\"" "$CONFIG_FILE"; then
    print_info "✓ DEFAULT_SIZES updated"
else
    print_warning "⚠ DEFAULT_SIZES may not have been updated correctly"
fi

if grep -q "FIRST_X_DISPLAY_NUMBER = $DISPLAY_NUMBER" "$CONFIG_FILE"; then
    print_info "✓ FIRST_X_DISPLAY_NUMBER updated"
else
    print_warning "⚠ FIRST_X_DISPLAY_NUMBER may not have been updated correctly"
fi

if grep -q "#while os.path.exists(X_LOCK_FILE_TEMPLATE % display):" "$CONFIG_FILE"; then
    print_info "✓ Display search loop commented out"
else
    print_warning "⚠ Display search loop may not be commented out"
fi

if grep -q "display = self.get_unused_display_number()" "$CONFIG_FILE"; then
    print_info "✓ launch_session() method updated"
else
    print_warning "⚠ launch_session() method may not have been updated correctly"
fi

echo
print_info "Configuration complete!"
echo

# Ask if user wants to start Chrome Remote Desktop
read -p "Start Chrome Remote Desktop now? (y/n, default: y): " START_NOW
START_NOW=${START_NOW:-y}

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    print_info "Starting Chrome Remote Desktop..."
    /opt/google/chrome-remote-desktop/chrome-remote-desktop --start
    if [ $? -eq 0 ]; then
        print_info "✓ Chrome Remote Desktop started successfully"
    else
        print_warning "⚠ Failed to start Chrome Remote Desktop. You can start it manually with:"
        print_info "  sudo /opt/google/chrome-remote-desktop/chrome-remote-desktop --start"
    fi
else
    print_info "To start Chrome Remote Desktop manually, run:"
    print_info "  sudo /opt/google/chrome-remote-desktop/chrome-remote-desktop --start"
fi

echo
print_info "If you need to restore the original configuration:"
print_info "  sudo cp $BACKUP_FILE $CONFIG_FILE"
echo
