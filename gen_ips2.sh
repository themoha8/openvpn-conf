#!/bin/bash

output_file="ips.txt"

echo -n > "$output_file"

for ((i=0; i<256; i++)); do
    for ((j=0; j<256; j++)); do
        if [[ ($i -eq 0 && $j -eq 0) || ($i -eq 255 && $j -eq 255) ]]; then
            continue;
        fi
        echo "10.48.$i.$j" >> "$output_file"
    done
done

echo "ip addresses successful generated into $output_file"