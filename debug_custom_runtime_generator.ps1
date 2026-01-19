$MAIN_CLASS_FILE = "client.class" 
$TEMP_DIR = "temp_extracted"
$JAVA_BIN = "" # PATH TO JAVA 11 BIN

# 1. Extract
if (Test-Path $TEMP_DIR) { Remove-Item -Recurse -Force $TEMP_DIR }
New-Item -ItemType Directory -Force -Path $TEMP_DIR
tar -xf client.jar -C $TEMP_DIR

# 2. Targeted jdeps with String Cleaning
Write-Host "Analyzing dependencies for Main Class..." -ForegroundColor Gray
$RAW_OUTPUT = & "$JAVA_BIN\jdeps.exe" --print-module-deps `
                 --ignore-missing-deps `
                 --recursive `
                 -cp "$TEMP_DIR" `
                 "$TEMP_DIR/$MAIN_CLASS_FILE" 2>$null

# CLEANING: Filter for valid module names starting with java, jdk, or javax
$VALID_MODULES = ($RAW_OUTPUT -split '[\s,]+' | Where-Object { 
    $_ -match '^(java\.|jdk\.|javax\.)[a-z0-9\.]+$' 
})

$CLEAN_MODS = $VALID_MODULES -join ","

# Safety Fallback if detection fails completely
if ([string]::IsNullOrWhiteSpace($CLEAN_MODS)) {
    Write-Host "No valid modules detected. Using desktop defaults." -ForegroundColor Yellow
    $CLEAN_MODS = "java.base,java.desktop,java.logging,java.naming"
}

# 3. Final Module Set (THE UPDATED SECTION)
# We use a HashSet to merge detected modules with a "Guaranteed Essentials" list
$FINAL_SET = New-Object System.Collections.Generic.HashSet[string]

# Add everything jdeps actually found
$CLEAN_MODS.Split(',') | ForEach-Object { if($_) { [void]$FINAL_SET.Add($_) } }

# Add the "Heavy Hitters" required for modern/obfuscated clients and nested libraries
$ESSENTIALS = @(
    "java.naming",      # Networking/JNDI
    "java.sql",         # Database/Caching
    "java.management",  # Performance/Hardware monitoring
    "java.prefs",       # FlatLaf/UI settings
    "java.instrument",  # Discord RPC/Profiling
    "java.scripting",   # Dynamic logic
    "jdk.unsupported",  # REQUIRED for sun.misc.Unsafe
    "jdk.crypto.ec",    # SSL/TLS
    "jdk.crypto.mscapi" # Windows Cert Store
)

foreach ($mod in $ESSENTIALS) { [void]$FINAL_SET.Add($mod) }

# Join them into a single sorted string for jlink
$MODULE_ARG = ($FINAL_SET | Sort-Object) -join ","

Write-Host "Final Module List: $MODULE_ARG" -ForegroundColor Green

# 4. Build Custom Runtime
if (Test-Path "./custom-runtime-test") { Remove-Item -Recurse -Force "./custom-runtime-test" }
& "$JAVA_BIN\jlink.exe" --add-modules $MODULE_ARG `
      --strip-debug --no-header-files --no-man-pages --compress=2 `
      --output ./custom-runtime-test

Write-Host "DONE! Runtime built in ./custom-runtime-test" -ForegroundColor Cyan