#!/bin/bash

# Test script to verify site preservation functionality

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}===== Site Preservation Test Script =====${NC}"
echo ""

# Function to list enabled sites
list_enabled_sites() {
    echo -e "${BLUE}Currently enabled sites:${NC}"
    for site in /etc/apache2/sites-enabled/*.conf; do
        if [ -L "$site" ] && [ -e "$site" ]; then
            echo "  - $(basename "$site")"
        fi
    done
    echo ""
}

# Step 1: Show current state
echo -e "${YELLOW}Step 1: Current Apache site configuration${NC}"
list_enabled_sites

# Step 2: Count enabled sites
INITIAL_COUNT=$(ls -1 /etc/apache2/sites-enabled/*.conf 2>/dev/null | wc -l)
echo -e "${GREEN}Total enabled sites: $INITIAL_COUNT${NC}"
echo ""

# Step 3: Check if nilgiristores.in is enabled
if [ -L "/etc/apache2/sites-enabled/nilgiristores.in.conf" ]; then
    echo -e "${GREEN}✓ nilgiristores.in.conf is enabled${NC}"
else
    echo -e "${RED}✗ nilgiristores.in.conf is NOT enabled${NC}"
fi

if [ -L "/etc/apache2/sites-enabled/nilgiristores.in-le-ssl.conf" ]; then
    echo -e "${GREEN}✓ nilgiristores.in-le-ssl.conf is enabled${NC}"
else
    echo -e "${RED}✗ nilgiristores.in-le-ssl.conf is NOT enabled${NC}"
fi

# Step 4: Check if goagents.space is enabled  
if [ -L "/etc/apache2/sites-enabled/goagents.space.conf" ]; then
    echo -e "${GREEN}✓ goagents.space.conf is enabled${NC}"
else
    echo -e "${RED}✗ goagents.space.conf is NOT enabled${NC}"
fi

if [ -L "/etc/apache2/sites-enabled/goagents.space-le-ssl.conf" ]; then
    echo -e "${GREEN}✓ goagents.space-le-ssl.conf is enabled${NC}"
else
    echo -e "${RED}✗ goagents.space-le-ssl.conf is NOT enabled${NC}"
fi

echo ""
echo -e "${CYAN}===== Test Complete =====${NC}"
echo ""
echo -e "${YELLOW}Note: When installing a new WordPress site, the script should now:${NC}"
echo "1. Save the list of currently enabled sites"
echo "2. Perform the installation (which may temporarily disable sites)"
echo "3. Automatically re-enable all originally enabled sites"
echo ""
echo -e "${GREEN}The fix has been applied to:${NC}"
echo "  /root/install_wordpress_on_lamp/wordpress/install_lamp_stack.sh"