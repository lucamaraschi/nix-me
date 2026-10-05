#!/bin/bash
# create-utm-vm.sh - Create a UTM VM programmatically

set -e

# Function to generate UUID
generate_uuid() {
    uuidgen
}

# Function to generate random MAC address
generate_mac() {
    printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

# Function to create Linux VM configuration
create_linux_vm() {
    local vm_name="$1"
    local memory_mb="$2"
    local cpu_count="$3"
    local disk_size_gb="$4"
    local iso_path="$5"

    local utm_dir="${HOME}/Library/Containers/com.utmapp.UTM/Data/Documents/${vm_name}.utm"
    local data_dir="${utm_dir}/Data"
    local images_dir="${utm_dir}/Images"

    # Generate UUIDs and MAC
    local vm_uuid=$(generate_uuid)
    local disk_uuid=$(generate_uuid)
    local iso_uuid=$(generate_uuid)
    local mac_address=$(generate_mac)

    echo "Creating UTM VM: $vm_name"
    echo "  Memory: ${memory_mb}MB"
    echo "  CPUs: $cpu_count"
    echo "  Disk: ${disk_size_gb}GB"
    echo "  ISO: $iso_path"

    # Create directory structure
    mkdir -p "$data_dir"
    mkdir -p "$images_dir"

    # Create disk image using UTM's qemu-img
    echo "Creating disk image..."
    local qemu_img="/Applications/UTM.app/Contents/Frameworks/qemu-img.framework/Versions/A/qemu-img"
    "$qemu_img" create -f qcow2 "${images_dir}/${disk_uuid}.qcow2" "${disk_size_gb}G"

    # Copy ISO to Images directory (or create symlink)
    echo "Linking ISO..."
    ln -sf "$iso_path" "${images_dir}/${iso_uuid}.iso"

    # Create config.plist
    echo "Generating configuration..."
    cat > "${utm_dir}/config.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Backend</key>
	<string>QEMU</string>
	<key>ConfigurationVersion</key>
	<integer>4</integer>
	<key>Display</key>
	<array>
		<dict>
			<key>ConsoleMode</key>
			<integer>0</integer>
			<key>HeightPixels</key>
			<integer>768</integer>
			<key>PixelsPerInch</key>
			<integer>80</integer>
			<key>Retina</key>
			<false/>
			<key>WidthPixels</key>
			<integer>1024</integer>
		</dict>
	</array>
	<key>Drive</key>
	<array>
		<dict>
			<key>ImageName</key>
			<string>${iso_uuid}.iso</string>
			<key>ImageType</key>
			<string>CD</string>
			<key>Interface</key>
			<string>IDE</string>
			<key>ReadOnly</key>
			<true/>
			<key>Removable</key>
			<false/>
		</dict>
		<dict>
			<key>ImageName</key>
			<string>${disk_uuid}.qcow2</string>
			<key>ImageType</key>
			<string>Disk</string>
			<key>Interface</key>
			<string>VirtIO</string>
			<key>ReadOnly</key>
			<false/>
			<key>Removable</key>
			<false/>
		</dict>
	</array>
	<key>Information</key>
	<dict>
		<key>Icon</key>
		<string>linux</string>
		<key>IconCustom</key>
		<false/>
		<key>Name</key>
		<string>${vm_name}</string>
		<key>Notes</key>
		<string>Created by nix-me</string>
		<key>UUID</key>
		<string>${vm_uuid}</string>
	</dict>
	<key>Input</key>
	<dict>
		<key>LegacyInput</key>
		<false/>
		<key>USBBus</key>
		<true/>
	</dict>
	<key>Network</key>
	<array>
		<dict>
			<key>Hardware</key>
			<string>virtio-net-pci</string>
			<key>MacAddress</key>
			<string>${mac_address}</string>
			<key>Mode</key>
			<string>Shared</string>
		</dict>
	</array>
	<key>QEMU</key>
	<dict>
		<key>Arguments</key>
		<array/>
		<key>Debug</key>
		<false/>
		<key>DirectoryShareReadOnly</key>
		<false/>
	</dict>
	<key>Serial</key>
	<array/>
	<key>Sound</key>
	<dict>
		<key>Hardware</key>
		<string>intel-hda</string>
	</dict>
	<key>System</key>
	<dict>
		<key>Architecture</key>
		<string>x86_64</string>
		<key>Boot</key>
		<dict>
			<key>UEFIBoot</key>
			<true/>
		</dict>
		<key>CPUCount</key>
		<integer>${cpu_count}</integer>
		<key>JitCacheSize</key>
		<integer>0</integer>
		<key>MemorySize</key>
		<integer>${memory_mb}</integer>
		<key>Target</key>
		<string>q35</string>
	</dict>
</dict>
</plist>
EOF

    echo "✓ VM created successfully at: $utm_dir"
    echo ""
    echo "The VM is now ready to use in UTM!"
    echo "You can start it with: utmctl start '$vm_name'"
}

# Parse command line arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <vm_name> <memory_mb> <cpu_count> <disk_size_gb> <iso_path>"
    exit 1
fi

create_linux_vm "$1" "$2" "$3" "$4" "$5"
