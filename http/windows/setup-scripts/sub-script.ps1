
# Creates the file (or updates its timestamp)
$path = "C:\Temp\packer_was_here.txt"

# If the directory does not exist, create it
$dir = Split-Path $path
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# Create/update the file
New-Item -ItemType File -Force -Path $path | Out-Null
