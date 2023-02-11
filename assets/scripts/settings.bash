# This script triggers the KEY setting in /etc/wsl.conf
test="KEY[ ]*="
currentWSL=$(cat /etc/wsl.conf)
# Check if it has [PARENT] section
if [[ $currentWSL == *"[PARENT]"* ]]; then
    if [[ $currentWSL =~ $test ]]; then
        # Replace KEY value with the new value
        sed -i 's/KEY[ ]*=[ ]*.*/KEY = VALUE/g' /etc/wsl.conf
    else
        # Add KEY value after PARENT
        sed -i 's/\[PARENT\]/\[PARENT\]\nKEY = VALUE/g' /etc/wsl.conf
    fi
else
    # Add [PARENT] section and KEY value
    echo -e "[PARENT]\nKEY = VALUE" >> /etc/wsl.conf
fi