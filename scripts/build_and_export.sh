#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Configuration — can be overridden through the environment
: "${PROJECT_NAME:=Leeway}"
: "${SCHEME_NAME:=Leeway}"
: "${EXPORT_METHOD:=developer-id}"
: "${TEAM_ID:=DR3DF4J982}"
: "${OUTPUT_ROOT:=$HOME/Downloads}"
###############################################################################

# Locate the project: Xcode passes its own variables, the command line does not
if [ -n "${PROJECT_FILE_PATH:-}" ]; then
    PROJECT_PATH="${PROJECT_FILE_PATH}"
elif [ -n "${SRCROOT:-}" ]; then
    PROJECT_PATH="${SRCROOT}/${PROJECT_NAME}.xcodeproj"
else
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    PROJECT_PATH="${SCRIPT_DIR}/../${PROJECT_NAME}.xcodeproj"
fi

###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BOX_WIDTH=56

# A run of `count` copies of `char`
function rule {
  local count="$1" char="$2" run
  printf -v run '%*s' "${count}" ''
  echo "${run// /${char}}"
}

# Draw a centred title inside a box the width of BOX_WIDTH
function box {
  local text="$1"
  local left=$(( (BOX_WIDTH - ${#text}) / 2 ))
  local right=$(( BOX_WIDTH - ${#text} - left ))
  local line
  line="$(rule "${BOX_WIDTH}" '═')"
  echo -e "${BLUE}╔${line}╗${NC}"
  printf "${BLUE}║${NC}%*s%s%*s${BLUE}║${NC}\n" "${left}" '' "${text}" "${right}" ''
  echo -e "${BLUE}╚${line}╝${NC}"
}

# Function to send notification and play bell
function notify {
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    osascript -e 'display notification "Build and export completed successfully ✅" with title "Build Script"' 2>/dev/null || true
    echo -e "${GREEN}✅ SUCCESS${NC}"
  else
    osascript -e 'display notification "Build or export failed ❌" with title "Build Script"' 2>/dev/null || true
    echo -e "${RED}❌ FAILED${NC}"
  fi
  echo -e "\a"
}

trap notify EXIT

# Validate project exists
if [ ! -d "${PROJECT_PATH}" ]; then
    echo -e "${RED}error: Project not found at: ${PROJECT_PATH}${NC}"
    exit 1
fi

mkdir -p "${OUTPUT_ROOT}"

# Prepare output directory
CURRENT_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR="${OUTPUT_ROOT}/${PROJECT_NAME}-${CURRENT_DATE}"
mkdir -p "${OUTPUT_DIR}"

ARCHIVE_PATH="${OUTPUT_DIR}/${PROJECT_NAME}.xcarchive"
EXPORT_PLIST="${OUTPUT_DIR}/ExportOptions.plist"
LOG_FILE="${OUTPUT_DIR}/build.log"

box "${PROJECT_NAME} Build & Export Script"
echo ""
echo -e "${YELLOW}📦 Archiving project: ${PROJECT_NAME}${NC}"
echo "   Scheme:        ${SCHEME_NAME}"
echo "   Configuration: Release"
echo "   Export method: ${EXPORT_METHOD}"
echo "   Project path:  ${PROJECT_PATH}"
echo "   Output dir:    ${OUTPUT_DIR}"
echo "   Log file:      ${LOG_FILE}"
echo ""

# Archive with logging
echo -e "${YELLOW}⏳ Starting archive process...${NC}"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME_NAME}" \
  -configuration Release \
  archive \
  -archivePath "${ARCHIVE_PATH}" \
  2>&1 | tee "${LOG_FILE}"

# Check if archive was created
if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo -e "${RED}error: Archive was not created${NC}"
    echo -e "${RED}Check log file: ${LOG_FILE}${NC}"
    exit 1
fi

ARCHIVE_SIZE=$(du -sh "${ARCHIVE_PATH}" | cut -f1)
echo -e "${GREEN}✓ Archive created successfully (${ARCHIVE_SIZE})${NC}"

echo ""
echo -e "${YELLOW}📝 Writing ExportOptions.plist...${NC}"
cat > "${EXPORT_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

echo ""
echo -e "${YELLOW}🚀 Exporting archive as signed app...${NC}"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${OUTPUT_DIR}" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates \
  2>&1 | tee -a "${LOG_FILE}"

# Check if app was exported
APP_PATH="${OUTPUT_DIR}/${PROJECT_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}error: App was not exported${NC}"
    echo -e "${RED}Check log file: ${LOG_FILE}${NC}"
    exit 1
fi

# Get app size and version info
APP_SIZE=$(du -sh "${APP_PATH}" | cut -f1)
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "Unknown")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "Unknown")

echo ""
box "Build script finished successfully!"
echo ""
echo "📦 Application: ${PROJECT_NAME}.app"
echo "📊 Version:     ${APP_VERSION} (${APP_BUILD})"
echo "💾 Size:        ${APP_SIZE}"
echo "📂 Location:    ${OUTPUT_DIR}"
echo "📄 Build log:   ${LOG_FILE}"
echo ""

# Create a summary file
SUMMARY_FILE="${OUTPUT_DIR}/build-summary.txt"
SUMMARY_TITLE="${PROJECT_NAME} Build Summary"
cat > "${SUMMARY_FILE}" <<SUMMARY
${SUMMARY_TITLE}
$(rule "${#SUMMARY_TITLE}" '=')
Date:           $(date "+%Y-%m-%d %H:%M:%S")
Project:        ${PROJECT_NAME}
Scheme:         ${SCHEME_NAME}
Configuration:  Release
Export Method:  ${EXPORT_METHOD}
Team ID:        ${TEAM_ID}

Application Info
----------------
Version:        ${APP_VERSION}
Build:          ${APP_BUILD}
Size:           ${APP_SIZE}
Archive Size:   ${ARCHIVE_SIZE}

Output Locations
----------------
App:            ${APP_PATH}
Archive:        ${ARCHIVE_PATH}
Log:            ${LOG_FILE}
SUMMARY

echo -e "${GREEN}📋 Summary saved to: ${SUMMARY_FILE}${NC}"
echo ""

# Open output directory in Finder
open "${OUTPUT_DIR}"
