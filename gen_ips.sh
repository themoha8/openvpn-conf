#!/bin/bash

output_file="ips.txt"

# clean
echo -n > "$output_file"

for ((i=0; i<256; i++)); do
	if [ $i -eq 0 ] || [ $i -eq 255 ]; then
		continue;
    fi
	echo "10.11.11.$i" >> "$output_file"
done

echo "ip addresses successful generated into $output_file"
